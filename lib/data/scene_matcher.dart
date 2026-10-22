import 'models.dart';
import 'scene_catalog.dart';

/// One scenery chosen for a run of verses, and why.
class ScenePick {
  final Scene scene;

  /// The verses this scenery was chosen for, 1-based and inclusive.
  final int firstAyah;
  final int lastAyah;

  /// The motif that won — `sea`, `night`, `garden`, … — or `fallback`
  /// when nothing in the verses named a place and the passage's own
  /// mood, or the app's default, decided instead.
  final String motif;

  /// The word (as written in the verse) that carried the decision, so
  /// the picker can say *why* a scenery was picked and not merely that
  /// it was. Empty for a fallback.
  final String evidence;

  const ScenePick({
    required this.scene,
    required this.firstAyah,
    required this.lastAyah,
    required this.motif,
    required this.evidence,
  });

  @override
  String toString() =>
      'ScenePick(${scene.id} for $firstAyah-$lastAyah · $motif "$evidence")';
}

/// A thing the Quran names that the scenery library has a picture of.
///
/// [stems] are unpointed Arabic stems matched against every word of a
/// verse after [SceneMatcher.stem] has taken the word's prefixes and
/// suffixes off — so `وَٱلْجِبَالَ` and `جِبَالًا` both reach `جبال`. Stems
/// are listed longest-first within a motif only for readability; the
/// match is exact or prefix, whichever [stemPrefix] allows.
///
/// [families] are the scene-id families that picture the motif, best
/// first: `sea` is an ocean before it is a coastline from the air.
class SceneMotif {
  final String id;
  final List<String> stems;
  final List<String> families;

  /// How strongly the motif claims a verse per matching word. A verse
  /// that names the sea once is about the sea; a verse that says
  /// "path" once is usually about guidance, so `road` claims less.
  final double weight;

  /// Prefer darker (`night`) or lighter (`day`) sceneries in the family,
  /// by the poster's measured luminance. Null for no preference.
  final SceneTone? tone;

  const SceneMotif({
    required this.id,
    required this.stems,
    required this.families,
    this.weight = 1.0,
    this.tone,
  });
}

/// Which end of a family's brightness a motif wants: the night wants
/// the dark skies, a verse about the sun the bright ones.
enum SceneTone { dark, light }

/// Picks sceneries for verses by what the verses say.
///
/// The library's scene ids are named for what is in the picture — a
/// `sky_`, an `ocean_`, a `mountains_`, a `sacred_` — and the Quran
/// names those same things constantly: the heavens, the seas, the
/// mountains set firm, the gardens beneath which rivers flow. So a
/// verse's own vocabulary is enough to choose a scene that shows what
/// it describes, and that is all this does. There is no model here and
/// nothing is guessed: a verse that says `ٱلْبَحْرِ` gets the sea, a verse
/// that says nothing pictorial gets the mood of the passage around it,
/// and a passage with no mood at all gets the sky — which is the tab
/// people pick more than any other when they choose by hand.
///
/// Pure: no I/O, no plugins. The catalog is handed in, so the same
/// verses over the same library always give the same answer — a user
/// who taps "match" twice sees the same reel twice, and a test can pin
/// every choice.
abstract final class SceneMatcher {
  /// Everything the library can picture, in the Quran's own words.
  ///
  /// Stems are unpointed and without the definite article; see
  /// [normalize] and [stem] for exactly what a word is reduced to
  /// before it is compared. A stem that is a prefix of many unrelated
  /// words (`ماء`, three letters, is also the start of `مائدة`) is kept
  /// out of [stemPrefix] and matched whole.
  static const motifs = <SceneMotif>[
    SceneMotif(
      id: 'night',
      stems: [
        'ليل', 'ليال', 'نجم', 'نجوم', 'كوكب', 'كواكب', 'قمر', 'شفق',
        'غسق', 'بروج', 'ظلمات', 'مصابيح', 'طارق', 'ثاقب', 'خنس', 'كنس',
        'سهر', 'عشاء', 'اسرى',
      ],
      families: ['aurora', 'sky'],
      tone: SceneTone.dark,
    ),
    SceneMotif(
      id: 'sky',
      stems: [
        'سماء', 'سموات', 'سماوات', 'شمس', 'ضحى', 'ضحا', 'نهار',
        'صبح', 'فجر', 'افق', 'عرش', 'سقف', 'اشراق', 'اسحار', 'سحر',
        'بكرة', 'اصيل', 'غدو', 'طير', 'طيرا', 'صافات', 'جناح', 'رفع',
      ],
      families: ['sky', 'clouds'],
      tone: SceneTone.light,
    ),
    SceneMotif(
      id: 'clouds',
      stems: [
        'سحاب', 'غمام', 'ريح', 'رياح', 'عاصف', 'مزن', 'ركام', 'رعد',
        'برق', 'صرصر', 'اعصار', 'ضباب', 'دخان',
      ],
      families: ['clouds', 'rain', 'sky'],
    ),
    SceneMotif(
      id: 'rain',
      stems: [
        'مطر', 'امطر', 'غيث', 'ودق', 'صيب', 'وابل', 'طل', 'ثجاج', 'قطر',
        'سيل',
      ],
      families: ['rain', 'water', 'clouds'],
    ),
    SceneMotif(
      id: 'sea',
      stems: [
        'بحر', 'بحار', 'بحرين', 'بحران', 'موج', 'امواج', 'فلك', 'سفينة',
        'سفن', 'لجي', 'جواري', 'جوار', 'غرق', 'اغرق', 'ساحل', 'يم',
        'جري', 'مرسى', 'مجرى', 'شاطئ', 'لؤلؤ', 'مرجان', 'حوت',
      ],
      families: ['ocean', 'water', 'aerial_coast', 'aerial_water'],
      weight: 1.3,
    ),
    SceneMotif(
      id: 'water',
      stems: [
        'انهار', 'نهر', 'انهر', 'عين', 'عيون', 'عينا', 'ينبوع', 'ينابيع',
        'ماء', 'مياه', 'شراب', 'سقى', 'سقاه', 'اسقي', 'جداول', 'سلسبيل',
        'كوثر', 'تسنيم', 'يسقون', 'شرب',
      ],
      families: ['water', 'aerial_water', 'forest', 'field'],
    ),
    SceneMotif(
      id: 'snow',
      stems: ['ثلج', 'برد', 'زمهرير', 'قر', 'بارد'],
      families: ['snow', 'mountains', 'aerial_mountain'],
    ),
    SceneMotif(
      id: 'mountain',
      stems: [
        'جبل', 'جبال', 'رواسي', 'طور', 'صخر', 'صخرة', 'حجر', 'حجارة',
        'كهف', 'غار', 'شامخات', 'اوتاد', 'رقيم', 'علو', 'اعالي', 'هضاب',
        'صفا', 'مروة', 'رجيم', 'قمم', 'حديد',
      ],
      families: ['mountains', 'rock', 'aerial_mountain', 'snow'],
      weight: 1.2,
    ),
    SceneMotif(
      id: 'desert',
      stems: [
        'صحراء', 'رمل', 'رمال', 'قفر', 'بادية', 'اعراب', 'ابل', 'ناقة',
        'جمل', 'بعير', 'سراب', 'قيعة', 'قاع', 'صفصف', 'هاجرة', 'خيام',
        'خيمة', 'بيد', 'رحلة', 'شتاء', 'صيف', 'عاد', 'ثمود', 'احقاف',
        'حجر', 'مدين', 'فلاة', 'سبخ', 'عير', 'قافلة', 'ظعن', 'ظمآن',
        'ظمأ', 'عطش', 'حر', 'ضاحية', 'رمضاء', 'تيه', 'سيناء', 'وادي',
        'واد', 'اودية', 'طوى',
      ],
      families: ['desert', 'aerial_desert', 'road'],
    ),
    SceneMotif(
      id: 'garden',
      stems: [
        'جنة', 'جنات', 'جنتين', 'جنتان', 'حدائق', 'حديقة', 'شجر', 'شجرة',
        'اشجار', 'نخل', 'نخيل', 'نخلة', 'زرع', 'زروع', 'حب', 'حبة',
        'نبات', 'انبت', 'ثمر', 'ثمرات', 'اثمار', 'اعناب', 'عنب', 'زيتون',
        'رمان', 'خضر', 'مخضرة', 'خضرا', 'ريحان', 'حرث', 'عشب', 'تين',
        'فاكهة', 'فواكه', 'روضة', 'روضات', 'بستان', 'ورق', 'اوراق',
        'سنبلة', 'سنابل', 'حصيد', 'يانع', 'الفاف', 'طلح', 'سدر', 'يقطين',
        'بقل', 'قثاء', 'فوم', 'عدس', 'بصل', 'ربوة', 'فردوس', 'عدن',
        'نعيم',
      ],
      families: ['forest', 'field', 'aerial_forest', 'water'],
      weight: 1.2,
    ),
    SceneMotif(
      id: 'land',
      stems: [
        'ارض', 'مهد', 'مهاد', 'بساط', 'فراش', 'سهل', 'بلد', 'بلدة', 'قرية',
        'قرى', 'فجاج', 'مشرق', 'مغرب', 'مشارق', 'مغارب', 'دحاها', 'بسط',
        'مدت', 'اقطار', 'مناكب', 'اقاليم', 'مدينة', 'مدائن', 'ديار',
      ],
      families: ['aerial_land', 'field', 'road', 'mountains'],
      weight: 0.55,
    ),
    SceneMotif(
      id: 'road',
      stems: [
        'صراط', 'سبيل', 'سبل', 'طريق', 'طرق', 'طرائق', 'سير', 'سيروا',
        'سيري', 'مشي', 'يمشون', 'سفر', 'هجرة', 'هاجر', 'مهاجر', 'خطوات',
        'سعى', 'سعي', 'رحل', 'مسير', 'اهد', 'هدى', 'هداية', 'مهتد',
        'مهتدون', 'رشد', 'رشاد', 'ضل', 'ضلال', 'منازل', 'مسافر', 'راكب',
        'مركب', 'انعام', 'دابة', 'دواب',
      ],
      families: ['road', 'aerial_land', 'desert'],
      weight: 0.8,
    ),
    SceneMotif(
      id: 'sacred',
      stems: [
        'مسجد', 'مساجد', 'كعبة', 'قبلة', 'صلاة', 'صلوة', 'صلوات', 'صلوا',
        'صل', 'يصلون', 'مصلى', 'مصلين', 'سجد', 'سجود', 'ساجد', 'اسجد',
        'ركع', 'راكع', 'ركوع', 'حج', 'عمرة', 'طواف', 'طوف', 'مكة', 'بكة',
        'مقام', 'منبر', 'محراب', 'اذان', 'قرآن', 'قران', 'كتاب', 'تلاوة',
        'يتلو', 'جمعة', 'نبي', 'نبيء', 'انبياء', 'رسول', 'رسل', 'محمد',
        'ملائكة', 'دعاء', 'ادعو', 'يدعو', 'ذكر', 'اذكر', 'ذاكر', 'سبح',
        'يسبح', 'تسبيح', 'حرام', 'بيت', 'بيوت', 'قيام', 'قانت', 'خشوع',
        'خاشع', 'قنوت', 'وضوء', 'زكاة', 'زكوة', 'صوم', 'صيام', 'رمضان',
        'قربان', 'نسك', 'منسك', 'مناسك', 'هدي', 'اعتكاف', 'مشعر', 'عرفات',
        'حطيم', 'ابراهيم', 'اسماعيل',
      ],
      families: ['sacred'],
      weight: 0.9,
    ),
    SceneMotif(
      id: 'light',
      stems: [
        'نور', 'انوار', 'مصباح', 'زجاجة', 'دري', 'ضياء', 'ضيا', 'سراج',
        'شعاع', 'وهج', 'وهاج', 'منير', 'مضيء', 'اضاء', 'يضيء', 'تجلى',
        'اشرق', 'سنا', 'بهاء', 'زهرة', 'لمع', 'بريق', 'صبح', 'يستضيء',
      ],
      families: ['aurora', 'abstract', 'sky'],
      tone: SceneTone.dark,
    ),
    SceneMotif(
      id: 'fire',
      stems: [
        'نار', 'نيران', 'جهنم', 'جحيم', 'سعير', 'لظى', 'حطمة', 'عذاب',
        'حريق', 'لهب', 'شهاب', 'شهب', 'سقر', 'هاوية', 'حميم', 'غساق',
        'سموم', 'يحموم', 'وقود', 'صلي', 'يصلى', 'تصلى', 'احرق', 'حرق',
        'جمر', 'رماد', 'دمر', 'صاعقة', 'صواعق', 'زلزال', 'زلزلة', 'صيحة',
        'رجفة', 'خسف', 'قارعة', 'واقعة', 'حاقة', 'طامة', 'صاخة', 'قيامة',
        'ساعة', 'حشر', 'ينفخ', 'صور', 'انشقت', 'انفطرت', 'كورت', 'سجرت',
        'سيرت', 'نسفت', 'بست', 'دكت', 'دك', 'كشط', 'انكدرت', 'خسوف',
      ],
      families: ['abstract', 'rock', 'desert', 'mountains'],
      tone: SceneTone.dark,
      weight: 0.9,
    ),
  ];

  /// Stems short enough to be the start of many unrelated words are
  /// matched whole; the rest may also match as a prefix of a longer
  /// stem (`جبال` in `جبالا`, `انهار` in `انهارا`).
  static const stemPrefix = 4;

  /// The family a portrait reel falls back to, and a wide one. The sky
  /// tab is where a verse is read more than anywhere else; the
  /// cinematic tab is the wide library's landscapes.
  static const fallbackFamilies = <String>['sky', 'aurora', 'clouds'];
  static const fallbackFamiliesWide = <String>['cinematic', 'aerial_land'];

  // ── text ───────────────────────────────────────────────────────────

  /// The verse with everything a reader adds taken off: harakat,
  /// tanween, sukun, the small marks, the tatweel, and the pause marks
  /// that stand as their own tokens. Alif variants collapse to bare
  /// alif, alif maqsura to ya, ta marbuta to ha — the spellings that
  /// vary between a mushaf and a dictionary, and nothing that would
  /// fold two different words into one.
  ///
  /// Two marks are *read* rather than dropped, because the mushaf's
  /// spelling leans on them:
  ///
  ///  * The dagger alif stands where a dictionary writes a full alif —
  ///    `جَنَّـٰت`, `سَمَـٰوَٰت`, `ٱلصِّرَٰط` — so it becomes one, and the
  ///    stems in the table can be written the way anyone would write
  ///    them.
  ///  * A shadda on the article's own lam (`ٱلَّيْل`) is the doubled lam
  ///    of `al-layl` written once; it is expanded, so the article can
  ///    be taken off and `ليل` remain. A shadda anywhere else is left
  ///    out, which also covers the assimilated article before a sun
  ///    letter (`ٱلسَّمَاء` reads `السماء`, not `السسماء`).
  static String normalize(String arabic) {
    final out = StringBuffer();
    var word = '';
    for (final c in arabic.runes) {
      if (c == 0x0651) {
        // Shadda: only the article's lam doubles — `ال` (bare, or
        // behind a one-letter particle) at the head of the word.
        if (word.endsWith('ال') &&
            (word.length == 2 ||
                (word.length == 3 && 'وفبكل'.contains(word[0])))) {
          out.write('ل');
          word += 'ل';
        }
        continue;
      }
      if (c == 0x0670) {
        out.writeCharCode(0x0627); // dagger alif -> alif
        word += 'ا';
        continue;
      }
      // Combining marks: 064B–065F, 06D6–06ED (small high/low signs,
      // pause marks and their kin), 08D3–08FF, and tatweel.
      if ((c >= 0x064B && c <= 0x065F) ||
          (c >= 0x06D6 && c <= 0x06ED) ||
          (c >= 0x08D3 && c <= 0x08FF) ||
          c == 0x0640) {
        continue;
      }
      if (c == 0x20) {
        out.write(' ');
        word = '';
        continue;
      }
      final mapped = switch (c) {
        0x0671 || 0x0622 || 0x0623 || 0x0625 => 0x0627, // ٱ آ أ إ -> ا
        0x0649 || 0x06CC => 0x064A, // ى (and Farsi ya) -> ي
        0x0629 => 0x0647, // ة -> ه
        0x0624 => 0x0648, // ؤ -> و
        0x0626 => 0x064A, // ئ -> ي
        _ => c,
      };
      out.writeCharCode(mapped);
      word += String.fromCharCode(mapped);
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const _prefixes = [
    'وبال', 'فبال', 'وكال', 'فكال', 'ولل', 'فلل', 'وال', 'فال', 'بال',
    'كال', 'لل', 'ال', 'وب', 'فب', 'ول', 'فل', 'وك', 'فك', 'وس', 'فس',
    'و', 'ف', 'ب', 'ك', 'ل', 'س',
  ];

  static const _suffixes = [
    'كموها', 'تموها', 'كمو', 'هما', 'كما', 'تما', 'كم', 'هم', 'هن',
    'نا', 'ها', 'ون', 'ين', 'ان', 'ات', 'وا', 'تم', 'تن', 'ني', 'ه',
    'ك', 'ي', 'ا', 'ت', 'ن',
  ];

  /// A normalized word reduced towards its stem: one prefix off the
  /// front, one suffix off the back, never below three letters.
  ///
  /// Both are also tried separately, and every candidate is returned,
  /// because a light stemmer cannot know whether the `و` on `وجه` is a
  /// conjunction or the first letter of the word — so the matcher is
  /// shown `وجه` and `جه` both, and only a stem in the table can win.
  static List<String> stem(String word) {
    final out = <String>{word};
    var core = word;
    for (final p in _prefixes) {
      if (core.length - p.length >= 3 && core.startsWith(p)) {
        core = core.substring(p.length);
        out.add(core);
        break;
      }
    }
    for (final base in out.toList()) {
      for (final s in _suffixes) {
        if (base.length - s.length >= 3 && base.endsWith(s)) {
          out.add(base.substring(0, base.length - s.length));
          break;
        }
      }
    }
    return out.toList();
  }

  /// Whether [candidate] (a stem of a verse word) names [motifStem].
  static bool _hits(String candidate, String motifStem) {
    if (candidate == motifStem) return true;
    if (motifStem.length < stemPrefix) return false;
    return candidate.startsWith(motifStem) &&
        candidate.length <= motifStem.length + 2;
  }

  /// [motifs]' stems as [read] compares them, normalized once. [read]
  /// used to normalize all 449 of them again for every word of every
  /// verse, on the main thread: Play, 1.0.8 patch 7, an Infinix HOT 30i
  /// stopped answering for five seconds matching sceneries to a
  /// passage (ANR 21a614f7, in this normalize's regex).
  static final List<List<String>> _targets = [
    for (final m in motifs)
      [for (final ms in m.stems) normalize(ms).replaceAll(' ', '')],
  ];

  /// Every motif the verse names, with a score and the word that named
  /// it, strongest first.
  static List<({SceneMotif motif, double score, String evidence})> read(
      String arabic) {
    final words = arabic.split(' ');
    final scores = <String, double>{};
    final evidence = <String, String>{};
    for (final raw in words) {
      final norm = normalize(raw);
      if (norm.isEmpty) continue;
      final stems = stem(norm);
      for (var i = 0; i < motifs.length; i++) {
        final m = motifs[i];
        var hit = false;
        for (final target in _targets[i]) {
          for (final c in stems) {
            if (_hits(c, target)) {
              hit = true;
              break;
            }
          }
          if (hit) break;
        }
        if (!hit) continue;
        scores[m.id] = (scores[m.id] ?? 0) + m.weight;
        evidence[m.id] ??= raw;
      }
    }
    final out = [
      for (final m in motifs)
        if (scores.containsKey(m.id))
          (motif: m, score: scores[m.id]!, evidence: evidence[m.id]!),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  // ── scenes ─────────────────────────────────────────────────────────

  /// Mean luminance of a scene's measured poster gradient, 0..1.
  static double luminance(Scene s) {
    double lum(int argb) {
      final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
      return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
    }

    if (s.gradientArgb.isEmpty) return 0.5;
    var sum = 0.0;
    for (final c in s.gradientArgb) {
      sum += lum(c);
    }
    return sum / s.gradientArgb.length;
  }

  /// Chooses [count] sceneries for [startAyah]..[endAyah] of [ayahs]
  /// out of [catalog], one shape only.
  ///
  /// The verses are dealt out over the scenes the way the reel will
  /// play them — [ScenePlan] cuts on verse boundaries, a run of verses
  /// per scene when there are more verses than scenes — so scene *k*
  /// is chosen for exactly the verses it will be on screen for.
  ///
  /// [ready] are scene ids already on the device (bundled or cached);
  /// among equally good candidates those come first, so a reel matched
  /// offline still gets pictures. Nothing is chosen twice.
  static List<ScenePick> match({
    required List<Ayah> ayahs,
    required int startAyah,
    required int endAyah,
    required int count,
    required bool wide,
    required List<Scene> catalog,
    Set<String> ready = const {},
  }) {
    if (ayahs.isEmpty || endAyah < startAyah || count < 1) return const [];
    final ayahCount = endAyah - startAyah + 1;
    final n = count > ayahCount ? ayahCount : count;

    // Deal the verses out over the scenes: even runs, remainder to the
    // front, which is what ScenePlan does with even weights.
    final runs = <({int first, int last})>[];
    final per = ayahCount ~/ n;
    final spare = ayahCount % n;
    var a = startAyah;
    for (var i = 0; i < n; i++) {
      final len = per + (i < spare ? 1 : 0);
      runs.add((first: a, last: a + len - 1));
      a += len;
    }

    // What every verse says, once.
    final readings = <int, List<({SceneMotif motif, double score, String evidence})>>{};
    for (var v = startAyah; v <= endAyah; v++) {
      final i = v - 1;
      if (i < 0 || i >= ayahs.length) continue;
      readings[v] = read(ayahs[i].arabic);
    }

    // The passage's own mood, for verses that name nothing: the motif
    // that carries the most weight across the whole selection.
    final passage = <String, ({SceneMotif motif, double score, String evidence})>{};
    for (final r in readings.values) {
      for (final e in r) {
        final have = passage[e.motif.id];
        passage[e.motif.id] = have == null
            ? e
            : (motif: e.motif, score: have.score + e.score, evidence: have.evidence);
      }
    }
    final mood = passage.values.toList()
      ..sort((x, y) => y.score.compareTo(x.score));

    final used = <String>{};
    final usedFamilies = <String, int>{};
    final picks = <ScenePick>[];
    for (final run in runs) {
      // The run's strongest motif: scores summed over its verses.
      final sum = <String, ({SceneMotif motif, double score, String evidence})>{};
      for (var v = run.first; v <= run.last; v++) {
        for (final e in readings[v] ?? const []) {
          final have = sum[e.motif.id];
          sum[e.motif.id] = have == null
              ? e
              : (motif: e.motif, score: have.score + e.score, evidence: have.evidence);
        }
      }
      final ranked = sum.values.toList()
        ..sort((x, y) => y.score.compareTo(x.score));
      final candidates = [
        ...ranked,
        ...mood.where((m) => !sum.containsKey(m.motif.id)),
      ];

      Scene? chosen;
      String motifId = 'fallback';
      String evidence = '';
      for (final c in candidates) {
        final s = _pickScene(
          families: c.motif.families,
          tone: c.motif.tone,
          wide: wide,
          catalog: catalog,
          ready: ready,
          used: used,
          usedFamilies: usedFamilies,
          seed: run.first,
        );
        if (s == null) continue;
        chosen = s;
        motifId = c.motif.id;
        evidence = sum.containsKey(c.motif.id) ? c.evidence : '';
        break;
      }
      chosen ??= _pickScene(
        families: wide ? fallbackFamiliesWide : fallbackFamilies,
        tone: null,
        wide: wide,
        catalog: catalog,
        ready: ready,
        used: used,
        usedFamilies: usedFamilies,
        seed: run.first,
      );
      // A library with nothing of this shape at all: take anything of
      // it, and failing that stop — a reel is not improved by a
      // scenery it cannot show.
      chosen ??= _pickScene(
        families: const [],
        tone: null,
        wide: wide,
        catalog: catalog,
        ready: ready,
        used: used,
        usedFamilies: usedFamilies,
        seed: run.first,
        any: true,
      );
      if (chosen == null) break;
      used.add(chosen.id);
      usedFamilies[chosen.family] = (usedFamilies[chosen.family] ?? 0) + 1;
      picks.add(ScenePick(
        scene: chosen,
        firstAyah: run.first,
        lastAyah: run.last,
        motif: motifId,
        evidence: evidence,
      ));
    }
    return picks;
  }

  /// The best unused scene in the first of [families] that has one,
  /// with ties broken so the choice is stable across taps.
  ///
  /// Ordering inside a family: on the device before not, the asked-for
  /// tone before the other, then a deterministic shuffle keyed on the
  /// verse — so consecutive verses that both want the sky get two
  /// different skies rather than the first two in the catalog, and the
  /// same verse always gets the same one.
  static Scene? _pickScene({
    required List<String> families,
    required SceneTone? tone,
    required bool wide,
    required List<Scene> catalog,
    required Set<String> ready,
    required Set<String> used,
    required Map<String, int> usedFamilies,
    required int seed,
    bool any = false,
  }) {
    final order = any ? const <String>[''] : families;
    for (final fam in order) {
      var pool = catalog.where((s) =>
          s.wide == wide &&
          !used.contains(s.id) &&
          (any || s.family == fam)).toList();
      if (pool.isEmpty) continue;
      // The tone keeps the better half of the family — the darker
      // skies for the night — and no more than that: which of the
      // dark ones is the shuffle's to decide, or every night verse
      // would get the same darkest sky. Halved among the sceneries on
      // the device and among the rest apart, because being on the
      // device comes first: halving the family as a whole left a phone
      // offline with only the half it had nothing of.
      List<Scene> toned(List<Scene> p) {
        if (tone == null || p.length <= 1) return p;
        p.sort((x, y) {
          final lx = luminance(x), ly = luminance(y);
          return tone == SceneTone.dark ? lx.compareTo(ly) : ly.compareTo(lx);
        });
        return p.sublist(0, (p.length + 1) ~/ 2);
      }

      pool = [
        ...toned([for (final s in pool) if (ready.contains(s.id)) s]),
        ...toned([for (final s in pool) if (!ready.contains(s.id)) s]),
      ];
      pool.sort((x, y) {
        final rx = ready.contains(x.id) ? 0 : 1;
        final ry = ready.contains(y.id) ? 0 : 1;
        if (rx != ry) return rx - ry;
        return _hash(x.id, seed) - _hash(y.id, seed);
      });
      // Past the first pick from a family, skip a step through the
      // pool so two verses in a row do not take neighbouring entries.
      final skip = (usedFamilies[fam] ?? 0) % pool.length;
      return pool[skip];
    }
    return null;
  }

  static int _hash(String id, int seed) {
    var h = 0x811C9DC5 ^ seed;
    for (final c in id.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7FFFFFFF;
    }
    return h;
  }
}
