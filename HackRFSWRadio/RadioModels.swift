import Foundation

nonisolated enum RadioMode: String, Codable, CaseIterable, Sendable {
    case fm
    case shortwave
    case air
    case marine

    var title: String {
        switch self {
        case .fm: L10n.s("ui.fmMode")
        case .shortwave: L10n.s("ui.swMode")
        case .air: L10n.s("ui.air")
        case .marine: L10n.s("ui.marineShort")
        }
    }

    var isVoice: Bool { self == .air || self == .marine }
}

nonisolated struct SWBand: Identifiable, Equatable, Sendable {
    let meters: Int
    let lowHz: Double
    let highHz: Double

    var id: Int { meters }
    var title: String { "\(meters) m" }
    var centerHz: Double { (lowHz + highHz) / 2 }

    static let all: [SWBand] = [
        SWBand(meters: 120, lowHz: 2_300_000, highHz: 2_495_000),
        SWBand(meters: 90, lowHz: 3_200_000, highHz: 3_400_000),
        SWBand(meters: 75, lowHz: 3_900_000, highHz: 4_000_000),
        SWBand(meters: 60, lowHz: 4_750_000, highHz: 4_995_000),
        SWBand(meters: 49, lowHz: 5_900_000, highHz: 6_200_000),
        SWBand(meters: 41, lowHz: 7_200_000, highHz: 7_450_000),
        SWBand(meters: 31, lowHz: 9_400_000, highHz: 9_900_000),
        SWBand(meters: 25, lowHz: 11_600_000, highHz: 12_100_000),
        SWBand(meters: 22, lowHz: 13_570_000, highHz: 13_870_000),
        SWBand(meters: 19, lowHz: 15_100_000, highHz: 15_800_000),
        SWBand(meters: 16, lowHz: 17_480_000, highHz: 17_900_000),
        SWBand(meters: 15, lowHz: 18_900_000, highHz: 19_020_000),
        SWBand(meters: 13, lowHz: 21_450_000, highHz: 21_850_000),
        SWBand(meters: 11, lowHz: 25_670_000, highHz: 26_100_000),
    ]

    static func containing(_ hz: Double) -> SWBand? {
        all.first { hz >= $0.lowHz - 40_000 && hz <= $0.highHz + 40_000 }
    }

    static func nearest(to hz: Double) -> SWBand {
        all.min { abs($0.centerHz - hz) < abs($1.centerHz - hz) } ?? all[4]
    }
}

nonisolated struct SavedStation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var frequencyHz: Double
    var mode: RadioMode
    var bandMeters: Int?
    var name: String
    var signalDB: Double
    var updatedAt: Date
    var favorite: Bool

    var frequencyText: String {
        switch mode {
        case .fm:
            String(format: "%.1f MHz", frequencyHz / 1_000_000)
        case .shortwave:
            String(format: "%.0f kHz", frequencyHz / 1_000)
        case .air, .marine:
            String(format: "%.3f MHz", frequencyHz / 1_000_000)
        }
    }

    var detailText: String {
        switch mode {
        case .fm:
            return "FM"
        case .shortwave:
            return bandMeters.map { "\($0) m" } ?? L10n.s("ui.swMode")
        case .air:
            return L10n.s("ui.airAM")
        case .marine:
            return L10n.s("ui.marineNFM")
        }
    }
}

nonisolated struct HardwareGain: Sendable {
    var lna: Int
    var vga: Int
    var amp: Int

    var caption: String {
        "LNA \(lna) · VGA \(vga)" + (amp == 1 ? " · RF" : "")
    }

    static func from(level: Double, mode: RadioMode) -> HardwareGain {
        let clamped = min(1, max(0, level))
        let lnaTable = [0, 8, 16, 24, 32, 40]
        let lna = lnaTable[min(5, Int(clamped * 5.999))]
        let vga = min(62, Int(clamped * 31.0) * 2)
        let amp = (mode != .fm && clamped >= 0.55) ? 1 : 0
        return HardwareGain(lna: lna, vga: vga, amp: amp)
    }
}

nonisolated enum FrequencyText {
    static func value(_ hz: Double, mode: RadioMode) -> String {
        switch mode {
        case .fm, .air, .marine:
            String(format: "%.3f", hz / 1_000_000)
        case .shortwave:
            String(format: "%.1f", hz / 1_000)
        }
    }

    static func unit(_ mode: RadioMode) -> String {
        mode == .shortwave ? "kHz" : "MHz"
    }

    static func parse(_ raw: String) -> Double? {
        var cleaned = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "MHz", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "kHz", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        if cleaned.contains("."), cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(cleaned), value > 0 else { return nil }
        if value < 1_000 {
            return value * 1_000_000
        }
        return value * 1_000
    }
}

enum StationFilter: String, CaseIterable, Identifiable {
    case all
    case fm
    case shortwave
    case air
    case marine
    case reference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.s("ui.all")
        case .fm: L10n.s("ui.fm")
        case .shortwave: L10n.s("ui.shortwave")
        case .air: L10n.s("ui.air")
        case .marine: L10n.s("ui.marineShort")
        case .reference: L10n.s("ui.reference")
        }
    }
}

nonisolated struct AirReference: Identifiable, Sendable {
    var id: String
    var name: String
    var place: String
    var role: String
    var frequencyHz: Double
    var mode: RadioMode
    var region: String

    var localizedName: String { L10n.s(name) }
    var localizedRole: String { L10n.s(role) }
    var localizedRegion: String { L10n.s(region) }
}

nonisolated struct VHFRegion: Identifiable, Sendable {
    var id: String
    var title: String
    var mode: RadioMode
    var frequencyHz: Double

    var localizedTitle: String { L10n.s(title) }
}

nonisolated enum AirCatalog {
    static let regions: [VHFRegion] = [
        VHFRegion(id: "yvr", title: "region.vancouver", mode: .air, frequencyHz: 118_700_000),
        VHFRegion(id: "harbour", title: "region.harbour", mode: .air, frequencyHz: 118_400_000),
        VHFRegion(id: "yyj", title: "region.victoria", mode: .air, frequencyHz: 119_700_000),
        VHFRegion(id: "yxx", title: "region.abbotsford", mode: .air, frequencyHz: 119_400_000),
        VHFRegion(id: "ylw", title: "region.kelowna", mode: .air, frequencyHz: 119_600_000),
        VHFRegion(id: "yxs", title: "region.princegeorge", mode: .air, frequencyHz: 118_300_000),
        VHFRegion(id: "marine-van", title: "region.vanharbour", mode: .marine, frequencyHz: 156_600_000),
        VHFRegion(id: "marine-vic", title: "region.victraffic", mode: .marine, frequencyHz: 156_550_000),
    ]

    static let regionOrder = [
        "region.vancouver", "region.harbour", "region.victoria", "region.lowermainland",
        "region.interior", "region.north", "region.centre", "region.marine",
    ]

    static let references: [AirReference] = [
        ref("yvr-twr-s", "ref.yvr-twr-s", "CYVR", "role.tower", 118_700_000, .air, "region.vancouver"),
        ref("yvr-twr-n", "ref.yvr-twr-n", "CYVR", "role.tower", 119_550_000, .air, "region.vancouver"),
        ref("yvr-twr-bu", "ref.yvr-twr-bu", "CYVR", "role.tower", 120_150_000, .air, "region.vancouver"),
        ref("yvr-gnd-s", "ref.yvr-gnd-s", "CYVR", "role.ground", 121_700_000, .air, "region.vancouver"),
        ref("yvr-gnd-n", "ref.yvr-gnd-n", "CYVR", "role.ground", 127_150_000, .air, "region.vancouver"),
        ref("yvr-del", "ref.yvr-del", "CYVR", "role.clearance", 121_400_000, .air, "region.vancouver"),
        ref("yvr-atis", "ref.yvr-atis", "CYVR", "role.atis", 124_600_000, .air, "region.vancouver"),
        ref("yvr-app-hi", "ref.yvr-app-hi", "CYVR", "role.approach", 128_600_000, .air, "region.vancouver"),
        ref("yvr-app-lo", "ref.yvr-app-lo", "CYVR", "role.approach", 133_100_000, .air, "region.vancouver"),
        ref("yvr-dep-n", "ref.yvr-dep-n", "CYVR", "role.departure", 126_125_000, .air, "region.vancouver"),
        ref("yvr-dep-s", "ref.yvr-dep-s", "CYVR", "role.departure", 132_300_000, .air, "region.vancouver"),
        ref("yvr-trsa", "ref.yvr-trsa", "CYVR", "role.terminal", 125_200_000, .air, "region.vancouver"),
        ref("yhc-twr", "ref.yhc-twr", "CYHC", "role.water", 118_400_000, .air, "region.harbour"),
        ref("yhc-del", "ref.yhc-del", "CYHC", "role.clearance", 125_350_000, .air, "region.harbour"),
        ref("yhc-atis", "ref.yhc-atis", "CYHC", "role.atis", 126_800_000, .air, "region.harbour"),
        ref("yyj-twr-in", "ref.yyj-twr-in", "CYYJ", "role.tower", 119_700_000, .air, "region.victoria"),
        ref("yyj-twr-out", "ref.yyj-twr-out", "CYYJ", "role.tower", 119_100_000, .air, "region.victoria"),
        ref("yyj-gnd", "ref.yyj-gnd", "CYYJ", "role.ground", 121_900_000, .air, "region.victoria"),
        ref("yyj-del", "ref.yyj-del", "CYYJ", "role.clearance", 126_400_000, .air, "region.victoria"),
        ref("yyj-atis", "ref.yyj-atis", "CYYJ", "role.atis", 118_800_000, .air, "region.victoria"),
        ref("yyj-arr", "ref.yyj-arr", "CYYJ", "role.approach", 125_950_000, .air, "region.victoria"),
        ref("yyj-dep", "ref.yyj-dep", "CYYJ", "role.departure", 133_850_000, .air, "region.victoria"),
        ref("yyj-tml", "ref.yyj-tml", "CYYJ", "role.terminal", 127_800_000, .air, "region.victoria"),
        ref("ywh-radio", "ref.ywh-radio", "CYWH", "role.water", 127_450_000, .air, "region.victoria"),
        ref("ywh-atis", "ref.ywh-atis", "CYWH", "role.atis", 120_000_000, .air, "region.victoria"),
        ref("yxx-twr", "ref.yxx-twr", "CYXX", "role.tower", 119_400_000, .air, "region.lowermainland"),
        ref("yxx-outer", "ref.yxx-outer", "CYXX", "role.tower", 121_000_000, .air, "region.lowermainland"),
        ref("yxx-gnd", "ref.yxx-gnd", "CYXX", "role.ground", 121_800_000, .air, "region.lowermainland"),
        ref("yxx-atis", "ref.yxx-atis", "CYXX", "role.atis", 119_800_000, .air, "region.lowermainland"),
        ref("zbb-twr", "ref.zbb-twr", "CZBB", "role.tower", 118_100_000, .air, "region.lowermainland"),
        ref("zbb-outer", "ref.zbb-outer", "CZBB", "role.tower", 127_600_000, .air, "region.lowermainland"),
        ref("zbb-gnd", "ref.zbb-gnd", "CZBB", "role.ground", 124_300_000, .air, "region.lowermainland"),
        ref("zbb-atis", "ref.zbb-atis", "CZBB", "role.atis", 125_500_000, .air, "region.lowermainland"),
        ref("ynj-twr", "ref.ynj-twr", "CYNJ", "role.tower", 119_000_000, .air, "region.lowermainland"),
        ref("ynj-atis", "ref.ynj-atis", "CYNJ", "role.atis", 124_500_000, .air, "region.lowermainland"),
        ref("ypk-twr", "ref.ypk-twr", "CYPK", "role.tower", 126_300_000, .air, "region.lowermainland"),
        ref("ypk-atis", "ref.ypk-atis", "CYPK", "role.atis", 125_000_000, .air, "region.lowermainland"),
        ref("ycd-atis", "ref.ycd-atis", "CYCD", "role.atis", 128_425_000, .air, "region.lowermainland"),
        ref("ycd-fss", "ref.ycd-fss", "CYCD", "role.fss", 122_100_000, .air, "region.lowermainland"),
        ref("ylw-twr", "ref.ylw-twr", "CYLW", "role.tower", 119_600_000, .air, "region.interior"),
        ref("ylw-gnd", "ref.ylw-gnd", "CYLW", "role.ground", 121_700_000, .air, "region.interior"),
        ref("ylw-atis", "ref.ylw-atis", "CYLW", "role.atis", 127_500_000, .air, "region.interior"),
        ref("yka-fss", "ref.yka-fss", "CYKA", "role.fss", 125_700_000, .air, "region.interior"),
        ref("yxs-twr", "ref.yxs-twr", "CYXS", "role.tower", 118_300_000, .air, "region.north"),
        ref("yxs-gnd", "ref.yxs-gnd", "CYXS", "role.ground", 121_900_000, .air, "region.north"),
        ref("yxs-atis", "ref.yxs-atis", "CYXS", "role.atis", 128_725_000, .air, "region.north"),
        ref("yqq-twr", "ref.yqq-twr", "CYQQ", "role.tower", 126_200_000, .air, "region.north"),
        ref("yqq-gnd", "ref.yqq-gnd", "CYQQ", "role.ground", 119_750_000, .air, "region.north"),
        ref("yqq-atis", "ref.yqq-atis", "CYQQ", "role.atis", 118_600_000, .air, "region.north"),
        ref("yqq-tml", "ref.yqq-tml", "CYQQ", "role.terminal", 123_700_000, .air, "region.north"),
        ref("acc-n", "ref.acc-n", "CZVR", "role.centre", 134_400_000, .air, "region.centre"),
        ref("acc-e", "ref.acc-e", "CZVR", "role.centre", 125_950_000, .air, "region.centre"),
        ref("acc-w", "ref.acc-w", "CZVR", "role.centre", 134_800_000, .air, "region.centre"),
        ref("fic", "ref.fic", "FIC", "role.atis", 126_700_000, .air, "region.centre"),
        ref("ch16", "ref.ch16", "Ch 16", "role.marine", 156_800_000, .marine, "region.marine"),
        ref("vic-11", "ref.vic-11", "Ch 11", "role.vts", 156_550_000, .marine, "region.marine"),
        ref("vic-12", "ref.vic-12", "Ch 12", "role.vts", 156_600_000, .marine, "region.marine"),
        ref("vic-74", "ref.vic-74", "Ch 74", "role.vts", 156_725_000, .marine, "region.marine"),
        ref("vic-71", "ref.vic-71", "Ch 71", "role.vts", 156_575_000, .marine, "region.marine"),
        ref("pr-74", "ref.pr-74", "Ch 74", "role.vts", 156_725_000, .marine, "region.marine"),
        ref("ch13", "ref.ch13", "Ch 13", "role.ship", 156_650_000, .marine, "region.marine"),
        ref("ch83a", "ref.ch83a", "Ch 83A", "role.ccg", 157_175_000, .marine, "region.marine"),
        ref("sea-05a", "ref.sea-05a", "Ch 05A", "role.vts", 156_250_000, .marine, "region.marine"),
    ]

    static func legacyNameKey(_ stored: String) -> String? {
        legacyNames[stored]
    }

    private static let legacyNames: [String: String] = [
        "温哥华塔台南": "ref.yvr-twr-s", "温哥华塔台北": "ref.yvr-twr-n", "温哥华塔台备用": "ref.yvr-twr-bu",
        "温哥华地面南": "ref.yvr-gnd-s", "温哥华地面北": "ref.yvr-gnd-n", "温哥华放行": "ref.yvr-del",
        "温哥华 ATIS": "ref.yvr-atis", "温哥华进近外": "ref.yvr-app-hi", "温哥华进近内": "ref.yvr-app-lo",
        "温哥华离场北": "ref.yvr-dep-n", "温哥华离场南": "ref.yvr-dep-s", "温哥华终端": "ref.yvr-trsa",
        "温哥华海港塔台": "ref.yhc-twr", "温哥华海港放行": "ref.yhc-del", "温哥华海港 ATIS": "ref.yhc-atis",
        "维多利亚塔台内": "ref.yyj-twr-in", "维多利亚塔台外": "ref.yyj-twr-out", "维多利亚地面": "ref.yyj-gnd",
        "维多利亚放行": "ref.yyj-del", "维多利亚 ATIS": "ref.yyj-atis", "维多利亚进近": "ref.yyj-arr",
        "维多利亚离场": "ref.yyj-dep", "维多利亚终端": "ref.yyj-tml", "维多利亚港台": "ref.ywh-radio",
        "维多利亚港 ATIS": "ref.ywh-atis", "阿伯茨福德塔台": "ref.yxx-twr", "阿伯茨福德外塔": "ref.yxx-outer",
        "阿伯茨福德地面": "ref.yxx-gnd", "阿伯茨福德 ATIS": "ref.yxx-atis", "边界湾塔台": "ref.zbb-twr",
        "边界湾外塔": "ref.zbb-outer", "边界湾地面": "ref.zbb-gnd", "边界湾 ATIS": "ref.zbb-atis",
        "兰利塔台": "ref.ynj-twr", "兰利 ATIS": "ref.ynj-atis", "皮特梅多斯塔台": "ref.ypk-twr",
        "皮特梅多斯 ATIS": "ref.ypk-atis", "纳奈莫 ATIS": "ref.ycd-atis", "纳奈莫飞行服务": "ref.ycd-fss",
        "基洛纳塔台": "ref.ylw-twr", "基洛纳地面": "ref.ylw-gnd", "基洛纳 ATIS": "ref.ylw-atis",
        "坎卢普斯飞行服务": "ref.yka-fss", "乔治王子城塔台": "ref.yxs-twr", "乔治王子城地面": "ref.yxs-gnd",
        "乔治王子城 ATIS": "ref.yxs-atis", "科莫克斯塔台": "ref.yqq-twr", "科莫克斯地面": "ref.yqq-gnd",
        "科莫克斯 ATIS": "ref.yqq-atis", "科莫克斯终端": "ref.yqq-tml", "温哥华区调北": "ref.acc-n",
        "温哥华区调东": "ref.acc-e", "温哥华区调西": "ref.acc-w", "太平洋飞行情报": "ref.fic",
        "遇险与呼叫": "ref.ch16", "维多利亚交通": "ref.vic-11", "温哥华港交通": "ref.vic-12",
        "弗雷泽河交通": "ref.vic-74", "海峡北段交通": "ref.vic-71", "鲁珀特交通": "ref.pr-74",
        "船间导航": "ref.ch13", "海岸警卫联络": "ref.ch83a", "西雅图交通协同": "ref.sea-05a",
    ]

    static func nearest(_ hz: Double, mode: RadioMode, tolerance: Double = 8_000) -> AirReference? {
        references
            .filter { $0.mode == mode && abs($0.frequencyHz - hz) <= tolerance }
            .min { abs($0.frequencyHz - hz) < abs($1.frequencyHz - hz) }
    }

    static func grouped() -> [(region: String, items: [AirReference])] {
        regionOrder.compactMap { region in
            let items = references.filter { $0.region == region }
            return items.isEmpty ? nil : (region, items)
        }
    }

    private static func ref(
        _ id: String,
        _ name: String,
        _ place: String,
        _ role: String,
        _ hz: Double,
        _ mode: RadioMode,
        _ region: String
    ) -> AirReference {
        AirReference(id: id, name: name, place: place, role: role, frequencyHz: hz, mode: mode, region: region)
    }
}

nonisolated struct DetectedChannel: Sendable {
    var frequencyHz: Double
    var powerDB: Double
}

nonisolated struct ListenRequest: Sendable {
    var frequencyHz: Double
    var mode: RadioMode
    var gain: HardwareGain
    var volume: Float
    var squelchDB: Float
    var deemphasis75: Bool
}

nonisolated struct ConnectResult: Sendable {
    var ok: Bool
    var message: String
    var board: String
    var firmware: String
    var serial: String
}

nonisolated struct ReceiverTelemetry: Sendable {
    var signalDB: Double
    var spectrum: [Float]
    var clipRatio: Float
}

nonisolated struct ScanSnapshot: Sendable {
    var active: Bool
    var progress: Double
    var frequencyHz: Double
    var bandMeters: Int?
    var mode: RadioMode
    var foundCount: Int
    var message: String
    var spectrum: [Float]
    var freshFinds: [DetectedChannel]
}
