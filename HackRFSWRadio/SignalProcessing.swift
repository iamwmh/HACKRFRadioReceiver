import Accelerate
import Foundation

nonisolated enum DSPRates {
    static let listen = 2_400_000.0
    static let fmScan = 8_000_000.0
    static let audio = 48_000.0
    static let stage1 = 10
    static let stage2 = 5
    static let channelRate = listen / Double(stage1)
}

nonisolated enum FIRDesign {
    static func lowpass(taps: Int, cutoffHz: Double, sampleRate: Double) -> [Float] {
        var coeffs = [Float](repeating: 0, count: taps)
        let fc = cutoffHz / sampleRate
        let m = Double(taps - 1)
        for i in 0..<taps {
            let x = Double(i) - m / 2
            let sinc = x == 0 ? 2 * fc : sin(2 * .pi * fc * x) / (.pi * x)
            let w = 0.42 - 0.5 * cos(2 * .pi * Double(i) / m) + 0.08 * cos(4 * .pi * Double(i) / m)
            coeffs[i] = Float(sinc * w)
        }
        let sum = coeffs.reduce(0, +)
        guard sum != 0 else { return coeffs }
        return coeffs.map { $0 / sum }
    }
}

nonisolated final class StreamingDecimator: @unchecked Sendable {
    let factor: Int
    let coeffs: [Float]
    private var history: [Float] = []

    init(factor: Int, taps: Int, cutoffHz: Double, sampleRate: Double) {
        self.factor = factor
        self.coeffs = FIRDesign.lowpass(taps: taps, cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    func reset() {
        history.removeAll(keepingCapacity: true)
    }

    func process(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }
        var data = history
        data.append(contentsOf: input)
        let taps = coeffs.count
        guard data.count >= taps else {
            history = data
            return []
        }
        let nOut = (data.count - taps) / factor + 1
        guard nOut > 0 else {
            history = data
            return []
        }
        var output = [Float](repeating: 0, count: nOut)
        data.withUnsafeBufferPointer { src in
            coeffs.withUnsafeBufferPointer { fir in
                guard let srcBase = src.baseAddress, let firBase = fir.baseAddress else { return }
                vDSP_desamp(
                    srcBase,
                    vDSP_Stride(factor),
                    firBase,
                    &output,
                    vDSP_Length(nOut),
                    vDSP_Length(taps)
                )
            }
        }
        let consumed = nOut * factor
        if consumed < data.count {
            history = Array(data[consumed...])
        } else {
            history.removeAll(keepingCapacity: true)
        }
        return output
    }
}

nonisolated final class ComplexFFT: @unchecked Sendable {
    let count: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]

    init(log2n: vDSP_Length) {
        self.log2n = log2n
        self.count = 1 << log2n
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(FFT_RADIX2)) else {
            fatalError("无法创建 FFT")
        }
        self.setup = setup
        self.window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func power(i: UnsafePointer<Float>, q: UnsafePointer<Float>) -> [Float] {
        var real = [Float](repeating: 0, count: count)
        var imag = [Float](repeating: 0, count: count)
        for k in 0..<count {
            real[k] = i[k] * window[k]
            imag[k] = q[k] * window[k]
        }
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                guard let r = rp.baseAddress, let im = ip.baseAddress else { return }
                var split = DSPSplitComplex(realp: r, imagp: im)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        var realSq = [Float](repeating: 0, count: count)
        var imagSq = [Float](repeating: 0, count: count)
        var mag = [Float](repeating: 0, count: count)
        vDSP_vsq(real, 1, &realSq, 1, vDSP_Length(count))
        vDSP_vsq(imag, 1, &imagSq, 1, vDSP_Length(count))
        vDSP_vadd(realSq, 1, imagSq, 1, &mag, 1, vDSP_Length(count))
        return mag
    }
}

nonisolated enum SpectrumImage {
    static func trace(power: [Float], columns: Int) -> [Float] {
        guard power.count > 4, columns > 4 else {
            return Array(repeating: 0.08, count: max(columns, 1))
        }
        let n = power.count
        let half = n / 2
        var shifted = [Float](repeating: 0, count: n)
        for i in 0..<n {
            shifted[i] = power[(i + half) % n]
        }
        var grouped = [Float](repeating: 0, count: columns)
        let span = Double(n) / Double(columns)
        for c in 0..<columns {
            let a = Int(Double(c) * span)
            let b = min(n, max(a + 1, Int(Double(c + 1) * span)))
            var sum: Float = 0
            for i in a..<b { sum += shifted[i] }
            grouped[c] = sum / Float(b - a)
        }
        let db = grouped.map { 10 * log10(Double($0) + 1e-16) }
        let sorted = db.sorted()
        let noise = sorted[sorted.count / 5]
        let top = noise + 32
        return db.map { value in
            let t = (value - noise) / (top - noise)
            return Float(min(1, max(0.04, t)))
        }
    }
}

nonisolated final class Demodulator: @unchecked Sendable {
    private let stageI: StreamingDecimator
    private let stageQ: StreamingDecimator
    private let narrowI: StreamingDecimator
    private let narrowQ: StreamingDecimator
    private let fmAudio: StreamingDecimator
    private let nfmAudio: StreamingDecimator
    private let amI: StreamingDecimator
    private let amQ: StreamingDecimator
    private let spectrumFFT = ComplexFFT(log2n: 10)

    private var mode: RadioMode = .fm
    private var squelchDB: Float = -120
    private var deemphasis75 = false

    private var prevI: Float = 0
    private var prevQ: Float = 0
    private var dcI: Float = 0
    private var dcQ: Float = 0
    private var hpX: Float = 0
    private var hpY: Float = 0
    private var deY: Float = 0
    private var amLevel: Float = 0.05
    private var gate: Float = 1
    private var meter: Float = -90
    private var needsReset = false
    private var specI: [Float] = []
    private var specQ: [Float] = []
    private var spectrum: [Float] = Array(repeating: 0.08, count: 96)
    private var lastClip: Float = 0
    private let lock = NSLock()

    init() {
        let channel = DSPRates.channelRate
        stageI = StreamingDecimator(factor: DSPRates.stage1, taps: 255, cutoffHz: 95_000, sampleRate: DSPRates.listen)
        stageQ = StreamingDecimator(factor: DSPRates.stage1, taps: 255, cutoffHz: 95_000, sampleRate: DSPRates.listen)
        narrowI = StreamingDecimator(factor: DSPRates.stage1, taps: 255, cutoffHz: 10_000, sampleRate: DSPRates.listen)
        narrowQ = StreamingDecimator(factor: DSPRates.stage1, taps: 255, cutoffHz: 10_000, sampleRate: DSPRates.listen)
        fmAudio = StreamingDecimator(factor: DSPRates.stage2, taps: 161, cutoffHz: 12_500, sampleRate: channel)
        nfmAudio = StreamingDecimator(factor: DSPRates.stage2, taps: 161, cutoffHz: 3_400, sampleRate: channel)
        amI = StreamingDecimator(factor: DSPRates.stage2, taps: 201, cutoffHz: 6_000, sampleRate: channel)
        amQ = StreamingDecimator(factor: DSPRates.stage2, taps: 201, cutoffHz: 6_000, sampleRate: channel)
    }

    func setControls(mode: RadioMode, squelchDB: Float, deemphasis75: Bool, reset: Bool) {
        lock.lock()
        if self.mode != mode || reset {
            needsReset = true
        }
        self.mode = mode
        self.squelchDB = squelchDB
        self.deemphasis75 = deemphasis75
        lock.unlock()
    }

    func reset() {
        stageI.reset()
        stageQ.reset()
        narrowI.reset()
        narrowQ.reset()
        fmAudio.reset()
        nfmAudio.reset()
        amI.reset()
        amQ.reset()
        prevI = 0
        prevQ = 0
        dcI = 0
        dcQ = 0
        hpX = 0
        hpY = 0
        deY = 0
        amLevel = 0.05
        gate = 1
        specI.removeAll(keepingCapacity: true)
        specQ.removeAll(keepingCapacity: true)
    }

    func telemetry() -> ReceiverTelemetry {
        lock.lock()
        defer { lock.unlock() }
        return ReceiverTelemetry(signalDB: Double(meter), spectrum: spectrum, clipRatio: lastClip)
    }

    func process(_ bytes: [UInt8]) -> [Float] {
        let prelude = readControls()
        if prelude.reset {
            reset()
        }
        let pairs = bytes.count / 2
        guard pairs > 32 else { return [] }

        var iChan = [Float](repeating: 0, count: pairs)
        var qChan = [Float](repeating: 0, count: pairs)
        var clips = 0
        for n in 0..<pairs {
            let iv = Int8(bitPattern: bytes[n * 2])
            let qv = Int8(bitPattern: bytes[n * 2 + 1])
            if abs(Int(iv)) >= 126 || abs(Int(qv)) >= 126 { clips += 1 }
            iChan[n] = Float(iv) / 128
            qChan[n] = Float(qv) / 128
        }
        lastClip = Float(clips) / Float(pairs)

        var meanI: Float = 0
        var meanQ: Float = 0
        vDSP_meanv(iChan, 1, &meanI, vDSP_Length(pairs))
        vDSP_meanv(qChan, 1, &meanQ, vDSP_Length(pairs))
        dcI += 0.25 * (meanI - dcI)
        dcQ += 0.25 * (meanQ - dcQ)
        var negI = -dcI
        var negQ = -dcQ
        vDSP_vsadd(iChan, 1, &negI, &iChan, 1, vDSP_Length(pairs))
        vDSP_vsadd(qChan, 1, &negQ, &qChan, 1, vDSP_Length(pairs))

        let narrow = prelude.mode == .air || prelude.mode == .marine
        let iDec = (narrow ? narrowI : stageI).process(iChan)
        let qDec = (narrow ? narrowQ : stageQ).process(qChan)
        let n = min(iDec.count, qDec.count)
        guard n > 8 else { return [] }

        var power: Float = 0
        var pi: Float = 0
        var pq: Float = 0
        vDSP_dotpr(iDec, 1, iDec, 1, &pi, vDSP_Length(n))
        vDSP_dotpr(qDec, 1, qDec, 1, &pq, vDSP_Length(n))
        power = (pi + pq) / Float(n)
        let instant = 10 * log10(power + 1e-12)
        meter += 0.18 * (instant - meter)

        specI.append(contentsOf: iDec.prefix(n))
        specQ.append(contentsOf: qDec.prefix(n))
        let fftCount = spectrumFFT.count
        if specI.count >= fftCount {
            let start = specI.count - fftCount
            let mag = specI.withUnsafeBufferPointer { ip in
                specQ.withUnsafeBufferPointer { qp -> [Float] in
                    guard let iBase = ip.baseAddress, let qBase = qp.baseAddress else { return [] }
                    return spectrumFFT.power(i: iBase.advanced(by: start), q: qBase.advanced(by: start))
                }
            }
            if !mag.isEmpty {
                let trace = SpectrumImage.trace(power: mag, columns: 96)
                lock.lock()
                spectrum = trace
                lock.unlock()
            }
            specI.removeAll(keepingCapacity: true)
            specQ.removeAll(keepingCapacity: true)
        }

        let targetGate: Float = instant >= prelude.squelch + 1.5 ? 1 : (instant <= prelude.squelch - 1.5 ? 0 : gate)
        switch prelude.mode {
        case .fm:
            return demodFM(i: iDec, q: qDec, count: n, deemphasis75: prelude.de75, narrow: false, targetGate: targetGate)
        case .marine:
            return demodFM(i: iDec, q: qDec, count: n, deemphasis75: false, narrow: true, targetGate: targetGate)
        case .shortwave, .air:
            return demodAM(i: iDec, q: qDec, count: n, targetGate: targetGate)
        }
    }

    private func readControls() -> (mode: RadioMode, squelch: Float, de75: Bool, reset: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let reset = needsReset
        needsReset = false
        return (mode, squelchDB, deemphasis75, reset)
    }

    private func demodFM(i: [Float], q: [Float], count: Int, deemphasis75: Bool, narrow: Bool, targetGate: Float) -> [Float] {
        var phase = [Float](repeating: 0, count: count)
        var pi = prevI
        var pq = prevQ
        let deviation = narrow ? 5_000.0 : 75_000.0
        let emphasis = narrow ? 1.15 : 1.7
        let scale = Float(DSPRates.channelRate / (2 * Double.pi * deviation)) * Float(emphasis)
        for n in 0..<count {
            let ii = i[n]
            let qq = q[n]
            let real = ii * pi + qq * pq
            let imag = qq * pi - ii * pq
            phase[n] = atan2(imag, real) * scale
            pi = ii
            pq = qq
        }
        prevI = pi
        prevQ = pq
        let audio = (narrow ? nfmAudio : fmAudio).process(phase)
        return shape(audio, deemphasis75: deemphasis75, am: false, targetGate: targetGate)
    }

    private func demodAM(i: [Float], q: [Float], count: Int, targetGate: Float) -> [Float] {
        let ii = amI.process(Array(i.prefix(count)))
        let qq = amQ.process(Array(q.prefix(count)))
        let n = min(ii.count, qq.count)
        guard n > 0 else { return [] }
        var env = [Float](repeating: 0, count: n)
        for k in 0..<n {
            env[k] = sqrt(ii[k] * ii[k] + qq[k] * qq[k])
        }
        return shape(env, deemphasis75: false, am: true, targetGate: targetGate)
    }

    private func shape(_ input: [Float], deemphasis75: Bool, am: Bool, targetGate: Float) -> [Float] {
        guard !input.isEmpty else { return [] }
        let tau = deemphasis75 ? 75e-6 : 50e-6
        let deA = Float(1 - exp(-1.0 / (DSPRates.audio * tau)))
        let hpR = Float(exp(-2 * Double.pi * 40 / DSPRates.audio))
        var output = [Float](repeating: 0, count: input.count)
        for n in 0..<input.count {
            var x = input[n]
            if am {
                amLevel = amLevel * 0.9992 + abs(x) * 0.0008
                let gain = min(14, 0.22 / max(amLevel, 0.008))
                x = (x - amLevel) * gain
            }
            let hp = hpR * hpY + (x - hpX)
            hpX = x
            hpY = hp
            var y = hp
            if !am {
                deY += deA * (y - deY)
                y = deY
            }
            gate += (targetGate - gate) * 0.004
            y *= gate
            let level = abs(y)
            if level > 0.8 {
                let shaped = 0.8 + 0.18 * (1 - exp(-(level - 0.8) * 6))
                y = y < 0 ? -shaped : shaped
            }
            output[n] = y
        }
        return output
    }
}

nonisolated final class StationFinder: @unchecked Sendable {
    private let fft = ComplexFFT(log2n: 14)

    func fmStations(iq: [UInt8], centerHz: Double, sampleRate: Double) -> (channels: [DetectedChannel], spectrum: [Float]) {
        guard var power = averagedPower(iq: iq, sampleRate: sampleRate) else {
            return ([], Array(repeating: 0.08, count: 128))
        }
        let n = power.count
        let binHz = sampleRate / Double(n)
        let dcBins = max(2, Int(12_000 / binHz))
        for offset in -dcBins...dcBins {
            power[(offset + n) % n] = 0
        }
        let halfBins = max(1, Int(80_000 / binHz))
        var measured: [(Double, Double)] = []
        var freq = 87_500_000.0
        while freq <= 108_000_000.0 + 1 {
            if abs(freq - centerHz) < sampleRate * 0.5 - 1_250_000 {
                let bin = binIndex(freq: freq, center: centerHz, rate: sampleRate, n: n)
                var sum: Float = 0
                var used = 0
                for offset in -halfBins...halfBins {
                    let b = (bin + offset + n) % n
                    sum += power[b]
                    used += 1
                }
                let avg = sum / Float(max(used, 1))
                let db = 10 * log10(Double(avg) + 1e-20)
                measured.append((freq, db))
            }
            freq += 100_000
        }
        let spectrum = SpectrumImage.trace(power: power, columns: 128)
        guard measured.count >= 8 else { return ([], spectrum) }
        let noise = percentile(measured.map(\.1), p: 0.30)
        var found: [DetectedChannel] = []
        for i in 0..<measured.count {
            let db = measured[i].1
            if db < noise + 8 { continue }
            if i > 0, abs(measured[i].0 - measured[i - 1].0) < 150_000, measured[i - 1].1 >= db {
                continue
            }
            if i + 1 < measured.count, abs(measured[i + 1].0 - measured[i].0) < 150_000, measured[i + 1].1 > db {
                continue
            }
            found.append(DetectedChannel(frequencyHz: measured[i].0, powerDB: db))
        }
        return (found, spectrum)
    }

    func swStations(iq: [UInt8], centerHz: Double, sampleRate: Double, band: SWBand) -> (channels: [DetectedChannel], spectrum: [Float]) {
        guard var power = averagedPower(iq: iq, sampleRate: sampleRate) else {
            return ([], Array(repeating: 0.08, count: 128))
        }
        let n = power.count
        let binHz = sampleRate / Double(n)
        let dcBins = max(2, Int(8_000 / binHz))
        for offset in -dcBins...dcBins {
            power[(offset + n) % n] = 0
        }
        let local = max(3, Int(900 / binHz))
        let inner = max(local + 4, Int(2_500 / binHz))
        let outer = max(inner + 8, Int(12_000 / binHz))
        var peaks: [DetectedChannel] = []
        for bin in 0..<n {
            let signed = bin <= n / 2 ? bin : bin - n
            let freq = centerHz + Double(signed) * binHz
            if abs(Double(signed) * binHz) < 8_000 { continue }
            if freq < band.lowHz || freq > band.highHz { continue }
            let db = 10 * log10(Double(power[bin]) + 1e-20)
            var isMax = true
            for offset in -local...local where offset != 0 {
                let other = power[(bin + offset + n) % n]
                if other > power[bin] {
                    isMax = false
                    break
                }
            }
            if !isMax { continue }
            var neighborhood: [Float] = []
            neighborhood.reserveCapacity(outer * 2)
            for offset in -outer...outer {
                let distance = abs(offset)
                if distance < inner { continue }
                neighborhood.append(power[(bin + offset + n) % n])
            }
            guard neighborhood.count > 8 else { continue }
            let noise = percentile(neighborhood.map { 10 * log10(Double($0) + 1e-20) }, p: 0.5)
            if db < noise + 11 { continue }
            let snapped = (freq / 1_000).rounded() * 1_000
            peaks.append(DetectedChannel(frequencyHz: snapped, powerDB: db))
        }
        peaks.sort { $0.powerDB > $1.powerDB }
        var merged: [DetectedChannel] = []
        for peak in peaks {
            if merged.contains(where: { abs($0.frequencyHz - peak.frequencyHz) < 4_000 }) {
                continue
            }
            merged.append(peak)
        }
        merged.sort { $0.frequencyHz < $1.frequencyHz }
        return (merged, SpectrumImage.trace(power: power, columns: 128))
    }

    func vhfChannels(
        iq: [UInt8],
        centerHz: Double,
        sampleRate: Double,
        lowHz: Double,
        highHz: Double,
        spacingHz: Double
    ) -> (channels: [DetectedChannel], spectrum: [Float]) {
        guard var power = heldPower(iq: iq, hopsWanted: 28) else {
            return ([], Array(repeating: 0.08, count: 128))
        }
        let n = power.count
        let binHz = sampleRate / Double(n)
        let dcBins = max(2, Int(8_000 / binHz))
        for offset in -dcBins...dcBins {
            power[(offset + n) % n] = 0
        }
        let halfBins = max(1, Int(4_500 / binHz))
        let usable = sampleRate * 0.5 - 1_200_000
        var measured: [(Double, Double)] = []
        var freq = (lowHz / spacingHz).rounded(.up) * spacingHz
        while freq <= highHz + 1 {
            if abs(freq - centerHz) < usable {
                let bin = binIndex(freq: freq, center: centerHz, rate: sampleRate, n: n)
                var sum: Float = 0
                var used = 0
                for offset in -halfBins...halfBins {
                    sum += power[(bin + offset + n) % n]
                    used += 1
                }
                let avg = sum / Float(max(used, 1))
                measured.append((freq, 10 * log10(Double(avg) + 1e-20)))
            }
            freq += spacingHz
        }
        let spectrum = SpectrumImage.trace(power: power, columns: 128)
        guard measured.count >= 6 else { return ([], spectrum) }
        let noise = percentile(measured.map(\.1), p: 0.55)
        var found: [DetectedChannel] = []
        for i in 0..<measured.count {
            let db = measured[i].1
            if db < noise + 10 { continue }
            if i > 0, measured[i - 1].1 >= db { continue }
            if i + 1 < measured.count, measured[i + 1].1 > db { continue }
            found.append(DetectedChannel(frequencyHz: measured[i].0, powerDB: db))
        }
        found.sort { $0.powerDB > $1.powerDB }
        if found.count > 24 {
            found = Array(found.prefix(24))
        }
        found.sort { $0.frequencyHz < $1.frequencyHz }
        return (found, spectrum)
    }

    private func heldPower(iq: [UInt8], hopsWanted: Int) -> [Float]? {
        let n = fft.count
        let pairs = iq.count / 2
        guard pairs >= n else { return nil }
        let hops = min(hopsWanted, pairs / n)
        guard hops >= 1 else { return nil }
        var accum = [Float](repeating: 0, count: n)
        var seeded = false
        var iBuf = [Float](repeating: 0, count: n)
        var qBuf = [Float](repeating: 0, count: n)
        let stride = max(n, (pairs - n) / max(hops - 1, 1))
        for hop in 0..<hops {
            let base = min(hop * stride, pairs - n)
            for k in 0..<n {
                let iv = Int8(bitPattern: iq[(base + k) * 2])
                let qv = Int8(bitPattern: iq[(base + k) * 2 + 1])
                iBuf[k] = Float(iv) / 128
                qBuf[k] = Float(qv) / 128
            }
            let mag = iBuf.withUnsafeBufferPointer { ip in
                qBuf.withUnsafeBufferPointer { qp -> [Float] in
                    guard let iBase = ip.baseAddress, let qBase = qp.baseAddress else { return [] }
                    return fft.power(i: iBase, q: qBase)
                }
            }
            guard mag.count == n else { continue }
            if !seeded {
                accum = mag
                seeded = true
            } else {
                vDSP_vmax(accum, 1, mag, 1, &accum, 1, vDSP_Length(n))
            }
        }
        return seeded ? accum : nil
    }

    private func averagedPower(iq: [UInt8], sampleRate: Double) -> [Float]? {
        let n = fft.count
        let pairs = iq.count / 2
        let hops = pairs / n
        guard hops >= 1 else { return nil }
        var accum = [Float](repeating: 0, count: n)
        var iBuf = [Float](repeating: 0, count: n)
        var qBuf = [Float](repeating: 0, count: n)
        let usedHops = min(hops, 12)
        for hop in 0..<usedHops {
            let base = hop * n
            for k in 0..<n {
                let iv = Int8(bitPattern: iq[(base + k) * 2])
                let qv = Int8(bitPattern: iq[(base + k) * 2 + 1])
                iBuf[k] = Float(iv) / 128
                qBuf[k] = Float(qv) / 128
            }
            let mag = iBuf.withUnsafeBufferPointer { ip in
                qBuf.withUnsafeBufferPointer { qp -> [Float] in
                    guard let iBase = ip.baseAddress, let qBase = qp.baseAddress else { return [] }
                    return fft.power(i: iBase, q: qBase)
                }
            }
            guard mag.count == n else { continue }
            vDSP_vadd(accum, 1, mag, 1, &accum, 1, vDSP_Length(n))
        }
        var scale = Float(1) / Float(usedHops)
        vDSP_vsmul(accum, 1, &scale, &accum, 1, vDSP_Length(n))
        _ = sampleRate
        return accum
    }

    private func binIndex(freq: Double, center: Double, rate: Double, n: Int) -> Int {
        let binHz = rate / Double(n)
        var k = Int(((freq - center) / binHz).rounded())
        if k < 0 { k += n }
        return (k % n + n) % n
    }

    private func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }
}
