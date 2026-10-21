import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/render/motion_graph.dart';

/// The motion's half of the export's filter graph. What it draws is
/// only ever proved by an encode, so the shape of what it writes is
/// pinned here: every stream made is used exactly once, a card outside
/// every fade is written as the graph always wrote it, and each piece
/// is timed in its unit's clock whatever pass it falls in.
void main() {
  /// Checks the graph's wiring: each label made once and used once,
  /// nothing used before it is made, and returns the labels left open.
  List<String> wiring(String graph, String start) {
    final made = <String>{start};
    final used = <String>{};
    for (final chain in graph.split(';').where((c) => c.isNotEmpty)) {
      final ins = RegExp(r'^((?:\[[A-Za-z0-9_:]+\])+)').firstMatch(chain);
      final outs = RegExp(r'((?:\[[A-Za-z0-9_:]+\])+)$').firstMatch(chain);
      for (final m in RegExp(r'\[([A-Za-z0-9_:]+)\]')
          .allMatches(ins?.group(1) ?? '')) {
        final l = m.group(1)!;
        if (l.contains(':')) continue; // an input stream
        expect(made.contains(l), isTrue, reason: '$l used before made');
        expect(used.add(l), isTrue, reason: '$l used twice');
      }
      for (final m in RegExp(r'\[([A-Za-z0-9_:]+)\]')
          .allMatches(outs?.group(1) ?? '')) {
        expect(made.add(m.group(1)!), isTrue,
            reason: '${m.group(1)} made twice');
      }
    }
    return made.difference(used).toList();
  }

  final rows = [
    MotionRow(
      left: 140,
      right: 940,
      top: 60,
      bottom: 150,
      threadY: 132,
      progress: RowProgress.words(const [
        (startMs: 300, endMs: 900, from: 0, to: 300),
        (startMs: 1000, endMs: 2600, from: 320, to: 800),
      ], 800),
    ),
  ];

  String write(VerseMotion motion,
      {int passStart = 0,
      int passEnd = 6000,
      List<MotionCard>? cards,
      int? glint}) {
    final f = StringBuffer();
    final last = VerseMotionGraph.write(
      f,
      prev: 'v0',
      cards: cards ??
          const [
            MotionCard(
                input: 3,
                startMs: 500,
                endMs: 2000,
                unitStartMs: 500,
                unitEndMs: 3500),
            MotionCard(
                input: 4,
                startMs: 2000,
                endMs: 3500,
                unitStartMs: 500,
                unitEndMs: 3500),
          ],
      units: [
        MotionUnit(
          startMs: 500,
          endMs: 3500,
          cardTop: 800,
          cardH: 300,
          rows: rows,
          glintInput: glint,
        ),
      ],
      motion: motion,
      passStartMs: passStart,
      passEndMs: passEnd,
      baseY: '(H-h)*0.500',
      threadInput: 7,
      sparkInput: 8,
    );
    final graph = f.toString();
    expect(wiring(graph, 'v0'), [last], reason: graph);
    return graph;
  }

  test('cards outside every fade are written as they always were', () {
    final g = write(const VerseMotion(thread: true));
    expect(
        g,
        contains("[v0][3:v]overlay=(W-w)/2:'(H-h)*0.500':"
            "enable='gte(t,0.500)*lt(t,2.000)'"));
    expect(g, isNot(contains('fade=t=in')));
  });

  test('a fade splits the card into its fades and its rest', () {
    final g = write(const VerseMotion(arrival: VerseArrival.fade));
    // The first card arrives, the last leaves.
    expect(g, contains('[3:v]format=rgba,split=2'));
    expect(g, contains('[4:v]format=rgba,split=2'));
    expect(g, contains('fade=t=in:st=0:d=0.320:alpha=1'));
    // Out at the unit's own end: 3000 ms long, 260 off.
    expect(g, contains('fade=t=out:st=2.740:d=0.260:alpha=1'));
    // Timed in the unit's clock, then moved onto the pass's.
    expect(g, contains('setpts=PTS+0.500/TB'));
    // The still middle is a plain overlay.
    expect(g, contains("enable='gte(t,0.820)*lt(t,2.000)'"));
  });

  test('a rise moves the card on its way in', () {
    final g = write(const VerseMotion(arrival: VerseArrival.rise));
    expect(g, contains("'(H-h)*0.500+(if(lt((t-0.500),0.460),36.0*pow("));
  });

  test('a unit begun in the pass before keeps its own clock', () {
    final g = write(
      const VerseMotion(arrival: VerseArrival.rise, thread: true),
      passStart: 3300,
      passEnd: 9000,
      cards: const [
        MotionCard(
            input: 4,
            startMs: 3300,
            endMs: 3500,
            unitStartMs: 500,
            unitEndMs: 3500),
      ],
    );
    // 2.8 s into its unit as the pass opens, and moved back onto it.
    expect(g, contains('setpts=(N/30+2.800)/TB'));
    expect(g, contains('setpts=PTS-2.800/TB'));
    expect(g, contains('(t+2.800)'));
  });

  test('the thread crops a sliding window out of its strip', () {
    final g = write(const VerseMotion(thread: true));
    // 800 wide: the window starts 160 into the empty half.
    expect(g, contains("crop=w=800:h=40:x='160+if("));
    expect(g, contains('[7:v]format=rgba,split=1[qt0]'));
    // Laid at the line's left edge, under the letters.
    expect(g, contains("overlay=x=140:y='912'"));
    // The spark rides it.
    expect(g, contains('[8:v]split=1[qk0]'));
  });

  test('the light is cut from the glint card at the recitation', () {
    final g = write(const VerseMotion(light: true), glint: 9);
    expect(g, contains('[9:v]format=rgba,split=2'));
    expect(g, contains('colorchannelmixer=aa=0.45'));
    expect(g, contains('crop=w=168:h=90:'));
    expect(g, contains('crop=w=64:h=90:'));
    // And fades out once the line is crossed.
    expect(g, contains('fade=t=out:st=2.600:d=0.220:alpha=1'));
  });

  test('uses() names what a pass needs', () {
    final u = VerseMotionGraph.uses(
      units: [
        MotionUnit(
            startMs: 500,
            endMs: 3500,
            cardTop: 800,
            cardH: 300,
            rows: rows,
            glintInput: 9),
      ],
      motion: const VerseMotion(thread: true, light: true),
      passStartMs: 0,
      passEndMs: 6000,
    );
    expect(u.thread, isTrue);
    expect(u.spark, isTrue);
    expect(u.glintUnits, {0});
    final none = VerseMotionGraph.uses(
      units: const [],
      motion: const VerseMotion(thread: true),
      passStartMs: 0,
      passEndMs: 6000,
    );
    expect(none.thread, isFalse);
  });
}
