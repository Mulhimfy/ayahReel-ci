import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart' as os_settings;
import 'package:ayahreel_listen/ayahreel_listen.dart' show isWord;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debug_log.dart';
import '../data/listen/listen_live.dart';
import '../data/listen/listen_model.dart';
import '../data/listen/listen_service.dart';
import '../data/quran_repository.dart';
import '../data/user_audio_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/glow_button.dart';

/// Recite into the phone: AyahReel Listen follows the voice word by word as
/// it happens, and the recording becomes the upload the reel is made of.
/// Pops with the imported [UserAudio], or null.
class ReciteScreen extends StatefulWidget {
  const ReciteScreen({super.key});

  @override
  State<ReciteScreen> createState() => _ReciteScreenState();
}

enum _Phase { preparing, ask, downloading, ready, live, saving, noMic, nothing, failed }

class _ReciteScreenState extends State<ReciteScreen> {
  _Phase _phase = _Phase.preparing;
  double _share = 0;
  int _modelMb = 0;
  File? _model;
  ListenLive? _live;
  bool _offline = false;

  /// The verse being recited and the one before it, as display text.
  (int, int)? _shown;
  String _verse = '';
  String _before = '';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    final live = _live;
    _live = null;
    if (live != null) unawaited(live.dispose());
    super.dispose();
  }

  Future<void> _prepare() async {
    final local = await ListenModel.local();
    if (!mounted) return;
    if (local != null) {
      setState(() {
        _model = local;
        _phase = _Phase.ready;
      });
      return;
    }
    final m = await ListenModel.manifest();
    if (!mounted) return;
    setState(() {
      _offline = m == null;
      _modelMb = m == null ? 0 : (m.bytes / 1e6).round();
      _phase = m == null ? _Phase.failed : _Phase.ask;
    });
  }

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.downloading;
      _share = 0;
    });
    try {
      var last = 0;
      final f = await ListenModel.ensure(
        onProgress: (s) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (!mounted || (s < 1 && now - last < 150)) return;
          last = now;
          setState(() => _share = s);
        },
        keepGoing: () => mounted,
      );
      if (!mounted) return;
      setState(() {
        _model = f;
        _phase = _Phase.ready;
      });
    } catch (e) {
      rlog('recite: model ($e)');
      if (!mounted) return;
      setState(() {
        _offline = true;
        _phase = _Phase.failed;
      });
    }
  }

  Future<void> _start() async {
    final model = _model;
    if (model == null) return;
    final live = ListenLive();
    if (!await live.permitted()) {
      await live.dispose();
      if (mounted) setState(() => _phase = _Phase.noMic);
      return;
    }
    try {
      await live.start(model);
    } catch (e, st) {
      rlogError('recite: start', e, st);
      await live.dispose();
      if (mounted) setState(() => _phase = _Phase.failed);
      return;
    }
    if (!mounted) {
      unawaited(live.dispose());
      return;
    }
    HapticFeedback.mediumImpact();
    live.view.addListener(_onView);
    setState(() {
      _live = live;
      _phase = _Phase.live;
      _shown = null;
      _verse = '';
      _before = '';
    });
  }

  Future<void> _onView() async {
    final place = _live?.view.value.place;
    if (place == null || place == _shown) return;
    _shown = place;
    final (s, a) = place;
    final verse = await ListenService.verseText(s, a);
    final before = a > 1 ? await ListenService.verseText(s, a - 1) : '';
    if (!mounted || _shown != place) return;
    setState(() {
      _verse = verse;
      _before = before;
    });
  }

  Future<void> _stop() async {
    final live = _live;
    if (live == null) return;
    HapticFeedback.mediumImpact();
    live.view.removeListener(_onView);
    setState(() => _phase = _Phase.saving);
    final wav = await live.stop();
    _live = null;
    unawaited(live.dispose());
    if (wav == null) {
      if (mounted) setState(() => _phase = _Phase.nothing);
      return;
    }
    try {
      final stamp = DateTime.now();
      final name = 'Recitation ${stamp.year}-${stamp.month.toString().padLeft(2, '0')}-'
          '${stamp.day.toString().padLeft(2, '0')} ${stamp.hour.toString().padLeft(2, '0')}'
          '.${stamp.minute.toString().padLeft(2, '0')}';
      final audio = await UserAudioService.import(wav, name: name);
      try {
        wav.deleteSync();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(audio);
    } catch (e, st) {
      rlogError('recite: import', e, st);
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return PopScope(
      canPop: _phase != _Phase.live && _phase != _Phase.saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.live) _stop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(color: AppColors.textSecondary),
          title: Text(l.reciteNow),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: switch (_phase) {
              _Phase.preparing || _Phase.saving => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.gold),
                      ),
                      if (_phase == _Phase.saving) ...[
                        const SizedBox(height: 14),
                        Text(l.reciteSaving, style: t.bodyMedium),
                      ],
                    ],
                  ),
                ),
              _Phase.ask => _ask(t, l),
              _Phase.downloading => _downloading(t, l),
              _Phase.ready => _ready(t, l),
              _Phase.live => _liveView(t, l),
              _Phase.noMic => _message(t, l, l.reciteMic, settings: true),
              _Phase.nothing => _message(t, l, l.reciteNothing, retry: true),
              _Phase.failed => _message(
                  t, l, _offline ? l.listenOffline : l.listenFailed,
                  retry: true),
            },
          ),
        ),
      ),
    );
  }

  Widget _ask(TextTheme t, L10n l) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          A11yHeader(child: Text(l.reciteNow, style: t.headlineMedium)),
          const SizedBox(height: 12),
          Text(l.reciteNowBody, style: t.bodyMedium),
          const SizedBox(height: 8),
          Text(l.listenAskBody(_modelMb), style: t.bodySmall),
          const Spacer(),
          GlowButton(
            label: l.listenStart,
            icon: Icons.download_rounded,
            onPressed: _download,
          ),
        ],
      );

  Widget _downloading(TextTheme t, L10n l) {
    final mb = _modelMb > 0 ? _modelMb : 130;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.gold,
              value: _share.clamp(0.02, 1.0),
            ),
          ),
          const SizedBox(height: 18),
          A11yLive(
            child: Text(l.listenStageModel((_share * mb).round(), mb),
                style: t.titleMedium, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _ready(TextTheme t, L10n l) => Column(
        children: [
          const Spacer(),
          Text(l.reciteNowBody,
              style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 28),
          _MicButton(onTap: _start, active: false, level: 0),
          const SizedBox(height: 14),
          Text(l.reciteStart, style: t.bodyMedium),
          const Spacer(),
        ],
      );

  Widget _liveView(TextTheme t, L10n l) {
    final live = _live;
    if (live == null) return const SizedBox.shrink();
    return ValueListenableBuilder<LiveView>(
      valueListenable: live.view,
      builder: (context, v, _) {
        final place = v.place;
        final secs = v.elapsedMs ~/ 1000;
        final clock =
            '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fiber_manual_record_rounded,
                    color: Colors.redAccent, size: 14),
                const SizedBox(width: 6),
                Text(clock, style: t.titleMedium),
                const Spacer(),
                if (place != null)
                  Text(
                    '${QuranRepository.surahInfo(place.$1).nameEnglish} · '
                    '${l.listenVerses(place.$2, place.$2)}',
                    style: t.bodyMedium?.copyWith(color: AppColors.gold),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: place == null || _verse.isEmpty
                  ? Center(
                      child: A11yLive(
                        child: Text(l.reciteListening,
                            style: t.titleMedium,
                            textAlign: TextAlign.center),
                      ),
                    )
                  : SingleChildScrollView(
                      reverse: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_before.isNotEmpty)
                            _VerseText(
                              text: _before,
                              heard: v.heard[place.$2 - 1] ?? const {},
                              size: 18,
                              dim: true,
                            ),
                          const SizedBox(height: 12),
                          _VerseText(
                            text: _verse,
                            heard: v.heard[place.$2] ?? const {},
                            size: 27,
                            dim: false,
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Center(child: _MicButton(onTap: _stop, active: true, level: v.level)),
            const SizedBox(height: 8),
            Center(child: Text(l.reciteStop, style: t.bodyMedium)),
          ],
        );
      },
    );
  }

  Widget _message(TextTheme t, L10n l, String text,
      {bool retry = false, bool settings = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        A11yLive(child: Text(text, style: t.titleMedium)),
        const Spacer(),
        if (settings)
          GlowButton(
            label: l.reciteOpenSettings,
            icon: Icons.settings_rounded,
            onPressed: () async {
              try {
                await os_settings.AppSettings.openAppSettings(
                    type: os_settings.AppSettingsType.settings);
              } catch (_) {}
            },
          ),
        if (retry)
          GlowButton(
            label: l.listenTryAgain,
            icon: Icons.refresh_rounded,
            onPressed: () {
              setState(() => _phase = _Phase.preparing);
              _prepare();
            },
          ),
      ],
    );
  }
}

/// A verse as displayed, its words lit as they are heard.
class _VerseText extends StatelessWidget {
  final String text;
  final Set<int> heard;
  final double size;
  final bool dim;

  const _VerseText(
      {required this.text,
      required this.heard,
      required this.size,
      required this.dim});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var p = 0;
    for (final tok in text.split(' ')) {
      final word = isWord(tok);
      if (word) p++;
      final lit = word && heard.contains(p);
      spans.add(TextSpan(
        text: '$tok ',
        style: TextStyle(
          color: lit
              ? (dim ? AppColors.goldDeep : AppColors.goldBright)
              : (dim ? AppColors.textSecondary.withValues(alpha: 0.5) : AppColors.textSecondary),
        ),
      ));
    }
    return Text.rich(
      TextSpan(children: spans),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      style: TextStyle(fontFamily: 'HafsUthmani', fontSize: size, height: 1.9),
    );
  }
}

class _MicButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;
  final double level;

  const _MicButton(
      {required this.onTap, required this.active, required this.level});

  @override
  Widget build(BuildContext context) {
    final ring = 84 + 26 * level;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: active ? ring : 84,
                height: active ? ring : 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: active ? 0.18 : 0.1),
                ),
              ),
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold,
                ),
                child: Icon(
                  active ? Icons.stop_rounded : Icons.mic_rounded,
                  color: AppColors.bg,
                  size: 38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
