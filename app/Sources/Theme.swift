import AppKit
import CAMRCore
import SwiftUI

extension NSColor {
    static func camr(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

enum Theme {
    /// The page follows the Mac's appearance: warm paper by day, warm dark by night.
    static let pageNS = NSColor.camr(light: NSColor(hex: 0xFAF6EE), dark: NSColor(hex: 0x1C1B19))
    static let inkNS = NSColor.camr(light: NSColor(hex: 0x2B2620), dark: NSColor(hex: 0xE9E4DA))
    static let inkSoftNS = NSColor.camr(light: NSColor(hex: 0x6F675C), dark: NSColor(hex: 0x9D968A))
    static let inkFaintNS = NSColor.camr(light: NSColor(hex: 0xB5AC9E), dark: NSColor(hex: 0x5E5951))
    static let wellNS = NSColor.camr(light: NSColor(hex: 0xEFE9DC), dark: NSColor(hex: 0x2A2825))
    static let tagNS = NSColor.camr(light: NSColor(hex: 0x8A5A12), dark: NSColor(hex: 0xE3B66A))

    static let page = Color(nsColor: pageNS)
    static let ink = Color(nsColor: inkNS)
    static let inkSoft = Color(nsColor: inkSoftNS)
    static let well = Color(nsColor: wellNS)

    /// Gold is what the model has read, or where you are. Nothing else uses it.
    static let gold = Color(red: 1, green: 0.84, blue: 0.52)

    /// One colour per top-level folder, so colour always answers "which part of the vault is this".
    static let clusters: [Color] = [
        Color(red: 0.50, green: 0.70, blue: 1.00), Color(red: 0.49, green: 0.89, blue: 0.76), Color(red: 1.00, green: 0.60, blue: 0.64),
        Color(red: 0.78, green: 0.65, blue: 1.00), Color(red: 0.56, green: 0.89, blue: 0.53), Color(red: 1.00, green: 0.69, blue: 0.44),
        Color(red: 0.44, green: 0.85, blue: 0.95), Color(red: 0.95, green: 0.65, blue: 0.88), Color(red: 0.85, green: 0.88, blue: 0.44),
    ]
    static let otherCluster = Color(red: 0.62, green: 0.65, blue: 0.74)

    static func colour(for kind: NoteKind) -> Color {
        switch kind {
        case .decision: return .blue
        case .rejected: return .red
        case .bug: return .orange
        case .convention: return .green
        case .note: return .secondary
        }
    }
}

extension NoteKind {
    var label: String {
        switch self {
        case .decision: return "Decision"
        case .rejected: return "Rejected"
        case .bug: return "Bug"
        case .convention: return "Convention"
        case .note: return "Note"
        }
    }
}

extension String {
    var fileName: String { (self as NSString).lastPathComponent }
    var folderPath: String { (self as NSString).deletingLastPathComponent }
    var title: String {
        let name = fileName
        return ["md", "markdown"].contains((name as NSString).pathExtension.lowercased()) ? (name as NSString).deletingPathExtension : name
    }
    /// A tool's name the way a person reads it: vault_search and camr_find become "search" and "find".
    var toolTitle: String {
        var name = self
        for prefix in ["vault_", "camr_"] where name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        return name.replacingOccurrences(of: "_", with: " ")
    }
    var isMarkdownPath: Bool { ["md", "markdown"].contains((self as NSString).pathExtension.lowercased()) }
}

// MARK: Colour themes

/// The night's colour: it tints the sky behind every dark page, the selection, the active tab and the buttons.
/// Kind colours (decision, handoff, stale) stay fixed whatever the theme, so colour keeps its meaning.
enum SkyTheme: String, CaseIterable, Identifiable {
    case nebula, aurora, ember, tide

    /// Kept under its first name: the app's settings stay where 1.3 saved them, so the rename to CAMR keeps the theme.
    static let key = "burrow.skyTheme"
    /// Ember, the logo's colour, unless the person picked another (D-120).
    static let standard = SkyTheme.ember
    var id: String { rawValue }

    var name: String {
        switch self {
        case .nebula: return "Nebula"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .tide: return "Tide"
        }
    }

    var accent: Color {
        switch self {
        case .nebula: return Color(red: 0.66, green: 0.55, blue: 1.00)
        case .aurora: return Color(red: 0.35, green: 0.92, blue: 0.70)
        case .ember: return Color(red: 1.00, green: 0.48, blue: 0.10)
        case .tide: return Color(red: 0.38, green: 0.72, blue: 1.00)
        }
    }

    /// Two glows that drift slowly across the sky.
    var glows: (Color, Color) {
        switch self {
        case .nebula: return (Color(red: 0.42, green: 0.22, blue: 0.85), Color(red: 0.10, green: 0.45, blue: 0.80))
        case .aurora: return (Color(red: 0.05, green: 0.60, blue: 0.45), Color(red: 0.20, green: 0.30, blue: 0.75))
        case .ember: return (Color(red: 0.85, green: 0.30, blue: 0.05), Color(red: 0.55, green: 0.14, blue: 0.05))
        case .tide: return (Color(red: 0.10, green: 0.35, blue: 0.85), Color(red: 0.05, green: 0.60, blue: 0.70))
        }
    }

    static var current: SkyTheme { SkyTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .standard }
}

/// The ground of every dark page: near-black with two soft glows that drift, and a sparse field of stars that twinkle.
/// It stays still when Reduce Motion is on, and it never takes a click.
struct NightSky: View {
    @AppStorage(SkyTheme.key) private var themeName = SkyTheme.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var theme: SkyTheme { SkyTheme(rawValue: themeName) ?? .standard }

    private static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, phase: Double)] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        return (0..<140).map { _ in (next(), next(), 0.4 + next() * 1.1, Double(next()) * 6.28) }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.012, green: 0.012, blue: 0.025)))
                let (a, b) = theme.glows
                let reach = max(size.width, size.height)
                let first = CGPoint(x: size.width * (0.78 + 0.06 * sin(t / 23)), y: size.height * (0.08 + 0.05 * cos(t / 31)))
                let second = CGPoint(x: size.width * (0.12 + 0.07 * cos(t / 27)), y: size.height * (0.92 + 0.04 * sin(t / 19)))
                for (centre, colour, radius) in [(first, a, reach * 0.62), (second, b, reach * 0.5)] {
                    canvas.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                                with: .radialGradient(Gradient(colors: [colour.opacity(0.22), colour.opacity(0.06), .clear]),
                                                      center: centre, startRadius: 0, endRadius: radius))
                }
                for star in Self.stars {
                    let twinkle = 0.35 + 0.35 * (1 + sin(t * 0.9 + star.phase)) / 2
                    let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.r, height: star.r)
                    canvas.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle * 0.55)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Cards rise and fade in one after another as a page opens; at once when Reduce Motion is on.
struct Arrive: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85).delay(Double(min(index, 12)) * 0.045)) { shown = true }
            }
    }
}

extension View {
    func arrive(_ index: Int) -> some View { modifier(Arrive(index: index)) }
}

/// A card on the night sky: frosted, with a hairline edge that brightens and a small lift on hover.
struct SkyCard: ViewModifier {
    var tint: Color = .white
    var radius: CGFloat = 14
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(LinearGradient(colors: [tint.opacity(hovering ? 0.13 : 0.09), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background(.ultraThinMaterial.opacity(0.35), in: .rect(cornerRadius: radius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(LinearGradient(colors: [tint.opacity(hovering ? 0.55 : 0.32), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: tint.opacity(hovering ? 0.22 : 0.0), radius: 18, y: 6)
            .scaleEffect(hovering ? 1.004 : 1)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func skyCard(tint: Color = .white, radius: CGFloat = 14) -> some View { modifier(SkyCard(tint: tint, radius: radius)) }
}

// MARK: The mark

/// The logo files that ride inside the app (build.sh copies app/Resources/Brand). Missing ones are nil, so a bare
/// `swift run` still opens, without the pictures.
enum Brand {
    static let c = image("camr-c")
    static let wordmark = image("camr-wordmark")
    /// The logo's two ends: the C runs from amber at the top to red at the bottom.
    static let amber = Color(red: 1.00, green: 0.67, blue: 0.00)
    static let flame = Color(red: 1.00, green: 0.24, blue: 0.07)

    private static func image(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
}

/// CAMR's mark: the orange C of the logo (D-124; the B before it, D-120, replaced the Ledger Strata bands).
struct CAMRMark: View {
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let c = Brand.c {
                Image(nsImage: c).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Text("C").font(.system(size: size * 0.8, weight: .black)).fontWidth(.expanded)
                    .foregroundStyle(LinearGradient(colors: [Brand.amber, Brand.flame], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("CAMR")
    }
}

/// The logo with its name: the C and AMR, as on the launch screen (D-124).
struct CAMRWordmark: View {
    var height: CGFloat = 44

    var body: some View {
        Group {
            if let wordmark = Brand.wordmark {
                Image(nsImage: wordmark).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Text("CAMR").font(.system(size: height * 0.8, weight: .heavy)).fontWidth(.expanded).foregroundStyle(.white)
            }
        }
        .frame(height: height)
        .accessibilityLabel("CAMR")
    }
}
