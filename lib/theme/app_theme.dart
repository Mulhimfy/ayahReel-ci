import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/verse_font.dart';
import '../l10n/app_lang.dart';

/// Design system for Ayah Reels.
///
/// Night-sky charcoal base, warm gold accent. One accent color only:
/// gold is reserved exclusively for the single most-desired action on
/// each screen, so the eye always knows where to go.
abstract final class AppColors {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceRaised = Color(0xFF1F2630);
  static const gold = Color(0xFFD4A947);
  static const goldBright = Color(0xFFEEC96B);

  /// The gold for text that has to be *read* on a light ground.
  ///
  /// [gold] is tuned against the app's own night and manages about 2:1
  /// on the ivory, sand and rose papers a card can stand on — visible
  /// as an accent, not readable as a line. This clears 4.5:1 on all
  /// three and is still unmistakably gold rather than ink.
  static const goldDeep = Color(0xFF7A5A24);
  static const textPrimary = Color(0xFFF2EFE6);
  static const textSecondary = Color(0xFF9BA3AE);
  static const stroke = Color(0xFF2A313B);
}

abstract final class AppTheme {
  /// One [ThemeData] per language, built once.
  ///
  /// Not a micro-optimisation. Building this theme resolves fifteen
  /// text styles through google_fonts, and the whole app is rebuilt
  /// whenever *any* setting changes — the verse translation, a
  /// reminder switch, a nudge dot going out. Each of those was
  /// building a brand new ThemeData, and a new ThemeData is a new
  /// object for every `Theme.of` dependent in the tree to compare
  /// itself against and rebuild for. Changing the translation edition
  /// half a dozen times in a row was re-laying the entire app that
  /// many times over, which is exactly what it felt like.
  ///
  /// Keyed by language because language is the only thing the theme
  /// reads; five entries is the whole cache, for the life of the
  /// process.
  static final Map<AppLang, ThemeData> _cache = {};

  /// [lang] only ever decides typography here: it swaps the Latin UI
  /// face for one with full Arabic coverage and drops the negative
  /// letter-spacing, which breaks joined script. Arabic and Urdu both
  /// take that face. Colors and layout stay identical.
  static ThemeData dark({AppLang lang = AppLang.en}) =>
      _cache[lang] ??= _build(lang);

  static ThemeData _build(AppLang lang) {
    final arabic = lang.arabicScript;
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.gold,
        surface: AppColors.surface,
        onPrimary: Color(0xFF14100A),
        onSurface: AppColors.textPrimary,
      ),
      splashFactory: InkSparkle.splashFactory,
      // Slide-over-with-parallax transitions instead of Android's stock
      // zoom: screens feel like one continuous flow, and users get the
      // swipe-from-left-edge back gesture for free.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
    // IBM Plex Sans Arabic keeps the same quiet, modern feel as Inter
    // while shaping Arabic properly; Inter itself has no Arabic glyphs.
    // It also covers Urdu whole — every codepoint of the Urdu edition
    // was checked against its cmap, see tool/verify_translations.py —
    // so Urdu needs no font of its own.
    final ui = arabic ? GoogleFonts.ibmPlexSansArabic : GoogleFonts.inter;
    final uiTheme = arabic
        ? GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme)
        : GoogleFonts.interTextTheme(base.textTheme);
    return base.copyWith(
      textTheme: uiTheme.copyWith(
        headlineMedium: ui(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: arabic ? 0 : -0.5,
          color: AppColors.textPrimary,
        ),
        titleMedium: ui(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: ui(
          fontSize: 14.5,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
        labelLarge: ui(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: arabic ? 0 : 0.2,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }

  /// Quran text style, in whichever face the reel is typeset in —
  /// the mushaf's own KFGQPC Hafs unless the user chose otherwise.
  ///
  /// [size] is the size the *default* face would be set at; each face
  /// scales it by its own [VerseFace.sizeFactor] so two faces at one
  /// nominal size are the same size on the page, which they are not
  /// otherwise. The line box comes from the face too, and is never
  /// below the one the file itself declares — that is where the marks
  /// of one line start landing on the line above. See
  /// `lib/data/verse_font.dart`, and `tool/verify_fonts.py`, which
  /// re-derives both numbers from the files.
  ///
  /// Every face here is bundled, so this resolves synchronously and
  /// identically whether or not the phone has a network — which the
  /// exporter depends on, since it rasterizes this very style.
  static TextStyle quran({
    double size = 30,
    Color color = Colors.white,
    VerseFace face = VerseFace.uthmani,
  }) {
    return TextStyle(
      fontFamily: face.family,
      fontFamilyFallback: face.fallback,
      fontSize: size * face.sizeFactor,
      height: face.height,
      color: color,
    );
  }

  /// The translation line, in whichever face the reel is typeset in.
  ///
  /// [arabic] is still what decides the *script*: pass it for any
  /// translation set in Arabic script, which is Urdu as well as
  /// Arabic, and [VerseTranslation.arabicScript] is what answers it.
  /// It picks the default face for that script when no [face] is
  /// given, so every caller that only ever meant "is this Arabic"
  /// keeps reading the way it did.
  ///
  /// The italic is the face's own business now rather than the
  /// script's: Inter is sloped, because that is the look the app
  /// shipped with, and joined script never is — but neither is a
  /// serif face set under a verse, where upright reads better.
  ///
  /// The Latin faces carry an Arabic fallback even when the
  /// translation is English, and that is not belt and braces: Saheeh
  /// International writes the honorific after the Prophet's name as
  /// the single ligature ﷺ (U+FDFA), 34 times, and no Latin face has
  /// a glyph for it. Without the fallback those 34 verses show a tofu
  /// box — on screen and baked into an exported reel.
  static TextStyle translation({
    double size = 14,
    Color? color,
    bool arabic = false,
    TranslationFace? face,
  }) {
    final f = face ?? TranslationFace.defaultFor(arabicScript: arabic);
    return TextStyle(
      fontFamily: f.family,
      fontFamilyFallback: f.fallback,
      fontSize: size * f.sizeFactor,
      height: f.height,
      fontStyle: f.italic ? FontStyle.italic : FontStyle.normal,
      color: color ?? Colors.white.withValues(alpha: 0.85),
    );
  }
}
