import AVFoundation
import Foundation

nonisolated final class GainBox: @unchecked Sendable {
    private let lock = NSLock()
    private var target: Float = 0.75
    private var muted = false

    func setVolume(_ value: Float) {
        lock.lock()
        target = min(1, max(0, value))
        lock.unlock()
    }

    func setMuted(_ value: Bool) {
        lock.lock()
        muted = value
        lock.unlock()
    }

    func read() -> (volume: Float, muted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (target, muted)
    }
}

nonisolated final class FloatRing: @unchecked Sendable {
    private var storage: [Float]
    private var readIndex = 0
    private var count = 0
    private var fraction: Float = 0
    private var primed = false
    private var held: Float = 0
    private let targetFill: Int
    private let lock = NSLock()
    private var appliedGain: Float = 0

    init(capacity: Int) {
        storage = [Float](repeating: 0, count: capacity)
        targetFill = max(64, capacity / 16)
    }

    func flush() {
        lock.lock()
        readIndex = 0
        count = 0
        fraction = 0
        primed = false
        held = 0
        lock.unlock()
    }

    func push(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        for sample in samples {
            if count == storage.count {
                readIndex = (readIndex + 1) % storage.count
                count -= 1
                fraction = 0
            }
            let write = (readIndex + count) % storage.count
            storage[write] = sample
            count += 1
        }
        lock.unlock()
    }

    func render(into audioBufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int, gain: GainBox) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let data = buffers.first?.mData else { return true }
        let dst = data.assumingMemoryBound(to: Float.self)
        let settings = gain.read()
        lock.lock()
        let silent = settings.muted || settings.volume < 0.001
        if silent {
            for i in 0..<frames { dst[i] = 0 }
            lock.unlock()
            return true
        }
        let error = Float(count - targetFill) / Float(max(targetFill, 1))
        let step = min(1.004, max(0.996, 1 + error * 0.002))
        var any = false
        for i in 0..<frames {
            appliedGain += (settings.volume - appliedGain) * 0.01
            if !primed {
                if count >= targetFill {
                    primed = true
                } else {
                    dst[i] = 0
                    continue
                }
            }
            if count < 2 {
                held *= 0.9
                dst[i] = held * appliedGain
                continue
            }
            let i0 = readIndex
            let i1 = (readIndex + 1) % storage.count
            let sample = storage[i0] * (1 - fraction) + storage[i1] * fraction
            held = sample
            dst[i] = sample * appliedGain
            any = true
            fraction += step
            while fraction >= 1, count > 1 {
                fraction -= 1
                readIndex = (readIndex + 1) % storage.count
                count -= 1
            }
            if fraction >= 1 { fraction = 0 }
        }
        lock.unlock()
        return !any
    }
}

nonisolated final class AudioOutput: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let ring: FloatRing
    private let gain: GainBox
    private let source: AVAudioSourceNode
    private let recorder = MP3Recorder()
    private var started = false
    private let lock = NSLock()

    init() {
        let ring = FloatRing(capacity: 48_000)
        let gain = GainBox()
        self.ring = ring
        self.gain = gain
        let format = AVAudioFormat(standardFormatWithSampleRate: DSPRates.audio, channels: 1)!
        source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let silent = ring.render(into: audioBufferList, frames: Int(frameCount), gain: gain)
            return silent ? noErr : noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.isAutoShutdownEnabled = false
    }

    func setVolume(_ value: Float) {
        gain.setVolume(value)
    }

    func setMuted(_ value: Bool) {
        gain.setMuted(value)
    }

    func push(_ samples: [Float]) {
        ring.push(samples)
        recorder.append(samples)
    }

    func startRecording(url: URL, title: String) -> String? {
        recorder.start(url: url, title: title)
    }

    func stopRecording() -> URL? {
        recorder.stop()
    }

    func recordingElapsed() -> TimeInterval {
        recorder.elapsed()
    }

    func flush() {
        ring.flush()
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        ring.flush()
        try engine.start()
        started = true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if started {
            engine.stop()
            started = false
        }
        ring.flush()
    }
}
