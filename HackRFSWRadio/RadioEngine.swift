import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RadioEngine {
    let session = RadioSession()

    var mode: RadioMode
    var fmFrequency: Double
    var swFrequency: Double
    var airFrequency: Double
    var marineFrequency: Double
    var isOn = false
    var isPowering = false
    var isScanning = false
    var statusText = L10n.s("ui.notConnected")
    var board = ""
    var firmware = ""
    var serial = ""
    var signalDB = -120.0
    var spectrum: [Float] = Array(repeating: 0.06, count: 96)
    var clipped = false
    var volume = 0.75
    var squelchDB = -90.0
    var fmGain = 0.34
    var swGain = 0.68
    var vhfGain = 0.62
    var agcEnabled = true
    var deemphasis75 = false
    var fine = false
    var stations: [SavedStation] = []
    var scanProgress = 0.0
    var scanFrequency = 0.0
    var scanMeters: Int?
    var scanService: RadioMode = .fm
    var scanFound = 0
    var activeReferenceID: String?
    var isRecording = false
    var recordingSeconds = 0

    private var life = 0
    private var meterTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var agcTick = 0
    private var addedThisScan = 0
    private let defaults = UserDefaults.standard

    var currentFrequency: Double {
        switch mode {
        case .fm: fmFrequency
        case .shortwave: swFrequency
        case .air: airFrequency
        case .marine: marineFrequency
        }
    }

    var displayFrequency: Double {
        isScanning && scanFrequency > 0 ? scanFrequency : currentFrequency
    }

    var displayMode: RadioMode { isScanning ? scanService : mode }

    var activeBand: SWBand? {
        let hz = displayMode == .shortwave ? (isScanning ? scanFrequency : swFrequency) : 0
        guard displayMode == .shortwave else { return nil }
        if let scanMeters, isScanning {
            return SWBand.all.first { $0.meters == scanMeters }
        }
        return SWBand.containing(hz) ?? SWBand.nearest(to: hz == 0 ? swFrequency : hz)
    }

    var dial: (low: Double, high: Double) {
        switch displayMode {
        case .fm:
            return (87_500_000, 108_000_000)
        case .air:
            return (118_000_000, 136_975_000)
        case .marine:
            return (156_000_000, 162_025_000)
        case .shortwave:
            let band = activeBand ?? SWBand.nearest(to: swFrequency)
            return (band.lowHz, band.highHz)
        }
    }

    var gainLevel: Double {
        get {
            switch mode {
            case .fm: fmGain
            case .shortwave: swGain
            case .air, .marine: vhfGain
            }
        }
        set {
            let value = min(1, max(0, newValue))
            switch mode {
            case .fm: fmGain = value
            case .shortwave: swGain = value
            case .air, .marine: vhfGain = value
            }
        }
    }

    var hardware: HardwareGain {
        HardwareGain.from(level: gainLevel, mode: mode)
    }

    var squelchEnabled: Bool { squelchDB > -88 }

    var squelchOpen: Bool {
        !squelchEnabled || signalDB >= squelchDB
    }

    private(set) var tuneKnobAngle = -135.0
    private var knobFrequency = 0.0

    var knobAngle: Double {
        isScanning ? bandKnobAngle(for: displayFrequency) : tuneKnobAngle
    }

    private func bandKnobAngle(for hz: Double) -> Double {
        let span = dial.high - dial.low
        let t = span > 0 ? (hz - dial.low) / span : 0
        return -135 + min(1, max(0, t)) * 270
    }

    private func moveTuneKnob(to value: Double, precise: Bool) {
        let step = stepSize(forceFine: precise)
        let delta = value - knobFrequency
        knobFrequency = value
        guard step > 0 else {
            tuneKnobAngle = bandKnobAngle(for: value)
            return
        }
        let steps = delta / step
        if abs(steps) <= 30 {
            tuneKnobAngle += steps * (precise ? 12 : 20)
        } else {
            tuneKnobAngle = bandKnobAngle(for: value)
        }
    }

    private func parkTuneKnob(at hz: Double) {
        knobFrequency = hz
        tuneKnobAngle = bandKnobAngle(for: hz)
    }

    init() {
        let storedMode = RadioMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .fm
        mode = storedMode
        fmFrequency = defaults.object(forKey: Keys.fm) as? Double ?? 98_100_000
        swFrequency = defaults.object(forKey: Keys.sw) as? Double ?? 6_050_000
        airFrequency = defaults.object(forKey: Keys.air) as? Double ?? 118_700_000
        marineFrequency = defaults.object(forKey: Keys.marine) as? Double ?? 156_600_000
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.75
        squelchDB = defaults.object(forKey: Keys.squelch) as? Double ?? -90
        fmGain = defaults.object(forKey: Keys.fmGain) as? Double ?? 0.34
        swGain = defaults.object(forKey: Keys.swGain) as? Double ?? 0.68
        vhfGain = defaults.object(forKey: Keys.vhfGain) as? Double ?? 0.62
        agcEnabled = defaults.object(forKey: Keys.agc) as? Bool ?? true
        deemphasis75 = defaults.object(forKey: Keys.de75) as? Bool ?? false
        fine = defaults.object(forKey: Keys.fine) as? Bool ?? false
        loadStations()
        parkTuneKnob(at: currentFrequency)
    }

    func togglePower() {
        if isOn || isPowering {
            powerOff()
        } else {
            powerOn()
        }
    }

    func powerOn() {
        guard !isOn, !isPowering else { return }
        Task { _ = await connect() }
    }

    func powerOff() {
        life += 1
        meterTask?.cancel()
        meterTask = nil
        let saved = finishRecording(reveal: false)
        isOn = false
        isScanning = false
        isPowering = false
        clipped = false
        statusText = saved.map { L10n.f("ui.poweredOffSaved", $0.lastPathComponent) } ?? L10n.s("ui.poweredOff")
        endActivity()
        let session = session
        Task.detached {
            session.shutdown()
        }
        persistSettings()
    }

    func shutdownBlocking() {
        life += 1
        meterTask?.cancel()
        meterTask = nil
        _ = finishRecording(reveal: false)
        session.requestCancel()
        session.shutdown()
        endActivity()
        persistSettings()
    }

    func setMode(_ newMode: RadioMode) {
        guard !isScanning, mode != newMode else { return }
        mode = newMode
        pushDSP()
        applyGain()
        tune(currentFrequency, quantize: false)
        schedulePersist()
    }

    func selectBand(_ band: SWBand) {
        guard !isScanning else { return }
        mode = .shortwave
        if let best = stations
            .filter({ $0.mode == .shortwave && $0.bandMeters == band.meters })
            .max(by: { $0.signalDB < $1.signalDB }) {
            swFrequency = best.frequencyHz
        } else if swFrequency < band.lowHz || swFrequency > band.highHz {
            swFrequency = band.centerHz
        }
        pushDSP()
        applyGain()
        tune(swFrequency, quantize: false)
        schedulePersist()
    }

    func tune(_ hz: Double, quantize: Bool = true, precise: Bool? = nil) {
        guard !isScanning else { return }
        let ranged = clamp(hz)
        let value = quantize ? snap(ranged, forceFine: precise ?? fine) : ranged
        switch mode {
        case .fm: fmFrequency = value
        case .shortwave: swFrequency = value
        case .air: airFrequency = value
        case .marine: marineFrequency = value
        }
        if let id = activeReferenceID,
           let item = AirCatalog.references.first(where: { $0.id == id }),
           item.mode != mode || abs(item.frequencyHz - value) > 1_000 {
            activeReferenceID = nil
        }
        if isOn {
            session.retune(value)
        }
        moveTuneKnob(to: value, precise: precise ?? fine)
        schedulePersist()
    }

    func stepFrequency(_ steps: Int, forceFine: Bool = false) {
        let delta = Double(steps) * stepSize(forceFine: forceFine)
        tune(currentFrequency + delta, precise: fine || forceFine)
    }

    func jumpDial(fraction: Double) {
        let range = dial
        let hz = range.low + (range.high - range.low) * min(1, max(0, fraction))
        tune(hz)
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        session.setAudio(volume: Float(volume))
        schedulePersist()
    }

    func setSquelch(_ value: Double) {
        squelchDB = min(-25, max(-90, value))
        pushDSP()
        schedulePersist()
    }

    func setGainLevel(_ value: Double) {
        gainLevel = value
        applyGain()
        schedulePersist()
    }

    func setAGC(_ enabled: Bool) {
        agcEnabled = enabled
        schedulePersist()
    }

    func setDeemphasis75(_ enabled: Bool) {
        deemphasis75 = enabled
        pushDSP()
        schedulePersist()
    }

    func setFine(_ enabled: Bool) {
        fine = enabled
        schedulePersist()
    }

    func selectService(_ newMode: RadioMode, frequency: Double) {
        guard !isScanning, newMode == .air || newMode == .marine else { return }
        mode = newMode
        switch newMode {
        case .air: airFrequency = frequency
        case .marine: marineFrequency = frequency
        default: break
        }
        pushDSP()
        applyGain()
        if let match = AirCatalog.references.first(where: { $0.mode == newMode && abs($0.frequencyHz - frequency) < 1_000 }) {
            activeReferenceID = match.id
        } else {
            activeReferenceID = nil
        }
        tune(frequency, quantize: false)
        schedulePersist()
    }

    func tuneReference(_ item: AirReference) {
        selectService(item.mode, frequency: item.frequencyHz)
        activeReferenceID = item.id
    }

    func toggleScan(wide: Bool) {
        if isScanning {
            session.requestCancel()
            statusText = L10n.s("ui.stoppingScan")
            return
        }
        if isRecording {
            _ = finishRecording(reveal: false)
        }
        Task { await runScan(wide: wide) }
    }

    func toggleRecording() {
        if isRecording {
            if let url = finishRecording(reveal: true) {
                statusText = L10n.f("ui.recordingSaved", url.lastPathComponent)
            }
            return
        }
        guard isOn, !isScanning else {
            statusText = isScanning ? L10n.s("ui.recordWhileScan") : L10n.s("ui.powerOnFirst")
            return
        }
        let url = Self.makeRecordingURL(mode: mode, hz: currentFrequency)
        let title = "\(FrequencyText.value(currentFrequency, mode: mode)) \(FrequencyText.unit(mode))"
        if let error = session.startRecording(url: url, title: title) {
            statusText = error
            return
        }
        isRecording = true
        recordingSeconds = 0
        statusText = L10n.f("ui.recording", Int64(MP3Recorder.bitrate))
    }

    func saveCurrent() {
        guard !isScanning else { return }
        _ = upsert(
            frequencyHz: currentFrequency,
            mode: mode,
            signalDB: signalDB,
            forceNewName: false
        )
        persistStations()
        statusText = L10n.f("ui.stored", FrequencyText.value(currentFrequency, mode: mode), FrequencyText.unit(mode))
    }

    func tune(to station: SavedStation) {
        guard !isScanning else { return }
        mode = station.mode
        switch station.mode {
        case .fm: fmFrequency = station.frequencyHz
        case .shortwave: swFrequency = station.frequencyHz
        case .air: airFrequency = station.frequencyHz
        case .marine: marineFrequency = station.frequencyHz
        }
        pushDSP()
        applyGain()
        tune(station.frequencyHz, quantize: false)
    }

    func stepStation(_ direction: Int) {
        let list = stations(matching: stationFilter(for: mode))
        guard !list.isEmpty else { return }
        let current = currentFrequency
        let index: Int
        if let exact = list.firstIndex(where: { abs($0.frequencyHz - current) < matchTolerance(mode) }) {
            index = exact
        } else if let next = list.firstIndex(where: { $0.frequencyHz > current }) {
            index = next
        } else {
            index = 0
        }
        let target = (index + direction + list.count) % list.count
        tune(to: list[target])
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { return }
        stations[index].favorite.toggle()
        persistStations()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = stations.firstIndex(where: { $0.id == id }) else { return }
        stations[index].name = trimmed
        persistStations()
    }

    func delete(_ id: UUID) {
        stations.removeAll { $0.id == id }
        persistStations()
    }

    func clear(_ filter: StationFilter) {
        stations.removeAll { station in
            switch filter {
            case .all: true
            case .fm: station.mode == .fm
            case .shortwave: station.mode == .shortwave
            case .air: station.mode == .air
            case .marine: station.mode == .marine
            case .reference: false
            }
        }
        persistStations()
    }

    func commitEntry(_ raw: String) {
        guard let hz = FrequencyText.parse(raw) else {
            statusText = L10n.s("ui.badFrequency")
            return
        }
        if hz >= 87_500_000 && hz <= 108_000_000 {
            mode = .fm
            fmFrequency = hz
        } else if hz >= 118_000_000 && hz <= 137_000_000 {
            mode = .air
            airFrequency = hz
        } else if hz >= 156_000_000 && hz <= 162_050_000 {
            mode = .marine
            marineFrequency = hz
        } else if hz >= 2_000_000 && hz <= 30_000_000 {
            mode = .shortwave
            swFrequency = hz
        } else {
            statusText = L10n.s("ui.frequencyRange")
            return
        }
        pushDSP()
        applyGain()
        tune(currentFrequency, quantize: false)
    }

    func stations(matching filter: StationFilter) -> [SavedStation] {
        stations
            .filter { station in
                switch filter {
                case .all: true
                case .fm: station.mode == .fm
                case .shortwave: station.mode == .shortwave
                case .air: station.mode == .air
                case .marine: station.mode == .marine
                case .reference: false
                }
            }
            .sorted { lhs, rhs in
                if lhs.favorite != rhs.favorite { return lhs.favorite && !rhs.favorite }
                if lhs.mode != rhs.mode { return modeRank(lhs.mode) < modeRank(rhs.mode) }
                return lhs.frequencyHz < rhs.frequencyHz
            }
    }

    func isCurrent(_ station: SavedStation) -> Bool {
        station.mode == mode && abs(station.frequencyHz - currentFrequency) < matchTolerance(mode)
    }

    private func connect() async -> Bool {
        if isOn { return true }
        isPowering = true
        statusText = L10n.s("ui.connectingHackRF")
        let token = life
        let request = makeRequest()
        let session = session
        let result = await Task.detached {
            session.open(request)
        }.value
        guard token == life else { return false }
        isPowering = false
        guard result.ok else {
            isOn = false
            statusText = result.message
            return false
        }
        do {
            try session.startOutput()
        } catch {
            statusText = L10n.f("ui.audioFailed", error.localizedDescription)
            await Task.detached { session.shutdown() }.value
            return false
        }
        session.setAudio(volume: Float(volume))
        session.setDSP(mode: mode, squelchDB: effectiveSquelch, deemphasis75: deemphasis75)
        session.startDSP()
        isOn = true
        board = result.board
        firmware = result.firmware
        serial = result.serial
        statusText = L10n.s("ui.receiving")
        startMeters()
        beginActivity()
        return true
    }

    private func runScan(wide: Bool) async {
        let ready = await connect()
        guard ready, !isScanning else { return }
        isScanning = true
        addedThisScan = 0
        scanFound = 0
        scanProgress = 0
        scanService = mode
        let token = life
        let session = session
        let gain = hardware
        let scanMode = mode
        let restore = currentFrequency
        let bands = scanMode == .shortwave
            ? (wide ? SWBand.all : [activeListeningBand()])
            : []
        let services: [RadioMode] = {
            guard scanMode == .air || scanMode == .marine else { return [] }
            return wide ? [.air, .marine] : [scanMode]
        }()
        session.resetScanCounter()
        statusText = scanStatus(scanMode, wide: wide)
        await Task.detached {
            switch scanMode {
            case .fm:
                session.scanFM(gain: gain, restoreHz: restore)
            case .shortwave:
                session.scanShortwave(bands: bands, gain: gain, restoreHz: restore)
            case .air, .marine:
                session.scanVHF(services: services, gain: gain, restoreHz: restore, restoreMode: scanMode)
            }
        }.value
        pullTelemetry()
        guard token == life else { return }
        isScanning = false
        let parked = session.parkedFrequency()
        let parkedService = session.parkedService()
        if parked > 1_000_000 {
            mode = parkedService
            switch parkedService {
            case .fm: fmFrequency = parked
            case .shortwave: swFrequency = parked
            case .air: airFrequency = parked
            case .marine: marineFrequency = parked
            }
            pushDSP()
        }
        parkTuneKnob(at: currentFrequency)
        statusText = scanFound > 0 ? L10n.f("ui.scanDoneNew", Int64(scanFound)) : L10n.s("ui.scanDoneNone")
        persistStations()
        persistSettings()
    }

    @discardableResult
    private func finishRecording(reveal: Bool) -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        recordingSeconds = 0
        guard let url = session.stopRecording() else {
            statusText = L10n.s("ui.recordFailed")
            return nil
        }
        if reveal {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        return url
    }

    private static func makeRecordingURL(mode: RadioMode, hz: Double) -> URL {
        let base = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("HackRF Radio", isDirectory: true)
        let stamp = recordingStamp.string(from: Date())
        let freq = FrequencyText.value(hz, mode: mode).replacingOccurrences(of: ".", with: "_")
        let unit = FrequencyText.unit(mode)
        return folder.appendingPathComponent("\(stamp) \(freq)\(unit).mp3")
    }

    private static let recordingStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter
    }()

    private func scanStatus(_ scanMode: RadioMode, wide: Bool) -> String {
        switch scanMode {
        case .fm: L10n.s("ui.scanningFM")
        case .shortwave: wide ? L10n.s("ui.scanningAllSW") : L10n.s("ui.scanningSW")
        case .air: wide ? L10n.s("ui.scanningAirSea") : L10n.s("ui.scanningAir")
        case .marine: wide ? L10n.s("ui.scanningAirSea") : L10n.s("ui.scanningMarine")
        }
    }

    private func activeListeningBand() -> SWBand {
        SWBand.containing(swFrequency) ?? SWBand.nearest(to: swFrequency)
    }

    private func startMeters() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                self?.pullTelemetry()
            }
        }
    }

    private func pullTelemetry() {
        let tele = session.telemetry()
        if tele.signalDB.isFinite {
            signalDB = tele.signalDB
        }
        if !tele.spectrum.isEmpty, !isScanning {
            spectrum = tele.spectrum
        }
        clipped = tele.clipRatio > 0.004

        let scan = session.scanSnapshot()
        if isRecording {
            recordingSeconds = Int(session.recordingElapsed())
        }
        if isScanning {
            scanProgress = scan.progress
            if scan.frequencyHz > 0 { scanFrequency = scan.frequencyHz }
            scanMeters = scan.bandMeters
            scanService = scan.mode
            if !scan.spectrum.isEmpty { spectrum = scan.spectrum }
            if !scan.message.isEmpty { statusText = scan.message }
            for find in scan.freshFinds where upsert(frequencyHz: find.frequencyHz, mode: scan.mode, signalDB: find.powerDB, forceNewName: false) {
                addedThisScan += 1
            }
            if !scan.freshFinds.isEmpty {
                persistStations()
            }
            scanFound = addedThisScan
        }

        guard agcEnabled, isOn, !isScanning else { return }
        agcTick += 1
        guard agcTick % 8 == 0 else { return }
        if tele.clipRatio > 0.003 {
            setGainLevel(gainLevel - 0.06)
        } else if tele.signalDB < -62, tele.clipRatio < 0.0004, gainLevel < 0.9 {
            setGainLevel(gainLevel + 0.025)
        }
    }

    @discardableResult
    private func upsert(frequencyHz: Double, mode: RadioMode, signalDB: Double, forceNewName: Bool) -> Bool {
        let tolerance = matchTolerance(mode)
        let meters = mode == .shortwave ? SWBand.containing(frequencyHz)?.meters : nil
        if let index = stations.firstIndex(where: { $0.mode == mode && abs($0.frequencyHz - frequencyHz) < tolerance }) {
            stations[index].frequencyHz = frequencyHz
            stations[index].signalDB = signalDB
            stations[index].updatedAt = Date()
            stations[index].bandMeters = meters
            return false
        }
        let station = SavedStation(
            id: UUID(),
            frequencyHz: frequencyHz,
            mode: mode,
            bandMeters: meters,
            name: defaultName(frequencyHz, mode: mode, meters: meters),
            signalDB: signalDB,
            updatedAt: Date(),
            favorite: false
        )
        _ = forceNewName
        stations.append(station)
        return true
    }

    private func defaultName(_ hz: Double, mode: RadioMode, meters: Int?) -> String {
        if let named = AirCatalog.nearest(hz, mode: mode) {
            return named.name
        }
        switch mode {
        case .fm:
            return String(format: "FM %.1f", hz / 1_000_000)
        case .shortwave:
            if let meters {
                return L10n.f("ui.swMetersName", Int64(meters), Int64((hz / 1_000).rounded()))
            }
            return String(format: "SW %.0f", hz / 1_000)
        case .air:
            return L10n.f("ui.airFallback", hz / 1_000_000)
        case .marine:
            return L10n.f("ui.marineFallback", hz / 1_000_000)
        }
    }

    private func makeRequest() -> ListenRequest {
        ListenRequest(
            frequencyHz: currentFrequency,
            mode: mode,
            gain: hardware,
            volume: Float(volume),
            squelchDB: effectiveSquelch,
            deemphasis75: deemphasis75
        )
    }

    private var effectiveSquelch: Float {
        squelchEnabled ? Float(squelchDB) : -130
    }

    private func pushDSP() {
        session.setDSP(mode: mode, squelchDB: effectiveSquelch, deemphasis75: deemphasis75)
    }

    private func applyGain() {
        guard isOn else { return }
        session.setGain(hardware)
    }

    private func stepSize(forceFine: Bool) -> Double {
        let precise = fine || forceFine
        switch mode {
        case .fm: return precise ? 10_000 : 100_000
        case .shortwave: return precise ? 1_000 : 5_000
        case .air, .marine: return precise ? 5_000 : 25_000
        }
    }

    private func snap(_ hz: Double, forceFine: Bool) -> Double {
        let step = stepSize(forceFine: forceFine)
        return (hz / step).rounded() * step
    }

    private func clamp(_ hz: Double) -> Double {
        switch mode {
        case .fm:
            return min(108_000_000, max(87_500_000, hz))
        case .air:
            return min(136_975_000, max(118_000_000, hz))
        case .marine:
            return min(162_025_000, max(156_000_000, hz))
        case .shortwave:
            let band = SWBand.containing(hz) ?? SWBand.nearest(to: hz)
            return min(band.highHz + 25_000, max(band.lowHz - 25_000, hz))
        }
    }

    private func matchTolerance(_ mode: RadioMode) -> Double {
        switch mode {
        case .fm: 60_000
        case .shortwave: 3_000
        case .air, .marine: 10_000
        }
    }

    private func stationFilter(for mode: RadioMode) -> StationFilter {
        switch mode {
        case .fm: .fm
        case .shortwave: .shortwave
        case .air: .air
        case .marine: .marine
        }
    }

    private func modeRank(_ mode: RadioMode) -> Int {
        switch mode {
        case .fm: 0
        case .shortwave: 1
        case .air: 2
        case .marine: 3
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.persistSettings()
        }
    }

    func persistSettings() {
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(fmFrequency, forKey: Keys.fm)
        defaults.set(swFrequency, forKey: Keys.sw)
        defaults.set(airFrequency, forKey: Keys.air)
        defaults.set(marineFrequency, forKey: Keys.marine)
        defaults.set(volume, forKey: Keys.volume)
        defaults.set(squelchDB, forKey: Keys.squelch)
        defaults.set(fmGain, forKey: Keys.fmGain)
        defaults.set(swGain, forKey: Keys.swGain)
        defaults.set(vhfGain, forKey: Keys.vhfGain)
        defaults.set(agcEnabled, forKey: Keys.agc)
        defaults.set(deemphasis75, forKey: Keys.de75)
        defaults.set(fine, forKey: Keys.fine)
    }

    private func loadStations() {
        guard let data = try? Data(contentsOf: stationURL) else { return }
        if let decoded = try? JSONDecoder().decode([SavedStation].self, from: data) {
            let migrated = decoded.map { station in
                var copy = station
                if let key = AirCatalog.legacyNameKey(copy.name) {
                    copy.name = key
                }
                return copy
            }
            stations = migrated
            if zip(decoded, migrated).contains(where: { $0.name != $1.name }) {
                persistStations()
            }
        }
    }

    private func persistStations() {
        let url = stationURL
        let payload = stations
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private var stationURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("HackRFSWRadio", isDirectory: true).appendingPathComponent("stations.json")
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: L10n.s("ui.activityReason")
        )
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private enum Keys {
        static let mode = "HackRFRadio.mode"
        static let fm = "HackRFRadio.fmHz"
        static let sw = "HackRFRadio.swHz"
        static let air = "HackRFRadio.airHz"
        static let marine = "HackRFRadio.marineHz"
        static let volume = "HackRFRadio.volume"
        static let squelch = "HackRFRadio.squelch"
        static let fmGain = "HackRFRadio.fmGain"
        static let swGain = "HackRFRadio.swGain"
        static let vhfGain = "HackRFRadio.vhfGain"
        static let agc = "HackRFRadio.agc"
        static let de75 = "HackRFRadio.de75"
        static let fine = "HackRFRadio.fine"
    }
}
