import AppKit
import SwiftUI

enum RadioTheme {
    static let chassisTop = Color(red: 0.20, green: 0.21, blue: 0.23)
    static let chassisBottom = Color(red: 0.07, green: 0.075, blue: 0.085)
    static let inset = Color(red: 0.05, green: 0.055, blue: 0.06)
    static let amber = Color(red: 0.98, green: 0.74, blue: 0.32)
    static let amberDeep = Color(red: 0.78, green: 0.42, blue: 0.10)
    static let amberDim = Color(red: 0.62, green: 0.44, blue: 0.18)
    static let lcdTop = Color(red: 0.16, green: 0.11, blue: 0.05)
    static let lcdBottom = Color(red: 0.05, green: 0.035, blue: 0.02)
    static let glow = Color(red: 1.0, green: 0.82, blue: 0.42)
    static let text = Color(red: 0.94, green: 0.92, blue: 0.86)
    static let muted = Color(white: 0.62)
    static let danger = Color(red: 0.96, green: 0.38, blue: 0.28)
    static let good = Color(red: 0.62, green: 0.86, blue: 0.46)
    static let metal = Color(white: 0.72)
}

struct ChassisBackground: View {
    var body: some View {
        LinearGradient(colors: [RadioTheme.chassisTop, RadioTheme.chassisBottom], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.white.opacity(0.10), Color.clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
            .ignoresSafeArea()
    }
}

struct RadioWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> RadioWindowChromeView {
        RadioWindowChromeView()
    }

    func updateNSView(_ nsView: RadioWindowChromeView, context: Context) {
        nsView.apply()
    }
}

final class RadioWindowChromeView: NSView {
    private var pendingCapabilities = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pendingCapabilities = false
        apply()
    }

    func apply() {
        guard let window else { return }
        RadioWindows.shared.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        RadioWindows.shared.enableFrameActions(window)
        guard !pendingCapabilities else { return }
        pendingCapabilities = true
        for delay in [0.0, 0.25, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
                guard let window else { return }
                RadioWindows.shared.enableFrameActions(window)
            }
        }
    }
}

@MainActor
final class RadioWindows {
    static let shared = RadioWindows()
    weak var window: NSWindow?

    var current: NSWindow? {
        window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
    }

    func enableFrameActions(_ window: NSWindow) {
        var mask = window.styleMask
        mask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        if window.styleMask != mask {
            window.styleMask = mask
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        var behavior = window.collectionBehavior
        behavior.subtract([.fullScreenNone, .fullScreenAuxiliary])
        behavior.insert(.fullScreenPrimary)
        if window.collectionBehavior != behavior {
            window.collectionBehavior = behavior
        }
    }

    func minimize() {
        guard let window = current else { return }
        enableFrameActions(window)
        window.miniaturize(nil)
    }

    func toggleFullScreen() {
        guard let window = current else { return }
        enableFrameActions(window)
        window.toggleFullScreen(nil)
    }
}

struct WindowTrafficLights: View {
    @State private var fullScreen = false

    var body: some View {
        HStack(spacing: 7) {
            TrafficLight(color: Color(red: 0.96, green: 0.33, blue: 0.29), symbol: "xmark", help: L10n.s("ui.windowClose"), shortcut: "w") {
                NSApp.terminate(nil)
            }
            TrafficLight(color: Color(red: 0.98, green: 0.76, blue: 0.24), symbol: "minus", help: L10n.s("ui.windowMinimize"), shortcut: "m") {
                RadioWindows.shared.minimize()
            }
            TrafficLight(
                color: Color(red: 0.40, green: 0.78, blue: 0.34),
                symbol: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                help: L10n.s(fullScreen ? "ui.windowExitFullScreen" : "ui.windowZoom"),
                shortcut: "f",
                modifiers: [.command, .control]
            ) {
                RadioWindows.shared.toggleFullScreen()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.32)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard let entered = note.object as? NSWindow, entered === RadioWindows.shared.current else { return }
            fullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard let exited = note.object as? NSWindow, exited === RadioWindows.shared.current else { return }
            fullScreen = false
        }
    }
}

private struct TrafficLight: View {
    var color: Color
    var symbol: String
    var help: String
    var shortcut: KeyEquivalent?
    var modifiers: EventModifiers = .command
    var action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.95), color.opacity(0.72)],
                            center: .init(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: 9
                        )
                    )
                Circle()
                    .stroke(Color.black.opacity(0.35), lineWidth: 0.6)
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.72))
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .handCursor()
        .accessibilityLabel(help)

        if let shortcut {
            button.keyboardShortcut(shortcut, modifiers: modifiers)
        } else {
            button
        }
    }
}

struct Screw: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(white: 0.42), Color(white: 0.16)],
                    center: .init(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: 8
                )
            )
            .frame(width: 12, height: 12)
            .overlay(
                Capsule()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 7, height: 1.2)
            )
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
    }
}

struct LCDScreen: View {
    @Environment(RadioEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .center, spacing: 18) {
                bandBlock
                Spacer(minLength: 8)
                frequencyBlock
                Spacer(minLength: 8)
                meterBlock
            }
            spectrumBlock
            footer
        }
        .padding(18)
        .background(lcdBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.8), lineWidth: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .padding(-6)
        )
        .shadow(color: RadioTheme.amber.opacity(engine.isOn ? 0.16 : 0.04), radius: 18, y: 0)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(modulationLabel)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().stroke(RadioTheme.amberDim, lineWidth: 1))
            Text(serviceLabel)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
            Spacer()
            if engine.isRecording {
                Text(String(format: "REC %d:%02d", engine.recordingSeconds / 60, engine.recordingSeconds % 60))
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(RadioTheme.danger)
            }
            if engine.isScanning {
                Label(L10n.s("ui.scan"), systemImage: "waveform")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .symbolEffect(.variableColor.iterative, isActive: true)
            } else if engine.isOn {
                Text(engine.squelchOpen ? "RX" : L10n.s("ui.squelched"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            if engine.clipped {
                Text("OVR")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(RadioTheme.danger)
            }
        }
        .foregroundStyle(RadioTheme.glow)
    }

    private var bandBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let band = engine.activeBand, engine.displayMode == .shortwave {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(band.meters)")
                        .font(.system(size: band.meters >= 100 ? 34 : 46, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("m")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.bottom, 4)
                        .fixedSize()
                }
                Text(L10n.s("ui.wavelength"))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(RadioTheme.amberDim)
            } else {
                Text(bandLowText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text("—")
                    .font(.system(size: 13, weight: .medium))
                Text(bandHighText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text("MHz")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RadioTheme.amberDim)
            }
        }
        .foregroundStyle(RadioTheme.glow)
        .frame(width: 118, alignment: .leading)
    }

    private var frequencyBlock: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(FrequencyText.value(engine.displayFrequency, mode: engine.displayMode))
                    .font(.system(size: 62, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(FrequencyText.unit(engine.displayMode))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .padding(.bottom, 8)
            }
            .foregroundStyle(RadioTheme.glow)
            .shadow(color: RadioTheme.amber.opacity(0.55), radius: 10, y: 0)
            if engine.displayMode == .shortwave {
                Text(String(format: "%.3f MHz", engine.displayFrequency / 1_000_000))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(RadioTheme.amberDim)
            } else if let named = activeReferenceName {
                Text(named)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RadioTheme.amberDim)
                    .lineLimit(1)
            }
        }
    }

    private var meterBlock: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(segmentColor(index: index, lit: litSegments))
                        .frame(width: 6, height: index > 11 ? 16 : 12)
                }
            }
            Text(engine.isOn ? String(format: "%+.0f dBFS", engine.signalDB) : "— dBFS")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(RadioTheme.amberDim)
        }
        .frame(width: 150, alignment: .trailing)
    }

    private var litSegments: Int {
        guard engine.isOn else { return 0 }
        let normalized = (engine.signalDB - (-96)) / ((-18) - (-96))
        return Int(min(16, max(0, normalized * 16)))
    }

    private func segmentColor(index: Int, lit: Int) -> Color {
        guard index < lit else { return Color.white.opacity(0.06) }
        if index >= 13 { return RadioTheme.danger }
        if index >= 10 { return Color(red: 1, green: 0.62, blue: 0.22) }
        return RadioTheme.amber
    }

    private var spectrumBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            SpectrumTrace(samples: engine.spectrum)
                .frame(height: 72)
            HStack {
                Text(engine.isScanning ? L10n.s("ui.scanSpectrum") : L10n.s("ui.channelSpectrum"))
                Spacer()
                if engine.isScanning {
                    Text(String(format: "%.0f%%", engine.scanProgress * 100))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(RadioTheme.amberDim)
            if engine.isScanning {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(RadioTheme.amber)
                            .frame(width: max(4, geo.size.width * engine.scanProgress))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(engine.statusText)
                .lineLimit(2)
            Spacer()
            Text(engine.hardware.caption)
            if engine.displayMode == .fm {
                Text("·")
                Text(engine.deemphasis75 ? "75 µs" : "50 µs")
            }
            Text("·")
            Text("2.4 Msps")
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(RadioTheme.amberDim)
    }

    private var lcdBackground: some View {
        ZStack {
            LinearGradient(colors: [RadioTheme.lcdTop, RadioTheme.lcdBottom], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.black.opacity(0.16)))
                    y += 3
                }
            }
            .allowsHitTesting(false)
            LinearGradient(colors: [Color.white.opacity(0.10), Color.clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
        }
    }

    private var modulationLabel: String {
        switch engine.displayMode {
        case .fm: "WFM"
        case .marine: "NFM"
        case .shortwave, .air: "AM"
        }
    }

    private var serviceLabel: String {
        switch engine.displayMode {
        case .fm: L10n.s("ui.fmBroadcast")
        case .shortwave: L10n.s("ui.swBroadcast")
        case .air: L10n.s("ui.airVoice")
        case .marine: L10n.s("ui.marineVoice")
        }
    }

    private var bandLowText: String {
        switch engine.displayMode {
        case .air: mhz(118)
        case .marine: mhz(156)
        case .fm, .shortwave: mhz(87.5)
        }
    }

    private var activeReferenceName: String? {
        if let id = engine.activeReferenceID,
           let item = AirCatalog.references.first(where: { $0.id == id }),
           item.mode == engine.displayMode {
            return item.localizedName
        }
        return AirCatalog.nearest(engine.displayFrequency, mode: engine.displayMode)?.localizedName
    }

    private func mhz(_ value: Double) -> String {
        String(format: "%.1f", locale: .autoupdatingCurrent, value)
    }

    private var bandHighText: String {
        switch engine.displayMode {
        case .air: mhz(137)
        case .marine: mhz(162)
        case .fm, .shortwave: mhz(108)
        }
    }
}

struct SpectrumTrace: View {
    var samples: [Float]

    var body: some View {
        Canvas { context, size in
            let mid = size.height * 0.72
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: mid))
            grid.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(grid, with: .color(RadioTheme.amberDim.opacity(0.35)), lineWidth: 0.6)

            guard samples.count > 2 else { return }
            var line = Path()
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: size.height))
            let step = size.width / CGFloat(samples.count - 1)
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * step
                let y = size.height - CGFloat(min(1, max(0, sample))) * (size.height - 6) - 2
                if index == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
                fill.addLine(to: CGPoint(x: x, y: y))
            }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [RadioTheme.amber.opacity(0.38), RadioTheme.amber.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(RadioTheme.glow), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

struct FrequencyDial: View {
    @Environment(RadioEngine.self) private var engine

    var body: some View {
        Canvas { context, size in
            let range = engine.dial
                let base = size.height - 18
                var axis = Path()
                axis.move(to: CGPoint(x: 8, y: base))
                axis.addLine(to: CGPoint(x: size.width - 8, y: base))
                context.stroke(axis, with: .color(Color.white.opacity(0.28)), lineWidth: 1)

                let ticks = 41
                for index in 0..<ticks {
                    let t = CGFloat(index) / CGFloat(ticks - 1)
                    let x = 8 + t * (size.width - 16)
                    let major = index % 10 == 0
                    var mark = Path()
                    mark.move(to: CGPoint(x: x, y: base))
                    mark.addLine(to: CGPoint(x: x, y: base - (major ? 14 : 7)))
                    context.stroke(mark, with: .color(Color.white.opacity(major ? 0.7 : 0.28)), lineWidth: major ? 1.4 : 1)
                    if major {
                        let hz = range.low + (range.high - range.low) * Double(t)
                        let label = engine.displayMode == .shortwave
                            ? String(format: "%.0f", hz / 1_000)
                            : String(format: engine.displayMode == .fm ? "%.0f" : "%.1f", hz / 1_000_000)
                        context.draw(
                            Text(label).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(RadioTheme.muted),
                            at: CGPoint(x: x, y: base - 26)
                        )
                    }
                }

                let span = range.high - range.low
                let fraction = span > 0 ? (engine.displayFrequency - range.low) / span : 0
                let needleX = 8 + CGFloat(min(1, max(0, fraction))) * (size.width - 16)
                var needle = Path()
                needle.move(to: CGPoint(x: needleX, y: 8))
                needle.addLine(to: CGPoint(x: needleX - 6, y: base - 16))
                needle.addLine(to: CGPoint(x: needleX + 6, y: base - 16))
                needle.closeSubpath()
                context.fill(needle, with: .color(RadioTheme.amber))
                var stem = Path()
                stem.move(to: CGPoint(x: needleX, y: base - 16))
                stem.addLine(to: CGPoint(x: needleX, y: base))
                context.stroke(stem, with: .color(RadioTheme.amber), lineWidth: 1.4)
            }
            .allowsHitTesting(false)
        .overlay {
            DialScrubber(enabled: !engine.isScanning) { fraction in
                engine.jumpDial(fraction: fraction)
            }
        }
        .frame(height: 74)
    }
}

struct MetalKnob: View {
    var angle: Double
    var diameter: CGFloat
    var title: String
    var readout: String
    var pixelsPerStep: CGFloat = 6
    var degreesPerStep: Double = 12
    var enabled: Bool = true
    var animated: Bool = false
    var onStep: (Int) -> Void

    @State private var shownAngle = 0.0
    @State private var primed = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .padding(4)
                tickRing
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [
                                    Color(white: 0.62),
                                    Color(white: 0.18),
                                    Color(white: 0.55),
                                    Color(white: 0.14),
                                    Color(white: 0.48),
                                    Color(white: 0.20),
                                    Color(white: 0.62),
                                ],
                                center: .center
                            )
                        )
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        .padding(6)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.34), Color(white: 0.08)],
                                center: .init(x: 0.38, y: 0.32),
                                startRadius: 2,
                                endRadius: diameter * 0.28
                            )
                        )
                        .padding(diameter * 0.28)
                    Capsule()
                        .fill(RadioTheme.amber)
                        .frame(width: 3.5, height: diameter * 0.16)
                        .offset(y: -diameter * 0.24)
                        .shadow(color: RadioTheme.amber.opacity(0.9), radius: 5)
                }
                .padding(diameter * 0.12)
                .rotationEffect(.degrees(displayAngle))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 6)
                .allowsHitTesting(false)
            }
            .frame(width: diameter, height: diameter)
            .overlay {
                KnobTurnCatcher(degreesPerStep: degreesPerStep, enabled: enabled, onStep: onStep)
            }
            .background {
                KnobScrollCatcher(pixelsPerStep: pixelsPerStep, enabled: enabled, onStep: onStep)
            }
            .opacity(enabled ? 1 : 0.45)
            .allowsHitTesting(enabled)
            .onAppear {
                shownAngle = angle
                primed = true
            }
            .onChange(of: angle) { _, new in
                pushAngle(new)
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(RadioTheme.muted)
            Text(readout)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(RadioTheme.glow)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var tickRing: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - 2
            for index in 0..<31 {
                let degrees = -135 + Double(index) / 30 * 270
                let radians = degrees * .pi / 180
                let inner = radius - (index % 5 == 0 ? 12 : 7)
                var path = Path()
                path.move(to: CGPoint(x: center.x + CGFloat(sin(radians)) * inner, y: center.y - CGFloat(cos(radians)) * inner))
                path.addLine(to: CGPoint(x: center.x + CGFloat(sin(radians)) * radius, y: center.y - CGFloat(cos(radians)) * radius))
                context.stroke(path, with: .color(Color.white.opacity(index % 5 == 0 ? 0.55 : 0.22)), lineWidth: index % 5 == 0 ? 1.5 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    private var displayAngle: Double {
        guard animated else { return angle }
        return primed ? shownAngle : angle
    }

    private func pushAngle(_ new: Double) {
        if !primed {
            shownAngle = new
            primed = true
            return
        }
        let delta = new - shownAngle
        if !animated || abs(delta) > 220 {
            shownAngle = new
        } else {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                shownAngle = new
            }
        }
    }
}

struct KnobTurnCatcher: NSViewRepresentable {
    var degreesPerStep: Double
    var enabled: Bool
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> KnobTurnView {
        let view = KnobTurnView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.001).cgColor
        view.degreesPerStep = degreesPerStep
        view.enabled = enabled
        view.onStep = onStep
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: KnobTurnView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func updateNSView(_ nsView: KnobTurnView, context: Context) {
        nsView.degreesPerStep = degreesPerStep
        nsView.enabled = enabled
        nsView.onStep = onStep
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

final class KnobTurnView: NSView {
    var degreesPerStep = 12.0
    var enabled = true
    var onStep: ((Int) -> Void)?
    private var trackingCircular = false
    private var insideTrack = false
    private var lastAngle = 0.0
    private var lastLinear: NSPoint?
    private var accum = 0.0
    private var windowWasMovable = false

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard enabled else { return nil }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        guard enabled else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        trackingCircular = false
        lastLinear = nil
        accum = 0
        windowWasMovable = window?.isMovableByWindowBackground ?? false
        window?.isMovableByWindowBackground = false
        NSCursor.closedHand.set()
        turn(event)
        guard let window else { return }
        insideTrack = true
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { [weak self] event, stop in
            guard let self, let event else {
                stop.pointee = true
                return
            }
            switch event.type {
            case .leftMouseDragged:
                self.turn(event)
            case .leftMouseUp:
                self.finishTurn()
                stop.pointee = true
            default:
                break
            }
        }
        insideTrack = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !insideTrack else { return }
        turn(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !insideTrack else { return }
        finishTurn()
    }

    private func finishTurn() {
        trackingCircular = false
        lastLinear = nil
        accum = 0
        window?.isMovableByWindowBackground = windowWasMovable
        NSCursor.pointingHand.set()
    }

    private func turn(_ event: NSEvent) {
        guard enabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        let radius = hypot(dx, dy)
        let limit = min(bounds.width, bounds.height)
        guard limit > 2 else { return }
        let inner = max(10, limit * 0.1)

        if radius >= inner {
            let pointer = atan2(dx, dy)
            if trackingCircular {
                var delta = pointer - lastAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                emit(delta * 180 / .pi)
            }
            lastAngle = pointer
            trackingCircular = true
            lastLinear = point
            return
        }

        if !trackingCircular, let previous = lastLinear {
            emit((point.y - previous.y) * 0.85)
        }
        lastLinear = point
    }

    private func emit(_ degrees: Double) {
        accum += degrees
        let fine = NSEvent.modifierFlags.contains(.shift)
        let threshold = fine ? degreesPerStep * 2.2 : degreesPerStep
        let steps = Int(accum / threshold)
        guard steps != 0 else { return }
        accum -= Double(steps) * threshold
        let callback = onStep
        callback?(steps)
    }
}

struct DialScrubber: NSViewRepresentable {
    var enabled: Bool
    var onFraction: (Double) -> Void

    func makeNSView(context: Context) -> DialScrubView {
        let view = DialScrubView()
        view.enabled = enabled
        view.onFraction = onFraction
        return view
    }

    func updateNSView(_ nsView: DialScrubView, context: Context) {
        nsView.enabled = enabled
        nsView.onFraction = onFraction
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

final class DialScrubView: NSView {
    var enabled = true
    var onFraction: ((Double) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard enabled else { return nil }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        guard enabled else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) { scrub(event) }
    override func mouseDragged(with event: NSEvent) { scrub(event) }

    private func scrub(_ event: NSEvent) {
        guard enabled else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let fraction = (x - 8) / max(1, bounds.width - 16)
        onFraction?(Double(min(1, max(0, fraction))))
    }
}

struct KnobScrollCatcher: NSViewRepresentable {
    var pixelsPerStep: CGFloat
    var enabled: Bool
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> KnobScrollView {
        let view = KnobScrollView()
        view.pixelsPerStep = pixelsPerStep
        view.enabled = enabled
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: KnobScrollView, context: Context) {
        nsView.pixelsPerStep = pixelsPerStep
        nsView.enabled = enabled
        nsView.onStep = onStep
    }
}

final class KnobScrollView: NSView {
    var pixelsPerStep: CGFloat = 6
    var enabled = true
    var onStep: ((Int) -> Void)?
    private var accum: CGFloat = 0
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.enabled, let window = self.window, event.window === window else { return event }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local), self.bounds.width > 2 else { return event }
                let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1.6 : 12
                self.ingest(event.deltaY * scale, fine: event.modifierFlags.contains(.shift))
                return nil
            }
        }
    }

    private func ingest(_ delta: CGFloat, fine: Bool) {
        accum += delta
        let threshold = fine ? pixelsPerStep * 2.4 : pixelsPerStep
        let steps = Int(accum / threshold)
        guard steps != 0 else { return }
        accum -= CGFloat(steps) * threshold
        let callback = onStep
        DispatchQueue.main.async {
            callback?(steps)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit { removeMonitor() }
}

extension View {
    func handCursor(_ enabled: Bool = true) -> some View {
        onHover { inside in
            guard enabled else {
                NSCursor.arrow.set()
                return
            }
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

struct PanelButton: View {
    var title: String
    var systemImage: String?
    var isOn = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? Color.black.opacity(0.86) : RadioTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? RadioTheme.amber : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isOn ? 0.35 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

struct BandStrip: View {
    @Environment(RadioEngine.self) private var engine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if engine.mode == .air || engine.mode == .marine {
                    ForEach(AirCatalog.regions) { region in
                        let selected = engine.mode == region.mode && abs(engine.currentFrequency - region.frequencyHz) < 15_000
                        chip(region.localizedTitle, selected: selected) {
                            engine.selectService(region.mode, frequency: region.frequencyHz)
                        }
                    }
                } else {
                    ForEach(SWBand.all) { band in
                        let selected = engine.mode == .shortwave && engine.activeBand?.meters == band.meters
                        chip(band.title, selected: selected) {
                            engine.selectBand(band)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(selected ? Color.black.opacity(0.86) : RadioTheme.text.opacity(0.8))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    Capsule().fill(selected ? RadioTheme.amber : Color.white.opacity(0.05))
                )
                .overlay(Capsule().stroke(Color.white.opacity(selected ? 0.3 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .handCursor(!engine.isScanning)
        .disabled(engine.isScanning)
    }
}

struct KeyMonitor: NSViewRepresentable {
    var onKey: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKey: onKey)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onKey: (NSEvent) -> Bool
        var token: Any?

        init(onKey: @escaping (NSEvent) -> Bool) {
            self.onKey = onKey
        }

        func install() {
            guard token == nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.window?.firstResponder is NSTextView { return event }
                return self.onKey(event) ? nil : event
            }
        }

        func remove() {
            if let token {
                NSEvent.removeMonitor(token)
                self.token = nil
            }
        }

        deinit { remove() }
    }
}
