import ImageIO
import SwiftUI
import WidgetKit

// The home-screen widget: a verse from the Quran over a photograph
// from the scene library, turning twice a day.
//
// Nothing here talks to Flutter, and there is no App Group: the verse
// comes from the widget's own copy of the list and the date (see
// VerseSchedule), the picture from the frames in Backgrounds/ (cut
// from the scene library by tool/widget_backgrounds.sh), the font from
// the same KFGQPC face the app renders with. WidgetKit draws it from a
// short timeline of the next turns, reloaded on its own, so it keeps
// turning on a phone where the app has not been opened in weeks.

/// How many pictures tool/widget_backgrounds.sh cut.
private let backgroundCount = 100

struct VerseEntry: TimelineEntry {
  let date: Date
  let verse: VerseSchedule.Verse
  let jumuah: Bool
  let background: Int
  /// The widget's size on this phone, so the picture is decoded no
  /// larger than it is drawn.
  let displaySize: CGSize
}

struct VerseProvider: TimelineProvider {
  private func entry(at date: Date, size: CGSize) -> VerseEntry {
    let s = VerseSchedule.shared
    return VerseEntry(
      date: date,
      verse: s.verse(at: date),
      jumuah: s.isJumuah(date),
      background: s.background(at: date, count: backgroundCount),
      displaySize: size)
  }

  func placeholder(in context: Context) -> VerseEntry {
    entry(at: Date(), size: context.displaySize)
  }

  func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
    completion(entry(at: Date(), size: context.displaySize))
  }

  /// Now and the next two turns (noon and midnight), then ask again.
  /// WidgetKit renders every entry of every placed size up front and
  /// the extension is capped near 30 MB, so a week of entries with a
  /// picture each was jetsammed the moment a second size was added.
  /// `.after` reloads without the app being opened, so it keeps
  /// turning all the same.
  func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
    let s = VerseSchedule.shared
    let size = context.displaySize
    let first = s.nextTurn(after: Date())
    let second = s.nextTurn(after: first)
    let entries = [
      entry(at: Date(), size: size),
      entry(at: first, size: size),
      entry(at: second, size: size),
    ]
    completion(Timeline(entries: entries, policy: .after(second)))
  }
}

/// Whether the phone's UI language is Arabic. Read off the preferred
/// languages list rather than `Locale.current.language`, which is an
/// iOS 16 API and the extension still builds for iOS 15 — the App
/// Store build for 1.0.5 died on exactly that.
var arabicUI: Bool {
  (Locale.preferredLanguages.first ?? "").hasPrefix("ar")
}

struct VerseView: View {
  let entry: VerseEntry
  @Environment(\.widgetFamily) private var family

  private var label: String {
    entry.jumuah
      ? (arabicUI ? "اليوم الجمعة" : "IT’S JUMU’AH")
      : (arabicUI ? "آية من القرآن" : "VERSE FROM THE QURAN")
  }

  /// Matches DayVerseCard.arabicSize in the app, scaled to the family.
  private var arabicSize: CGFloat {
    let words = entry.verse.shown.split(separator: " ").filter { $0.count > 1 }.count
    let base: CGFloat = words <= 9 ? 18 : (words <= 12 ? 16.5 : 15)
    switch family {
    case .systemSmall: return base * 0.82
    case .systemLarge: return base * 1.35
    default: return base
    }
  }

  private var arabicLines: Int {
    switch family {
    case .systemSmall: return 4
    case .systemLarge: return 6
    default: return 3
    }
  }

  private var showTranslation: Bool { !arabicUI && family != .systemSmall }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(label)
          .font(.system(size: family == .systemLarge ? 11 : 9.5, weight: .bold))
          .kerning(1.1)
          .foregroundColor(Palette.gold)
          .lineLimit(1)
        Spacer(minLength: 8)
        Text(entry.verse.reference(arabicUI: arabicUI))
          .font(.system(size: family == .systemLarge ? 11 : 9.5))
          .foregroundColor(Palette.muted)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      Text(entry.verse.shown)
        .font(QuranFont.font(size: arabicSize))
        .foregroundColor(Palette.goldBright)
        .multilineTextAlignment(.center)
        .lineLimit(arabicLines)
        .minimumScaleFactor(0.7)
        .lineSpacing(family == .systemLarge ? 6 : 3)
        .environment(\.layoutDirection, .rightToLeft)
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
      Spacer(minLength: 2)
      if showTranslation {
        Text(entry.verse.translation)
          .font(.system(size: family == .systemLarge ? 12.5 : 10.5).italic())
          .foregroundColor(Palette.text)
          .multilineTextAlignment(.center)
          .lineLimit(family == .systemLarge ? 4 : 2)
          .frame(maxWidth: .infinity)
          .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
      }
      signature
    }
    .padding(legacyPadding)
    .widgetBackground(background)
    .widgetURL(entry.verse.link)
  }

  /// The maker's mark: the app's name, small and tracked, under a
  /// hairline of gold at the foot — the way a page is signed, not a
  /// logo stamped on it. The same in both languages: it is the name.
  private var signature: some View {
    VStack(spacing: 2) {
      Rectangle()
        .fill(Palette.gold.opacity(0.55))
        .frame(width: 28, height: 0.5)
      Text("✦  AYAHREEL")
        .font(.system(size: family == .systemLarge ? 9 : 7.5, weight: .bold))
        .kerning(1.8)
        .foregroundColor(Palette.gold)
        .lineLimit(1)
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 2)
  }

  /// iOS 17 pads the content itself; earlier versions draw edge to
  /// edge and need the same margin by hand.
  private var legacyPadding: CGFloat {
    if #available(iOSApplicationExtension 17.0, *) { return 0 }
    return 14
  }

  /// The picture, centre-cropped to the widget, under a scrim that
  /// darkens towards the foot so gold script and the translation read
  /// on the brightest scenery.
  private var background: some View {
    ZStack {
      Palette.night
      if let image = Backgrounds.image(entry.background, fitting: entry.displaySize) {
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      }
      LinearGradient(
        stops: [
          .init(color: Palette.night.opacity(0.36), location: 0),
          .init(color: Palette.night.opacity(0.48), location: 0.5),
          .init(color: Palette.night.opacity(0.76), location: 1),
        ],
        startPoint: .top, endPoint: .bottom)
    }
    // A filled picture is wider than the widget; without this the
    // overflow is drawn and iOS 15/16 may size the view past its slot.
    .clipped()
  }
}

/// The app's palette (lib/theme/app_theme.dart).
private enum Palette {
  static let gold = Color(red: 0xD4 / 255, green: 0xA9 / 255, blue: 0x47 / 255)
  static let goldBright = Color(red: 0xEE / 255, green: 0xC9 / 255, blue: 0x6B / 255)
  static let text = Color(red: 0xF2 / 255, green: 0xEF / 255, blue: 0xE6 / 255)
  static let muted = Color(red: 0xC9 / 255, green: 0xCF / 255, blue: 0xD6 / 255).opacity(0.85)
  static let night = Color(red: 0x0B / 255, green: 0x0C / 255, blue: 0x14 / 255)
}

/// The frames in Backgrounds/, a folder reference in this target so
/// they ride in the bundle as files rather than an asset catalog.
/// Decoded through ImageIO at the widget's own pixel size rather than
/// the file's 960x640: a WidgetKit process is capped near 30 MB, a
/// full frame is 2.5 MB decoded, and a small widget needs a tenth.
private enum Backgrounds {
  static func image(_ index: Int, fitting size: CGSize) -> Image? {
    let name = String(format: "wbg_%02d", index)
    guard
      let url = Bundle.main.url(
        forResource: name, withExtension: "jpg", subdirectory: "Backgrounds")
        ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    else { return nil }
    let scale = UIScreen.main.scale
    let longest = max(size.width, size.height, 1) * scale
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(longest.rounded(.up)),
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return Image(uiImage: UIImage(cgImage: cg, scale: scale, orientation: .up))
  }
}

/// The KFGQPC Hafs face, registered from the bundle the first time it
/// is asked for. Registered from its descriptor rather than by name,
/// so the face's own PostScript name never has to be spelled here.
private enum QuranFont {
  private static let descriptor: CTFontDescriptor? = {
    guard let url = Bundle.main.url(forResource: "UthmanicHafs", withExtension: "ttf") else {
      return nil
    }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
    else { return nil }
    return descriptors.first
  }()

  static func font(size: CGFloat) -> Font {
    guard let d = descriptor else { return .system(size: size) }
    return Font(CTFontCreateWithFontDescriptor(d, size, nil))
  }
}

extension View {
  /// iOS 17's container background, which fills the widget behind the
  /// system margins; a plain background before that.
  @ViewBuilder
  func widgetBackground<B: View>(_ background: B) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { background }
    } else {
      self.background(background)
    }
  }
}

struct AyahWidget: Widget {
  let kind = "AyahWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: VerseProvider()) { entry in
      VerseView(entry: entry)
    }
    .configurationDisplayName(
      arabicUI ? "آية من القرآن" : "Verse from the Quran")
    .description(
      arabicUI
        ? "آية من القرآن، مرتين في اليوم، على خلفية جديدة. انقرها لفتح التطبيق."
        : "A verse from the Quran, twice a day, on a new scenery. Tap it to open the app.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct AyahWidgetBundle: WidgetBundle {
  var body: some Widget {
    AyahWidget()
  }
}
