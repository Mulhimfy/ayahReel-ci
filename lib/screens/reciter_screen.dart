import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../data/audio_picker.dart';
import '../data/audio_position.dart';
import '../data/debug_log.dart';
import '../data/fatiha_data.dart';
import '../data/listen/listen_model.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/recitation_service.dart';
import '../data/reciter_search.dart';
import '../data/user_audio_service.dart';
import '../data/word_align_service.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/glow_button.dart';
import '../widgets/step_dots.dart';
import 'listen_screen.dart';
import 'verses_screen.dart';

/// Step 1 of the wizard, pushed from Home. One decision: whose voice.
/// Tapping a card selects it AND starts a short audio preview, so the
/// user hears the choice instead of reading about it.
///
/// The first card is not a voice at all but a way past the list: a
/// recording the user already has, which the app then has to learn the
/// shape of rather than assemble. See [UserAudioService].
class ReciterScreen extends StatefulWidget {
  /// Where Continue goes. By default it pushes the verse picker; the
  /// verse of the day hands in its own next step instead, because its
  /// verses are already chosen.
  final void Function(BuildContext context, Reciter reciter)? onContinue;

  /// A voice to open with already selected, so making the reel is
  /// Continue, not a choice.
  final String? initialReciterId;

  /// The surah already chosen, when there is one — the verse of the
  /// day. A voice that never recorded it is shown but can't be picked.
  final int? surah;

  const ReciterScreen(
      {super.key, this.onContinue, this.initialReciterId, this.surah});

  @override
  State<ReciterScreen> createState() => _ReciterScreenState();
}

/// The two places a recording can be, each behind its own picker.
enum _Door { audio, video }

class _ReciterScreenState extends State<ReciterScreen>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();

  /// Moved on by every pick and by every way off this screen. A sample
  /// that has to be fetched is slower than a tap: one whose fetch ends
  /// after either is not played. It used to start on the screen after
  /// Continue, over whatever was there (the owner, 2026-10-26: a test
  /// Al-Fatiha verse overlapping once a voice was picked).
  int _sampleTurn = 0;
  Reciter? _selected;

  /// The upload in play, if there is one — from this session, or
  /// remembered from a previous one.
  UserAudio? _upload;

  /// True while a picked file is being converted and measured.
  bool _importing = false;

  /// Past this many voices the list is no longer read top to bottom
  /// but looked up, so it gets a search field.
  static const _searchFrom = 40;

  final _search = TextEditingController();
  String _query = '';

  /// The list, and the card of the voice chosen when the screen opened,
  /// so a voice kept from the last reel is on screen rather than forty
  /// cards down with Continue lit for no visible reason.
  final _list = ScrollController();
  final _chosenKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No audio focus: Android's async focus grant can get lost, which
    // leaves a "playing" but silent player (same bug as the preview
    // screen). Focus 'none' starts playback synchronously.
    _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        audioFocus: AndroidAudioFocus.none,
      ),
    ));
    // Nothing on this screen shows where a sample has got to, so the
    // player never has to be asked — and by default it would be asked
    // once a frame. See [PositionPolling].
    _player.stopPollingPosition();
    final wanted = widget.initialReciterId;
    if (wanted != null) {
      for (final r in reciters) {
        if (r.id == wanted && _has(r)) {
          _selected = r;
          creationState.selectReciter(r);
          break;
        }
      }
    } else {
      // The voice the last reel was made with — this session's, or
      // the last launch's (see LastChoices) — is where a new reel
      // starts. Continue is one tap away; any other voice is one tap.
      // A voice's other recording is kept too: it is the same card,
      // with that recording's chip lit.
      final last = creationState.reciter;
      if (last != null && !last.isUserAudio && _has(last)) {
        for (final r in reciters) {
          if (r.id == last.id) {
            _selected = r;
            WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
            break;
          }
        }
      }
    }
    _restoreUpload();
  }

  /// Scrolls the chosen voice's card into view. The list is built
  /// lazily, so a card far down does not exist until it is near: each
  /// frame jumps to where the cards laid out so far say it is, until it
  /// has been built, and the card itself is then brought to a third of
  /// the way down.
  void _reveal([int tries = 0]) {
    if (!mounted || !_list.hasClients) return;
    final card = _chosenKey.currentContext;
    if (card != null) {
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      Scrollable.ensureVisible(
        card,
        alignment: 0.35,
        duration: still ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final chosen = _selected;
    final i = chosen == null
        ? -1
        : voices.indexWhere((v) => v.id == voiceOf(chosen).id);
    if (i < 0 || tries >= 8) return;
    final pos = _list.position;
    // The upload card leads the list; the extent the list estimates for
    // all of it comes from the cards it has measured.
    final count = voices.length + 1;
    final each = (pos.maxScrollExtent + pos.viewportDimension) / count;
    final guess = (i + 1) * each - pos.viewportDimension * 0.35;
    _list.jumpTo(guess.clamp(0.0, pos.maxScrollExtent));
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _reveal(tries + 1))
      ..scheduleFrame();
  }

  /// Whether [r] has the surah this screen was opened for, if any.
  bool _has(Reciter r) {
    final s = widget.surah;
    return s == null || r.hasSurah(s);
  }

  Future<void> _restoreUpload() async {
    final a = await UserAudioService.restore();
    if (!mounted || a == null) return;
    setState(() {
      _upload = a;
      // The last reel was made on this very upload: it is the choice
      // the screen opens on, as a voice would be.
      final last = creationState.reciter;
      if (_selected == null &&
          widget.initialReciterId == null &&
          last != null &&
          last.isUserAudio &&
          UserAudioService.reciterFor(a).id == last.id) {
        _selected = last;
      }
    });
  }

  /// The sample stops when the app does. With audio focus off (see
  /// initState) nothing else would stop it: a full Al-Fatiha sample kept
  /// playing from the home screen of the phone, over whatever the user
  /// switched to, until it ran out.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player.stop().catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  Future<void> _pick(Reciter r) async {
    HapticFeedback.selectionClick();
    // The keyboard is put away so Continue is in view the moment a
    // voice is found.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selected = r);
    creationState.selectReciter(r);
    final turn = ++_sampleTurn;
    // A stop that fails (a player in a bad state) must not cost the
    // preview, or below, the picker itself.
    await _player.stop().catchError((_) {});
    // Preview from Al-Fatiha ayah 2 (voice, not silence/basmala pause):
    // seek into the bundled recording when there is one, else fetch
    // that single ayah (or cut it from its surah) and play it off the
    // disk. Never a UrlSource — see [RecitationService.sampleAyah] for
    // the ANR that streaming one cost.
    try {
      if (r.hasBundledFatiha) {
        final asset = r.audioAsset!.replaceFirst('assets/', '');
        await _player.play(AssetSource(asset),
            position: Duration(milliseconds: r.timings![1].startMs));
      } else {
        final f = await RecitationService.sampleAyah(r, 1, 2);
        // The fetch is slower than a tap. If another voice was picked
        // while it ran, or the screen was left or covered, this sample
        // is no longer one to play.
        if (!mounted ||
            turn != _sampleTurn ||
            _selected?.id != r.id ||
            !(ModalRoute.of(context)?.isCurrent ?? false)) {
          return;
        }
        await _player.play(DeviceFileSource(f.path));
      }
    } catch (_) {
      // The preview is a nicety; the selection itself already stuck.
    }
  }

  /// Selects the upload and plays it from the top — the same "hear what
  /// you picked" the voices get.
  Future<void> _pickUpload(UserAudio a) async {
    HapticFeedback.selectionClick();
    final r = UserAudioService.reciterFor(a);
    setState(() => _selected = r);
    creationState.selectReciter(r);
    _sampleTurn++;
    await _player.stop().catchError((_) {});
    try {
      await _player.play(DeviceFileSource(a.audioPath));
    } catch (_) {
      // As above: the selection is what matters.
    }
  }

  /// What the "audio file" door shows on iOS: `public.audio` is the
  /// parent of every audio type Files knows; `public.mpeg-4` is the
  /// `.mp4` container an audio-only export often arrives in.
  static const _audioTypes = XTypeGroup(
    label: 'audio',
    uniformTypeIdentifiers: ['public.audio', 'public.mpeg-4'],
  );

  /// The "audio file" door.
  ///
  /// A document picker on both platforms — UIDocumentPicker on iOS,
  /// ACTION_OPEN_DOCUMENT on Android — and never a media-library one.
  /// A recitation someone was sent lives in Files or iCloud Drive,
  /// which no music-library picker can reach, and what that picker
  /// hands back can be a DRM'd Apple Music track no encoder may touch.
  ///
  /// Android goes through the app's own channel rather than
  /// file_selector; see [AudioPicker]. Whatever arrives is probed by
  /// ffprobe before it is trusted.
  static Future<PickedAudio?> _pickAudio() async {
    if (Platform.isAndroid) return AudioPicker.pick();
    final f = await openFile(acceptedTypeGroups: const [_audioTypes]);
    return f == null ? null : (path: f.path, name: f.name);
  }

  /// The "video" door: the gallery, where a recording the user made
  /// actually is. A document browser cannot list it.
  static Future<PickedAudio?> _pickVideo() async {
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    return f == null ? null : (path: f.path, name: f.name);
  }

  /// Asks where the recording is, then brings it in.
  ///
  /// Two doors rather than one, because the OS puts two different
  /// pickers behind them: an audio file lives in Files and never
  /// appears in the gallery, and a video the user recorded lives in
  /// the gallery and no document browser will list it. Asking which is
  /// being looked for costs one tap, and it is the tap that makes the
  /// file findable at all.
  Future<void> _chooseFile() async {
    _sampleTurn++;
    await _player.stop().catchError((_) {});
    if (!mounted) return;
    final l = L10n.of(context);
    final type = await showModalBottomSheet<_Door>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              A11yHeader(
                child: Text(l.whereIsYourAudio,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 14),
              _SourceRow(
                icon: Icons.audiotrack_rounded,
                title: l.pickAudioFile,
                subtitle: l.pickAudioFileBody,
                onTap: () => Navigator.of(context).pop(_Door.audio),
              ),
              const SizedBox(height: 10),
              _SourceRow(
                icon: Icons.movie_creation_outlined,
                title: l.pickVideoFile,
                subtitle: l.pickVideoFileBody,
                onTap: () => Navigator.of(context).pop(_Door.video),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) return;

    // Busy from the moment the picker opens, not from when it answers:
    // both pickers copy the file before they answer, and a full surah
    // takes seconds to copy on a slow phone — seconds in which the card
    // would otherwise sit there as if the pick had come to nothing.
    setState(() => _importing = true);
    PickedAudio? picked;
    try {
      picked = type == _Door.audio ? await _pickAudio() : await _pickVideo();
      if (picked == null) {
        if (mounted) setState(() => _importing = false);
        return;
      }
      final audio = await UserAudioService.import(
        File(picked.path),
        name: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _upload = audio;
        _importing = false;
      });
      await _pickUpload(audio);
    } catch (e) {
      // A file that was picked and then failed is said so, never met
      // with a second picker: that is what this did once, and to the
      // user it looked like their choice had been thrown away.
      rlog('user audio: pick failed ($e)');
      if (!mounted) return;
      setState(() => _importing = false);
      final kind = e is UserAudioError ? e.kind : 'unreadable';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(toast(
          L10n.of(context).userAudioError(kind),
          tone: ToastTone.problem,
          duration: const Duration(seconds: 4),
        ));
    } finally {
      // The Android door's copy is spent once the import has converted
      // it; left alone it would sit in the cache at full size until the
      // next pick replaced it.
      final path = picked?.path;
      if (type == _Door.audio && Platform.isAndroid && path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
  }

  void _continue() {
    _sampleTurn++;
    _player.stop();
    final custom = widget.onContinue;
    final r = _selected;
    if (custom != null && r != null) {
      custom(context, r);
      return;
    }
    // An upload is heard first: AyahReel Listen finds its verses and
    // times its words (ListenScreen), with choosing them by hand still
    // one tap away. A build without the key goes straight to the verses.
    final upload = _upload;
    if (r != null && r.isUserAudio && upload != null && ListenHost.enabled) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ListenScreen(audio: upload)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VersesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final searching = _query.trim().isNotEmpty;
    // One card per voice; its other recordings are chips on the card.
    final shown = searching
        ? ReciterSearch.filter(voices, _query, styleOf: l.reciterStyle)
        : voices;
    // The upload is a way past the list, not a voice in it: while a
    // name is being looked for it steps aside.
    final head = searching ? 0 : 1;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          color: AppColors.textSecondary,
          onPressed: () {
            _sampleTurn++;
            _player.stop();
            Navigator.of(context).pop();
          },
        ),
        title: StepDots(current: WizardSteps.voice, total: WizardSteps.total),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text('بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
                    style: AppTheme.quran(size: 18, color: AppColors.gold)),
              ),
              const SizedBox(height: 10),
              A11yHeader(child: Text(l.chooseTheVoice, style: t.headlineMedium)),
              const SizedBox(height: 6),
              Text(l.tapToListen, style: t.bodyMedium),
              const SizedBox(height: 18),
              if (voices.length > _searchFrom) ...[
                _SearchField(
                  controller: _search,
                  hint: l.searchReciters(voices.length),
                  clearLabel: l.clear,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                // The upload sits at the head of the same list rather
                // than in a band of its own: it is one more way to
                // answer the screen's one question, and a permanent
                // strip above the voices would read as a second one.
                child: searching && shown.isEmpty
                    ? Align(
                        alignment: const Alignment(0, -0.6),
                        child: Text(l.noReciterMatch, style: t.bodyMedium),
                      )
                    : ListView.separated(
                      controller: _list,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: shown.length + head,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) {
                        if (i < head) {
                          return _UploadCard(
                            upload: _upload,
                            busy: _importing,
                            selected: _selected?.isUserAudio ?? false,
                            onUse: _upload == null
                                ? _chooseFile
                                : () => _pickUpload(_upload!),
                            onChooseFile: _chooseFile,
                          );
                        }
                        final v = shown[i - head];
                        final s = widget.surah;
                        final takes = recordingsOf(v);
                        final sel = _selected;
                        final chosen = sel != null &&
                                !sel.isUserAudio &&
                                voiceOf(sel).id == v.id
                            ? sel
                            : null;
                        final mine = chosen != null;
                        // The voice can be picked when any recording of
                        // it has the surah; the card opens on the first
                        // that does.
                        final usable = [
                          for (final r in takes)
                            if (_has(r)) r,
                        ];
                        return _ReciterCard(
                          key: mine ? _chosenKey : null,
                          reciter: v,
                          recordings: takes,
                          chosen: chosen,
                          usable: {for (final r in usable) r.id},
                          selected: mine,
                          onTap: () {
                            if (usable.isEmpty) return;
                            _pick(chosen ?? usable.first);
                          },
                          onRecording: _pick,
                          lacking: usable.isNotEmpty || s == null
                              ? null
                              : l.noRecordingOf(l.surahTitle(
                                  QuranRepository.surahInfo(s))),
                        );
                      },
                    ),
              ),
              const SizedBox(height: 16),
              GlowButton(
                label: l.continueLabel,
                icon: Icons.arrow_forward_rounded,
                onPressed: _selected == null || _importing ? null : _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The field that finds a voice by name, in either script, or by style.
/// See [ReciterSearch] for how loosely a name may be spelled.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String clearLabel;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.hint,
    required this.clearLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        style: t.bodyMedium
            ?.copyWith(color: AppColors.textPrimary, fontSize: 15.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: t.bodyMedium,
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textSecondary),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: clearLabel,
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceRaised,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// The way past the list of voices: a recitation the user already has.
class _UploadCard extends StatelessWidget {
  final UserAudio? upload;
  final bool busy;
  final bool selected;
  final VoidCallback onUse;
  final VoidCallback onChooseFile;

  const _UploadCard({
    required this.upload,
    required this.busy,
    required this.selected,
    required this.onUse,
    required this.onChooseFile,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final a = upload;
    // The card is one button — its title, its line, and whether it
    // is the chosen voice — with "choose another file" as its own
    // control inside it once there is a file to replace.
    return Semantics(
      container: true,
      button: true,
      enabled: !busy,
      selected: selected,
      hint: a == null ? l.a11yChoosesFile : l.a11yPicksVoice,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.gold : AppColors.stroke,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.12),
              blurRadius: 20,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: busy ? null : onUse,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? AppColors.gold
                        : AppColors.gold.withValues(alpha: 0.12),
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.gold,
                          ),
                        )
                      : Icon(
                          selected
                              ? Icons.graphic_eq_rounded
                              : Icons.file_upload_outlined,
                          color: selected
                              ? const Color(0xFF14100A)
                              : AppColors.gold,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busy ? l.preparingYourAudio : l.useYourOwnAudio,
                        style: t.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        a == null || busy ? l.useYourOwnAudioBody : a.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium,
                      ),
                      if (a != null && !busy) ...[
                        const SizedBox(height: 6),
                        A11yTap(
                          hint: l.a11yChoosesFile,
                          child: GestureDetector(
                          onTap: onChooseFile,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                size: 12,
                                color: AppColors.gold.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l.chooseAnotherFile,
                                style: t.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: AppColors.gold.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// One row of the "where is it?" sheet.
class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      child: Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: t.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _ReciterCard extends StatelessWidget {
  /// The voice: its first recording, which names the card.
  final Reciter reciter;

  /// Every recording of the voice, the first first. One chip each when
  /// there is more than one.
  final List<Reciter> recordings;

  /// The recording picked, when this card is the chosen voice.
  final Reciter? chosen;

  /// The ids of the recordings that can be picked here: all of them,
  /// unless a surah is already chosen that some never recorded.
  final Set<String> usable;

  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Reciter> onRecording;

  /// Why this voice can't be picked for the surah already chosen, or
  /// null when it can.
  final String? lacking;

  const _ReciterCard(
      {super.key,
      required this.reciter,
      required this.recordings,
      required this.chosen,
      required this.usable,
      required this.selected,
      required this.onTap,
      required this.onRecording,
      this.lacking});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final playing = chosen ?? reciter;
    // One button per voice: the name, the style, the per-word note,
    // and whether it is the chosen one. The Arabic name beside an
    // English card is the same name again, so it is left to the eye.
    final off = lacking != null;
    return Semantics(
      container: true,
      button: true,
      enabled: !off,
      selected: selected,
      hint: off ? lacking : l.a11yPicksVoice,
      child: Opacity(
      opacity: off ? 0.4 : 1,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.gold : AppColors.stroke,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.12),
              blurRadius: 20,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: off ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? AppColors.gold
                            : AppColors.gold.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        selected
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                        color: selected
                            ? const Color(0xFF14100A)
                            : AppColors.gold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.reciterName(reciter), style: t.titleMedium),
                          const SizedBox(height: 3),
                          Text(lacking ?? l.reciterStyle(reciter),
                              style: t.bodyMedium),
                          // Only some recordings have released word
                          // timings, and it is the one thing a card can
                          // say about a voice that the preview cannot
                          // play. Kept to a whisper: a line this small is
                          // a detail on the name, not a second decision.
                          if (WordAlignService.supports(playing)) ...[
                            const SizedBox(height: 5),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 11,
                                  color: AppColors.gold.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    l.perWordHighlight,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.bodySmall?.copyWith(
                                      fontSize: 10.5,
                                      letterSpacing: 0.2,
                                      color: AppColors.gold.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // In Arabic the name IS the Arabic name; repeating it in
                    // the trailing slot would just echo the row.
                    if (!l.usesArabicNames)
                      ExcludeSemantics(
                        child: Text(
                          reciter.arabicName,
                          style: AppTheme.quran(
                            size: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                // The recordings across the card, under the name: in one
                // line, clear of the Arabic name at the row's end.
                if (recordings.length > 1 && !off)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        start: 62, top: 10),
                    child: _RecordingChips(
                      recordings: recordings,
                      chosen: selected ? chosen : null,
                      usable: usable,
                      onPick: onRecording,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}

/// A voice's recordings, one numbered chip each, under its name. The
/// lit chip is the recording the reel will use; the note beside the
/// chips says what sets it apart, or what any recording here is for.
class _RecordingChips extends StatelessWidget {
  final List<Reciter> recordings;
  final Reciter? chosen;
  final Set<String> usable;
  final ValueChanged<Reciter> onPick;

  const _RecordingChips({
    required this.recordings,
    required this.chosen,
    required this.usable,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final note = chosen == null ? null : l.recordingNote(chosen!);
    final small = t.bodySmall?.copyWith(
      fontSize: 10.5,
      letterSpacing: 0.2,
      color: AppColors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ExcludeSemantics(child: Text(l.recordingsLabel, style: small)),
            const SizedBox(width: 2),
            for (var i = 0; i < recordings.length; i++)
              _chip(context, i, recordings[i]),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          note ?? l.recordingsHint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: small?.copyWith(
            color: note == null
                ? AppColors.textSecondary.withValues(alpha: 0.75)
                : AppColors.gold.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, int i, Reciter r) {
    final l = L10n.of(context);
    final on = chosen?.id == r.id;
    final ok = usable.contains(r.id);
    return Semantics(
      button: true,
      selected: on,
      enabled: ok,
      label: l.a11yRecording(i + 1, recordings.length, l.recordingNote(r)),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ok ? () => onPick(r) : null,
        // A chip is small to the eye but not to the thumb: the padding
        // around it takes the tap too.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 30,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? AppColors.gold
                  : AppColors.gold.withValues(alpha: ok ? 0.10 : 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: on
                    ? AppColors.gold
                    : AppColors.gold.withValues(alpha: ok ? 0.35 : 0.12),
              ),
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: on
                    ? const Color(0xFF14100A)
                    : AppColors.gold.withValues(alpha: ok ? 0.9 : 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
