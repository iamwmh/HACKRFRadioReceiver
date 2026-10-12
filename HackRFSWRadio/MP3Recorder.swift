import Foundation

/// Encodes demodulated mono audio as a small CBR MP3.
/// 48 kHz in, 22.05 kHz mono out, 32 kbps: about 14 MB per hour.
nonisolated final class MP3Recorder: @unchecked Sendable {
    static let bitrate = 32

    private let queue = DispatchQueue(label: "hackrf.mp3")
    private var encoder: OpaquePointer?
    private var handle: FileHandle?
    private var url: URL?
    private var startedAt: Date?
    private var failed = false
    private var active = false
    private let state = NSLock()

    func start(url: URL, title: String) -> String? {
        queue.sync {
            guard encoder == nil else { return L10n.s("ui.alreadyRecording") }
            guard let encoder = lame_init() else { return L10n.s("ui.mp3StartFailed") }
            lame_set_num_channels(encoder, 1)
            lame_set_in_samplerate(encoder, Int32(DSPRates.audio))
            lame_set_out_samplerate(encoder, 22_050)
            lame_set_mode(encoder, MONO)
            lame_set_VBR(encoder, vbr_off)
            lame_set_brate(encoder, Int32(Self.bitrate))
            lame_set_quality(encoder, 2)
            lame_set_bWriteVbrTag(encoder, 0)
            title.withCString { cString in
                id3tag_init(encoder)
                id3tag_set_title(encoder, cString)
            }
            guard lame_init_params(encoder) >= 0 else {
                lame_close(encoder)
                return L10n.s("ui.mp3InitFailed")
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                FileManager.default.createFile(atPath: url.path, contents: nil)
                guard let handle = FileHandle(forWritingAtPath: url.path) else {
                    lame_close(encoder)
                    return L10n.s("ui.mp3FileFailed")
                }
                self.encoder = encoder
                self.handle = handle
                self.url = url
                self.startedAt = Date()
                self.failed = false
                self.state.lock()
                self.active = true
                self.state.unlock()
                return nil
            } catch {
                lame_close(encoder)
                return L10n.s("ui.mp3FileFailed")
            }
        }
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        state.lock()
        let recording = active
        state.unlock()
        guard recording else { return }
        queue.async { [samples] in
            self.encode(samples)
        }
    }

    func elapsed() -> TimeInterval {
        queue.sync {
            guard let startedAt else { return 0 }
            return Date().timeIntervalSince(startedAt)
        }
    }

    func stop() -> URL? {
        state.lock()
        active = false
        state.unlock()
        return queue.sync { () -> URL? in
            guard let encoder else { return nil }
            let saved = url
            if !failed {
                var tail = [UInt8](repeating: 0, count: 7200)
                let wrote = tail.withUnsafeMutableBufferPointer { raw -> Int32 in
                    guard let base = raw.baseAddress else { return -1 }
                    return lame_encode_flush(encoder, base, Int32(raw.count))
                }
                if wrote > 0 {
                    handle?.write(Data(tail.prefix(Int(wrote))))
                }
            }
            try? handle?.close()
            lame_close(encoder)
            self.encoder = nil
            self.handle = nil
            self.url = nil
            self.startedAt = nil
            if failed {
                if let saved { try? FileManager.default.removeItem(at: saved) }
                return nil
            }
            return saved
        }
    }

    private func encode(_ samples: [Float]) {
        guard let encoder, let handle, !failed else { return }
        let size = Int(1.25 * Double(samples.count)) + 7200
        var mp3 = [UInt8](repeating: 0, count: size)
        let wrote = samples.withUnsafeBufferPointer { pcm -> Int32 in
            guard let base = pcm.baseAddress else { return -1 }
            return mp3.withUnsafeMutableBufferPointer { raw -> Int32 in
                guard let out = raw.baseAddress else { return -1 }
                return lame_encode_buffer_ieee_float(encoder, base, base, Int32(samples.count), out, Int32(raw.count))
            }
        }
        if wrote < 0 {
            failed = true
            return
        }
        if wrote > 0 {
            handle.write(Data(mp3.prefix(Int(wrote))))
        }
    }
}
