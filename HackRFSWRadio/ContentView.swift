import SwiftUI

struct ContentView: View {
    @Environment(RadioEngine.self) private var engine
    @AppStorage("HackRFRadio.stationsOpen") private var stationsOpen = true
    @State private var filter: StationFilter = .all
    @State private var entry = ""
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 0) {
            receiver
            stationDrawer
        }
        .background(ChassisBackground())
        .frame(minWidth: stationsOpen ? 1140 : 860, minHeight: 800)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
            WindowTrafficLights()
                .padding(.top, 12)
                .padding(.leading, 20)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .background(RadioWindowChrome())
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.22), value: stationsOpen)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_PREVIEWS"] != "1" else { return }
            engine.powerOn()
        }
        .background(
            KeyMonitor { event in
                handleKey(event)
            }
        )
        .confirmationDialog(L10n.s("ui.clearConfirm"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L10n.s("ui.clear"), role: .destructive) { engine.clear(filter) }
            Button(L10n.s("ui.cancel"), role: .cancel) {}
        }
    }

    private var receiver: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            LCDScreen()
            FrequencyDial()
            controls
            BandStrip()
            Text(L10n.s("ui.antennaHint"))
                .font(.system(size: 11))
                .foregroundStyle(RadioTheme.muted)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .padding(.top, 48)
        .overlay(alignment: .topLeading) { Screw().padding(.top, 46).padding(.leading, 14) }
        .overlay(alignment: .topTrailing) { Screw().padding(10) }
        .overlay(alignment: .bottomLeading) { Screw().padding(10) }
        .overlay(alignment: .bottomTrailing) { Screw().padding(10) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HACKRF")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(7)
                Text(L10n.s("ui.brandSubtitle"))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2.4)
                    .foregroundStyle(RadioTheme.muted)
            }
            .padding(.leading, 28)
            Spacer()
            statusPill
        }
        .foregroundStyle(RadioTheme.text)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.8), radius: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(engine.isOn ? L10n.s("ui.connected") : (engine.isPowering ? L10n.s("ui.connecting") : L10n.s("ui.disconnected")))
                    .font(.system(size: 12, weight: .semibold))
                Text(engine.isOn ? identityLine : "HackRF One")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(RadioTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
    }

    private var identityLine: String {
        let serial = engine.serial.isEmpty ? "" : String(engine.serial.suffix(8))
        if engine.firmware.isEmpty { return serial }
        return "\(engine.board)  \(serial)"
    }

    private var statusColor: Color {
        if engine.isScanning || engine.isPowering { return RadioTheme.amber }
        return engine.isOn ? RadioTheme.good : Color.white.opacity(0.28)
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 22) {
            MetalKnob(
                angle: -135 + engine.volume * 270,
                diameter: 132,
                title: L10n.s("ui.volume"),
                readout: String(format: "%.0f%%", engine.volume * 100),
                pixelsPerStep: 14,
                degreesPerStep: 10
            ) { steps in
                engine.setVolume(engine.volume + Double(steps) * (engine.fine ? 0.012 : 0.03))
            }

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    PanelButton(title: L10n.s("ui.fm"), isOn: engine.mode == .fm) { engine.setMode(.fm) }
                    PanelButton(title: L10n.s("ui.shortwave"), isOn: engine.mode == .shortwave) { engine.setMode(.shortwave) }
                    PanelButton(title: L10n.s("ui.air"), isOn: engine.mode == .air || engine.mode == .marine) {
                        engine.setMode(.air)
                    }
                    Spacer(minLength: 0)
                    PanelButton(
                        title: engine.isOn ? L10n.s("ui.off") : L10n.s("ui.power"),
                        systemImage: "power",
                        isOn: engine.isOn
                    ) {
                        engine.togglePower()
                    }
                    .disabled(engine.isPowering)
                }
                HStack(spacing: 8) {
                    PanelButton(
                        title: engine.isScanning ? L10n.s("ui.stop") : L10n.s("ui.scan"),
                        systemImage: engine.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right",
                        isOn: engine.isScanning
                    ) {
                        engine.toggleScan(wide: false)
                    }
                    PanelButton(title: wideScanTitle, systemImage: "arrow.triangle.2.circlepath") {
                        if engine.mode == .air || engine.mode == .marine {
                            engine.toggleScan(wide: true)
                        } else {
                            engine.setMode(.shortwave)
                            engine.toggleScan(wide: true)
                        }
                    }
                    .disabled(engine.isScanning)
                    PanelButton(title: L10n.s("ui.store"), systemImage: "plus") {
                        engine.saveCurrent()
                    }
                    .disabled(engine.isScanning)
                    PanelButton(
                        title: engine.isRecording ? L10n.s("ui.stop") : L10n.s("ui.record"),
                        systemImage: engine.isRecording ? "stop.fill" : "record.circle",
                        isOn: engine.isRecording
                    ) {
                        engine.toggleRecording()
                    }
                    .disabled(engine.isScanning || engine.isPowering)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        sliderRow(title: L10n.s("ui.gain"), valueText: String(format: "%.0f%%", engine.gainLevel * 100)) {
                            Slider(value: Binding(
                                get: { engine.gainLevel },
                                set: { engine.setGainLevel($0) }
                            ), in: 0...1)
                            .tint(RadioTheme.amber)
                        }
                        Text(engine.hardware.caption)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(RadioTheme.amberDim)
                            .padding(.leading, 42)
                    }
                    sliderRow(title: L10n.s("ui.squelch"), valueText: engine.squelchEnabled ? String(format: "%.0f dB", locale: .autoupdatingCurrent, engine.squelchDB) : L10n.s("ui.squelchOff")) {
                        Slider(value: Binding(
                            get: { engine.squelchDB },
                            set: { engine.setSquelch($0) }
                        ), in: -90 ... -25)
                        .tint(RadioTheme.amber)
                    }
                }
                HStack(spacing: 8) {
                    PanelButton(title: "AGC", isOn: engine.agcEnabled) { engine.setAGC(!engine.agcEnabled) }
                    PanelButton(title: L10n.s("ui.fine"), isOn: engine.fine) { engine.setFine(!engine.fine) }
                    PanelButton(title: engine.deemphasis75 ? "75 µs" : "50 µs", isOn: engine.deemphasis75) {
                        engine.setDeemphasis75(!engine.deemphasis75)
                    }
                    Spacer(minLength: 0)
                    TextField(L10n.s("ui.enterFrequency"), text: $entry)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(RadioTheme.text)
                        .padding(.horizontal, 10)
                        .frame(width: 128, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
                        .onSubmit {
                            engine.commitEntry(entry)
                            entry = ""
                        }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                MetalKnob(
                    angle: engine.knobAngle,
                    diameter: 188,
                    title: L10n.s("ui.tune"),
                    readout: "\(FrequencyText.value(engine.displayFrequency, mode: engine.displayMode)) \(FrequencyText.unit(engine.displayMode))",
                    pixelsPerStep: engine.fine ? 28 : 16,
                    degreesPerStep: engine.fine ? 8 : 5,
                    enabled: !engine.isScanning,
                    animated: true
                ) { steps in
                    engine.stepFrequency(steps)
                }
                HStack(spacing: 10) {
                    stepButton("minus") { engine.stepFrequency(-1) }
                    stepButton("backward.end.fill") { engine.stepStation(-1) }
                    stepButton("forward.end.fill") { engine.stepStation(1) }
                    stepButton("plus") { engine.stepFrequency(1) }
                }
            }
        }
    }

    private func sliderRow<Control: View>(title: String, valueText: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RadioTheme.muted)
                .frame(width: 32, alignment: .leading)
            control()
            Text(valueText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(RadioTheme.glow)
                .frame(width: 64, alignment: .trailing)
                .lineLimit(1)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(RadioTheme.text)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .handCursor(!engine.isScanning)
        .disabled(engine.isScanning)
    }

    private var wideScanTitle: String {
        engine.mode == .air || engine.mode == .marine ? L10n.s("ui.airSea") : L10n.s("ui.allBands")
    }

    private var stationDrawer: some View {
        HStack(spacing: 0) {
            Button {
                stationsOpen.toggle()
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: stationsOpen ? "chevron.right" : "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    if !stationsOpen {
                        Text(L10n.s("ui.stations"))
                            .font(.system(size: 12, weight: .semibold))
                            .fixedSize()
                            .frame(width: 18, height: 36)
                            .rotationEffect(.degrees(-90))
                        Text("\(engine.stations.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(RadioTheme.muted)
                    }
                }
                .foregroundStyle(RadioTheme.text)
                .frame(width: 36)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(stationsOpen ? L10n.s("ui.collapseStations") : L10n.s("ui.expandStations"))

            if stationsOpen {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                stationPanel
                    .frame(width: 332)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.black.opacity(stationsOpen ? 0.22 : 0.16))
    }

    private var stationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.s("ui.stations"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("\(filter == .reference ? AirCatalog.references.count : shownStations.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(RadioTheme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(StationFilter.allCases) { item in
                        let selected = filter == item
                        Button {
                            filter = item
                        } label: {
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selected ? Color.black.opacity(0.86) : RadioTheme.text.opacity(0.82))
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(Capsule().fill(selected ? RadioTheme.amber : Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .handCursor()
                    }
                }
            }

            if filter == .reference {
                referenceList
            } else if shownStations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                    Text(L10n.s("ui.noStations"))
                        .font(.system(size: 13, weight: .medium))
                    Text(L10n.s("ui.noStationsHint"))
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(RadioTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(RadioTheme.text.opacity(0.8))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shownStations) { station in
                            stationRow(station)
                        }
                    }
                }
            }

            HStack {
                Button(L10n.s("ui.clear")) { confirmClear = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(RadioTheme.muted)
                    .disabled(filter == .reference || shownStations.isEmpty)
                Spacer()
                Text(filter == .reference ? L10n.s("ui.tapToTune") : (engine.isScanning ? L10n.s("ui.scanAutosave") : L10n.s("ui.renameHint")))
                    .font(.system(size: 10))
                    .foregroundStyle(RadioTheme.muted)
            }
        }
        .padding(18)
        .foregroundStyle(RadioTheme.text)
    }

    private var referenceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(AirCatalog.grouped(), id: \.region) { group in
                    Text(L10n.s(group.region))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RadioTheme.amberDim)
                        .padding(.top, 2)
                    ForEach(group.items) { item in
                        referenceRow(item)
                    }
                }
            }
        }
    }

    private func referenceRow(_ item: AirReference) -> some View {
        let current = engine.activeReferenceID == item.id
            || (engine.activeReferenceID == nil && engine.mode == item.mode && abs(engine.currentFrequency - item.frequencyHz) < 8_000)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.localizedName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(item.place)   \(item.localizedRole)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(RadioTheme.muted)
            }
            Spacer(minLength: 4)
            Text(item.mode == .marine ? "NFM" : "AM")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(RadioTheme.amberDim)
            Text(String(format: "%.3f", item.frequencyHz / 1_000_000))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(RadioTheme.glow)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(current ? RadioTheme.amber.opacity(0.16) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(current ? RadioTheme.amber.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .handCursor(!engine.isScanning)
        .onTapGesture {
            engine.tuneReference(item)
        }
    }

    private var shownStations: [SavedStation] {
        engine.stations(matching: filter)
    }

    private func stationRow(_ station: SavedStation) -> some View {
        let current = engine.isCurrent(station)
        return HStack(spacing: 8) {
            Button {
                engine.toggleFavorite(station.id)
            } label: {
                Image(systemName: station.favorite ? "star.fill" : "star")
                    .foregroundStyle(station.favorite ? RadioTheme.amber : RadioTheme.muted)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if renamingID == station.id {
                    TextField(L10n.s("ui.name"), text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .onSubmit {
                            engine.rename(station.id, to: renameText)
                            renamingID = nil
                        }
                } else {
                    Text(L10n.s(station.name))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            renamingID = station.id
                            renameText = L10n.s(station.name)
                        }
                }
                Text("\(station.frequencyText)   \(station.detailText)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(RadioTheme.muted)
            }
            Spacer(minLength: 4)
            Text(String(format: "%.0f", station.signalDB))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(RadioTheme.amberDim)
            Button {
                engine.delete(station.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RadioTheme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(current ? RadioTheme.amber.opacity(0.16) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(current ? RadioTheme.amber.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .handCursor()
        .onTapGesture {
            if renamingID != station.id {
                engine.tune(to: station)
            }
        }
        .contextMenu {
            Button(L10n.s("ui.tuneHere")) { engine.tune(to: station) }
            Button(station.favorite ? L10n.s("ui.unfavorite") : L10n.s("ui.favorite")) { engine.toggleFavorite(station.id) }
            Button(L10n.s("ui.rename")) {
                renamingID = station.id
                renameText = L10n.s(station.name)
            }
            Button(L10n.s("ui.delete"), role: .destructive) { engine.delete(station.id) }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let fine = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123:
            engine.stepFrequency(-1, forceFine: fine)
            return true
        case 124:
            engine.stepFrequency(1, forceFine: fine)
            return true
        case 126:
            engine.setVolume(engine.volume + 0.03)
            return true
        case 125:
            engine.setVolume(engine.volume - 0.03)
            return true
        case 49:
            engine.toggleScan(wide: (engine.mode == .shortwave || engine.mode.isVoice) && event.modifierFlags.contains(.option))
            return true
        default:
            return false
        }
    }
}

#Preview {
    ContentView()
        .environment(RadioEngine())
        .frame(width: 1240, height: 820)
}
