import Foundation

nonisolated final class RadioSession: @unchecked Sendable {
    private let deviceQueue = DispatchQueue(label: "hackrf.device")
    private let lifecycle = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var dspThread: Thread?
    private var dspRunning = false
    private var paused = false
    private let stateLock = NSLock()

    private let audio = AudioOutput()
    private let demod = Demodulator()
    private let finder = StationFinder()

    private var closed = false
    private var cancelScan = false
    private var scanBusy = false
    private var sampleRate = DSPRates.listen
    private var parkedHz: Double = 0
    private var parkedMode: RadioMode = .fm

    private let scanLock = NSLock()
    private var scanState = ScanSnapshot(
        active: false,
        progress: 0,
        frequencyHz: 0,
        bandMeters: nil,
        mode: .fm,
        foundCount: 0,
        message: "",
        spectrum: [],
        freshFinds: []
    )

    private var boardName = ""
    private var firmwareName = ""
    private var serialNumber = ""

    func open(_ request: ListenRequest) -> ConnectResult {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        closed = false
        cancelScan = false

        if handle != nil {
            applyListen(request)
            return ConnectResult(ok: true, message: L10n.s("ui.receiving"), board: boardName, firmware: firmwareName, serial: serialNumber)
        }

        var err = [CChar](repeating: 0, count: 512)
        var opened: UnsafeMutableRawPointer?
        var startCode: Int32 = -1
        err.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            deviceQueue.sync {
                opened = hackrf_bridge_open(base, 512)
                guard let opened else { return }
                self.handle = opened
                self.boardName = String(cString: hackrf_bridge_board(opened))
                self.firmwareName = String(cString: hackrf_bridge_firmware(opened))
                self.serialNumber = String(cString: hackrf_bridge_serial(opened))
                startCode = hackrf_bridge_start(
                    opened,
                    DSPRates.listen,
                    UInt64(request.frequencyHz.rounded()),
                    Int32(request.gain.lna),
                    Int32(request.gain.vga),
                    Int32(request.gain.amp),
                    base,
                    512
                )
                if startCode != 0 {
                    hackrf_bridge_close(opened)
                    self.handle = nil
                } else {
                    self.sampleRate = DSPRates.listen
                }
            }
        }

        if handle == nil {
            let raw = String(cString: err)
            return ConnectResult(ok: false, message: Self.explain(raw), board: "", firmware: "", serial: "")
        }
        demod.setControls(mode: request.mode, squelchDB: request.squelchDB, deemphasis75: request.deemphasis75, reset: true)
        audio.setVolume(request.volume)
        audio.setMuted(false)
        return ConnectResult(ok: true, message: L10n.s("ui.receiving"), board: boardName, firmware: firmwareName, serial: serialNumber)
    }

    func startOutput() throws {
        try audio.start()
    }

    func startDSP() {
        stateLock.lock()
        let already = dspRunning
        stateLock.unlock()
        if already { return }
        stateLock.lock()
        dspRunning = true
        paused = false
        stateLock.unlock()
        if let handle {
            hackrf_bridge_flush(handle)
        }
        audio.flush()
        demod.reset()
        let thread = Thread { [weak self] in
            self?.dspLoop()
        }
        thread.name = "HackRF DSP"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 2 * 1024 * 1024
        dspThread = thread
        thread.start()
    }

    func shutdown() {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        closed = true
        cancelScan = true
        let deadline = Date().addingTimeInterval(4)
        while scanBusy && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        stopDSP()
        deviceQueue.sync {
            if let handle = self.handle {
                hackrf_bridge_close(handle)
                self.handle = nil
            }
        }
        audio.stop()
        sampleRate = DSPRates.listen
    }

    func retune(_ hz: Double) {
        let value = UInt64(max(1, hz.rounded()))
        deviceQueue.async { [weak self] in
            guard let self, let handle = self.handle, !self.closed else { return }
            hackrf_bridge_set_freq(handle, value)
        }
    }

    func setGain(_ gain: HardwareGain) {
        deviceQueue.async { [weak self] in
            guard let self, let handle = self.handle, !self.closed else { return }
            hackrf_bridge_set_gains(handle, Int32(gain.lna), Int32(gain.vga), Int32(gain.amp))
        }
    }

    func setAudio(volume: Float) {
        audio.setVolume(volume)
    }

    func startRecording(url: URL, title: String) -> String? {
        audio.startRecording(url: url, title: title)
    }

    func stopRecording() -> URL? {
        audio.stopRecording()
    }

    func recordingElapsed() -> TimeInterval {
        audio.recordingElapsed()
    }

    func setDSP(mode: RadioMode, squelchDB: Float, deemphasis75: Bool) {
        demod.setControls(mode: mode, squelchDB: squelchDB, deemphasis75: deemphasis75, reset: false)
    }

    func telemetry() -> ReceiverTelemetry {
        demod.telemetry()
    }

    func scanSnapshot() -> ScanSnapshot {
        scanLock.lock()
        defer { scanLock.unlock() }
        var copy = scanState
        scanState.freshFinds.removeAll(keepingCapacity: true)
        return copy
    }

    func requestCancel() {
        cancelScan = true
    }

    func parkedFrequency() -> Double {
        parkedHz
    }

    func parkedService() -> RadioMode {
        parkedMode
    }

    func scanFM(gain: HardwareGain, restoreHz: Double) {
        let centers: [Double] = [90.05e6, 94.65e6, 99.25e6, 103.85e6, 107.15e6]
        scanBusy = true
        defer {
            scanBusy = false
            cancelScan = false
        }
        guard !closed else { return }
        clearScanFinds()
        audio.setMuted(true)
        setPaused(true)
        parkedMode = .fm
        publishScan(active: true, progress: 0, frequency: centers[0], meters: nil, mode: .fm, message: L10n.s("ui.fmScanBand"), spectrum: nil, finds: [])

        if !ensureRate(DSPRates.fmScan) {
            finishHardware(gain: gain, frequency: restoreHz)
            publishScan(active: false, progress: 1, frequency: restoreHz, meters: nil, mode: .fm, message: L10n.s("ui.sampleRateFailed"), spectrum: nil, finds: [])
            return
        }

        var all: [DetectedChannel] = []
        for (index, center) in centers.enumerated() {
            if cancelScan || closed { break }
            tuneSync(center)
            discard(seconds: 0.05)
            guard let iq = readBytes(count: fftBytes(sampleRate: DSPRates.fmScan), timeout: 1.2) else {
                break
            }
            let result = finder.fmStations(iq: iq, centerHz: center, sampleRate: DSPRates.fmScan)
            all.append(contentsOf: result.channels)
            publishScan(
                active: true,
                progress: Double(index + 1) / Double(centers.count),
                frequency: center,
                meters: nil,
                mode: .fm,
                message: L10n.f("ui.fmScanCenter", center / 1_000_000),
                spectrum: result.spectrum,
                finds: result.channels
            )
        }
        let merged = merge(all, tolerance: 60_000)
        let tuned = merged.max(by: { $0.powerDB < $1.powerDB })?.frequencyHz ?? restoreHz
        parkedMode = .fm
        finishHardware(gain: gain, frequency: tuned)
        publishScan(active: false, progress: 1, frequency: tuned, meters: nil, mode: .fm, message: L10n.s("ui.fmScanDone"), spectrum: nil, finds: [])
    }

    func scanShortwave(bands: [SWBand], gain: HardwareGain, restoreHz: Double) {
        scanBusy = true
        defer {
            scanBusy = false
            cancelScan = false
        }
        guard !closed, !bands.isEmpty else { return }
        clearScanFinds()
        audio.setMuted(true)
        setPaused(true)
        parkedMode = .shortwave
        publishScan(active: true, progress: 0, frequency: bands[0].centerHz, meters: bands[0].meters, mode: .shortwave, message: L10n.s("ui.swScanStart"), spectrum: nil, finds: [])

        if !ensureRate(DSPRates.listen) {
            finishHardware(gain: gain, frequency: restoreHz)
            publishScan(active: false, progress: 1, frequency: restoreHz, meters: nil, mode: .shortwave, message: L10n.s("ui.sampleRateFailed"), spectrum: nil, finds: [])
            return
        }

        var strongest: DetectedChannel?
        for (index, band) in bands.enumerated() {
            if cancelScan || closed { break }
            let center = band.centerHz + 7_500
            tuneSync(center)
            discard(seconds: 0.04)
            publishScan(
                active: true,
                progress: Double(index) / Double(bands.count),
                frequency: band.centerHz,
                meters: band.meters,
                mode: .shortwave,
                message: L10n.f("ui.swBand", Int64(band.meters)),
                spectrum: nil,
                finds: []
            )
            guard let iq = readBytes(count: fftBytes(sampleRate: DSPRates.listen), timeout: 1.2) else {
                break
            }
            let result = finder.swStations(iq: iq, centerHz: center, sampleRate: DSPRates.listen, band: band)
            if let best = result.channels.max(by: { $0.powerDB < $1.powerDB }) {
                if strongest == nil || best.powerDB > strongest!.powerDB {
                    strongest = best
                }
            }
            publishScan(
                active: true,
                progress: Double(index + 1) / Double(bands.count),
                frequency: band.centerHz,
                meters: band.meters,
                mode: .shortwave,
                message: L10n.f("ui.swBandCarriers", Int64(band.meters), Int64(result.channels.count)),
                spectrum: result.spectrum,
                finds: result.channels
            )
        }
        let tuned = strongest?.frequencyHz ?? restoreHz
        parkedMode = .shortwave
        finishHardware(gain: gain, frequency: tuned)
        publishScan(active: false, progress: 1, frequency: tuned, meters: SWBand.containing(tuned)?.meters, mode: .shortwave, message: L10n.s("ui.swScanDone"), spectrum: nil, finds: [])
    }

    func scanVHF(services: [RadioMode], gain: HardwareGain, restoreHz: Double, restoreMode: RadioMode) {
        scanBusy = true
        defer {
            scanBusy = false
            cancelScan = false
        }
        let plan = services.flatMap { service -> [(RadioMode, Double, Double, Double)] in
            let limits = Self.vhfLimits(service)
            return Self.scanCenters(low: limits.low, high: limits.high, rate: DSPRates.fmScan, spacing: 25_000).map {
                (service, $0, limits.low, limits.high)
            }
        }
        guard !closed, !plan.isEmpty else { return }
        clearScanFinds()
        audio.setMuted(true)
        setPaused(true)
        parkedMode = restoreMode
        publishScan(
            active: true,
            progress: 0,
            frequency: plan[0].1,
            meters: nil,
            mode: plan[0].0,
            message: L10n.s("ui.vhfScanStart"),
            spectrum: nil,
            finds: []
        )

        if !ensureRate(DSPRates.fmScan) {
            finishHardware(gain: gain, frequency: restoreHz)
            publishScan(active: false, progress: 1, frequency: restoreHz, meters: nil, mode: restoreMode, message: L10n.s("ui.sampleRateFailed"), spectrum: nil, finds: [])
            return
        }

        var ranked: [(RadioMode, DetectedChannel)] = []
        let capture = 8_000_000
        for (index, item) in plan.enumerated() {
            if cancelScan || closed { break }
            let (service, center, low, high) = item
            tuneSync(center)
            discard(seconds: 0.06)
            let title = service == .marine ? L10n.s("ui.marineShort") : L10n.s("ui.airShort")
            publishScan(
                active: true,
                progress: Double(index) / Double(plan.count),
                frequency: center,
                meters: nil,
                mode: service,
                message: L10n.f("ui.vhfScanCenter", title, center / 1_000_000),
                spectrum: nil,
                finds: []
            )
            guard let iq = readBytes(count: capture, timeout: 2.8) else { break }
            let result = finder.vhfChannels(
                iq: iq,
                centerHz: center,
                sampleRate: DSPRates.fmScan,
                lowHz: low,
                highHz: high,
                spacingHz: 25_000
            )
            ranked.append(contentsOf: result.channels.map { (service, $0) })
            publishScan(
                active: true,
                progress: Double(index + 1) / Double(plan.count),
                frequency: center,
                meters: nil,
                mode: service,
                message: L10n.f("ui.vhfScanChannels", title, center / 1_000_000, Int64(result.channels.count)),
                spectrum: result.spectrum,
                finds: result.channels
            )
        }
        let best = ranked.max { $0.1.powerDB < $1.1.powerDB }
        let tuned = best?.1.frequencyHz ?? restoreHz
        parkedMode = best?.0 ?? restoreMode
        finishHardware(gain: gain, frequency: tuned)
        publishScan(active: false, progress: 1, frequency: tuned, meters: nil, mode: parkedMode, message: L10n.s("ui.vhfScanDone"), spectrum: nil, finds: [])
    }

    private static func vhfLimits(_ mode: RadioMode) -> (low: Double, high: Double) {
        switch mode {
        case .marine:
            return (156_000_000, 162_025_000)
        case .air:
            return (118_000_000, 136_975_000)
        default:
            return (118_000_000, 136_975_000)
        }
    }

    private static func scanCenters(low: Double, high: Double, rate: Double, spacing: Double) -> [Double] {
        let half = rate / 2 - 1_200_000
        guard half > spacing else { return [((low + high) / 2 / spacing).rounded() * spacing + spacing / 2] }
        var coveredUntil = low
        var centers: [Double] = []
        while coveredUntil < high - spacing && centers.count < 8 {
            let limited = min(coveredUntil + half, high - half)
            var center = (limited / spacing).rounded() * spacing + spacing / 2
            if center - half > coveredUntil + spacing {
                center = coveredUntil + half
            }
            if let last = centers.last, abs(last - center) < spacing {
                break
            }
            centers.append(center)
            let next = center + half
            if next <= coveredUntil { break }
            coveredUntil = next - spacing
        }
        return centers
    }

    private func finishHardware(gain: HardwareGain, frequency: Double) {
        parkedHz = frequency
        if closed { return }
        _ = ensureRate(DSPRates.listen)
        tuneSync(frequency)
        if let handle, !closed {
            deviceQueue.sync {
                hackrf_bridge_set_gains(handle, Int32(gain.lna), Int32(gain.vga), Int32(gain.amp))
            }
        }
        discard(seconds: 0.03)
        demod.reset()
        audio.flush()
        audio.setMuted(false)
        setPaused(false)
    }

    private func applyListen(_ request: ListenRequest) {
        demod.setControls(mode: request.mode, squelchDB: request.squelchDB, deemphasis75: request.deemphasis75, reset: true)
        audio.setVolume(request.volume)
        audio.setMuted(false)
        _ = ensureRate(DSPRates.listen)
        tuneSync(request.frequencyHz)
        setGainSync(request.gain)
    }

    @discardableResult
    private func ensureRate(_ rate: Double) -> Bool {
        if abs(sampleRate - rate) < 1 { return handle != nil }
        var ok = false
        deviceQueue.sync {
            guard let handle, !closed else { return }
            let code = hackrf_bridge_set_sample_rate(handle, rate)
            ok = code == 0
            if ok { sampleRate = rate }
        }
        return ok
    }

    private func tuneSync(_ hz: Double) {
        let value = UInt64(max(1, hz.rounded()))
        deviceQueue.sync {
            guard let handle, !closed else { return }
            hackrf_bridge_set_freq(handle, value)
        }
    }

    private func setGainSync(_ gain: HardwareGain) {
        deviceQueue.sync {
            guard let handle, !closed else { return }
            hackrf_bridge_set_gains(handle, Int32(gain.lna), Int32(gain.vga), Int32(gain.amp))
        }
    }

    private func setPaused(_ value: Bool) {
        stateLock.lock()
        paused = value
        stateLock.unlock()
        if value {
            Thread.sleep(forTimeInterval: 0.02)
            if let handle { hackrf_bridge_flush(handle) }
        }
    }

    private func isPaused() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return paused
    }

    private func fftBytes(sampleRate: Double) -> Int {
        _ = sampleRate
        return 16_384 * 12 * 2
    }

    private func clearScanFinds() {
        scanLock.lock()
        scanState.foundCount = 0
        scanState.freshFinds.removeAll(keepingCapacity: true)
        scanLock.unlock()
    }

    private func discard(seconds: Double) {
        let bytes = Int(sampleRate * seconds) * 2
        _ = readBytes(count: max(bytes, 4096), timeout: seconds + 0.4)
    }

    private func readBytes(count: Int, timeout: TimeInterval) -> [UInt8]? {
        guard let handle else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(count)
        let deadline = Date().addingTimeInterval(timeout)
        while out.count < count {
            if cancelScan || closed { return nil }
            if Date() > deadline { return out.count > count / 3 ? out : nil }
            let byteCount = min(262_144, count - out.count)
            var chunk = [UInt8](repeating: 0, count: byteCount)
            let n = chunk.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return 0 }
                return hackrf_bridge_read(handle, base.assumingMemoryBound(to: UInt8.self), Int32(byteCount))
            }
            if n > 0 {
                out.append(contentsOf: chunk.prefix(Int(n)))
            } else {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        return out
    }

    private func publishScan(active: Bool, progress: Double, frequency: Double, meters: Int?, mode: RadioMode, message: String, spectrum: [Float]?, finds: [DetectedChannel]) {
        scanLock.lock()
        scanState.active = active
        scanState.progress = progress
        scanState.frequencyHz = frequency
        scanState.bandMeters = meters
        scanState.mode = mode
        scanState.message = message
        if let spectrum {
            scanState.spectrum = spectrum
        }
        scanState.freshFinds.append(contentsOf: finds)
        scanState.foundCount += finds.count
        if !active {
            scanState.foundCount = scanState.foundCount
        }
        scanLock.unlock()
    }

    func resetScanCounter() {
        scanLock.lock()
        scanState.foundCount = 0
        scanState.freshFinds.removeAll()
        scanState.progress = 0
        scanState.active = true
        scanLock.unlock()
    }

    private func merge(_ channels: [DetectedChannel], tolerance: Double) -> [DetectedChannel] {
        var merged: [DetectedChannel] = []
        for channel in channels.sorted(by: { $0.powerDB > $1.powerDB }) {
            if let index = merged.firstIndex(where: { abs($0.frequencyHz - channel.frequencyHz) < tolerance }) {
                if channel.powerDB > merged[index].powerDB {
                    merged[index] = channel
                }
            } else {
                merged.append(channel)
            }
        }
        return merged.sorted { $0.frequencyHz < $1.frequencyHz }
    }

    private func stopDSP() {
        stateLock.lock()
        dspRunning = false
        stateLock.unlock()
        let deadline = Date().addingTimeInterval(1.5)
        while let thread = dspThread, thread.isExecuting, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        dspThread = nil
    }

    private func dspLoop() {
        var scratch = [UInt8](repeating: 0, count: 65_536)
        while true {
            stateLock.lock()
            let running = dspRunning
            let hold = paused
            stateLock.unlock()
            if !running { break }
            if hold || handle == nil {
                Thread.sleep(forTimeInterval: 0.008)
                continue
            }
            guard let handle else { continue }
            let scratchCount = scratch.count
            let n = scratch.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return 0 }
                return hackrf_bridge_read(handle, base.assumingMemoryBound(to: UInt8.self), Int32(scratchCount))
            }
            if n < 4_096 {
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            let audioSamples = demod.process(Array(scratch.prefix(Int(n))))
            if !audioSamples.isEmpty {
                audio.push(audioSamples)
            }
        }
    }

    private static func explain(_ raw: String) -> String {
        if raw.contains("NOT_FOUND") || raw.isEmpty {
            return L10n.s("ui.hackrfMissing")
        }
        if raw.contains("BUSY") || raw.contains("LIBUSB") {
            return L10n.s("ui.hackrfBusy")
        }
        return L10n.f("ui.hackrfOpenFailed", raw)
    }
}
