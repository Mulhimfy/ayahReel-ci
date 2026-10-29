import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../data/recitation_service.dart';
import '../data/user_audio_service.dart';
import '../l10n/l10n.dart';
import '../render/render_dir.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// Opens the storage manager as the app's standard bottom sheet.
Future<void> showStorageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    // Seven rows outgrow the default 9/16-of-the-screen cap on an
    // ordinary phone: let the sheet be as tall as it needs, and scroll
    // when even that is too tall.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const StorageSheet(),
  );
}

/// What's taking space, and one-tap cleanup for the rebuildable parts.
/// Saved reels are never bulk-deleted here — each one has its own
/// delete with confirmation in the grid.
class StorageSheet extends StatefulWidget {
  const StorageSheet({super.key});

  @override
  State<StorageSheet> createState() => _StorageSheetState();
}

class _StorageSheetState extends State<StorageSheet> {
  int? _reels;
  int? _cards;
  int? _cardStills;
  int? _recitations;
  int? _text;
  int? _renders;
  int? _scenes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final tmp = await getTemporaryDirectory();
    final reels = _dirSize(Directory('${docs.path}/reels'));
    // A deck is a recipe and a small cover, so the whole card library
    // is usually a few hundred kilobytes; the stills cut out of clips
    // are the part that can grow, and they are the part with a Clear
    // beside it.
    final cards = _dirSize(Directory('${docs.path}/cards'));
    final cardStills = _dirSize(Directory('${support.path}/card_stills'));
    final rec = _dirSize(Directory('${support.path}/recitations'));
    final text = _dirSize(Directory('${support.path}/quran_text'));
    final scenes = _dirSize(Directory('${support.path}/scenes'));
    var renders = 0;
    try {
      for (final f in tmp.listSync()) {
        if (f is File && f.uri.pathSegments.last.startsWith('ayah_')) {
          renders += f.lengthSync();
        }
      }
    } catch (_) {}
    // Android renders in a folder of its own (see [renderDir]); all of
    // it is the render's, and all of it can be made again.
    final work = await renderDir();
    if (work.path != tmp.path) renders += _dirSize(work);
    if (!mounted) return;
    setState(() {
      _reels = reels;
      _cards = cards;
      _cardStills = cardStills;
      _recitations = rec;
      _text = text;
      _renders = renders;
      _scenes = scenes;
    });
  }

  static int _dirSize(Directory d) {
    if (!d.existsSync()) return 0;
    var total = 0;
    try {
      for (final f in d.listSync(recursive: true)) {
        if (f is File) total += f.lengthSync();
      }
    } catch (_) {}
    return total;
  }

  static String _fmt(int? bytes) {
    if (bytes == null) return '…';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _clear(String subPath, {bool ofTemp = false}) async {
    final base = ofTemp
        ? await getTemporaryDirectory()
        : await getApplicationSupportDirectory();
    try {
      if (ofTemp) {
        // Only our own render/raster artifacts, never other temp files.
        for (final f in base.listSync()) {
          if (f is File && f.uri.pathSegments.last.startsWith('ayah_')) {
            f.deleteSync();
          }
        }
        final work = await renderDir();
        if (work.path != base.path) {
          for (final f in work.listSync()) {
            if (f is File) f.deleteSync();
          }
        }
      } else {
        final d = Directory('${base.path}/$subPath');
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    } catch (_) {}
    if (!ofTemp && subPath == 'recitations') {
      // Both hold recitations in memory by path, and those paths are
      // gone now.
      RecitationService.forgetAll();
      UserAudioService.forgetAll();
    }
    await _measure();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            A11yHeader(child: Text(l.storageTitle, style: t.titleMedium)),
            const SizedBox(height: 4),
            Text(
              l.storageBody,
              style: t.bodyMedium?.copyWith(fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            _row(t, l, l.savedReels, _fmt(_reels), null),
            _row(t, l, l.savedCards, _fmt(_cards), null),
            _row(t, l, l.cardStills, _fmt(_cardStills),
                _cardStills == 0 ? null : () => _clear('card_stills')),
            _row(t, l, l.downloadedScenery, _fmt(_scenes),
                _scenes == 0 ? null : () => _clear('scenes')),
            _row(t, l, l.downloadedRecitations, _fmt(_recitations),
                _recitations == 0 ? null : () => _clear('recitations')),
            _row(t, l, l.quranTextCache, _fmt(_text),
                _text == 0 ? null : () => _clear('quran_text')),
            _row(t, l, l.renderCache, _fmt(_renders),
                _renders == 0 ? null : () => _clear('', ofTemp: true)),
          ],
        ),
      ),
    );
  }

  Widget _row(TextTheme t, L10n l, String label, String size,
      VoidCallback? onClear) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // The name and its size are one line; the button after them
          // says which line it clears, since four bare "Clear"s in a
          // row would say nothing.
          Expanded(
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(child: Text(label, style: t.bodyMedium)),
                  Text(size,
                      style: t.bodyMedium?.copyWith(
                          color: AppColors.textPrimary, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
            child: onClear == null
                ? const SizedBox.shrink()
                : Semantics(
                    label: l.a11yClearItem(label),
                    button: true,
                    onTap: onClear,
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: onClear,
                      child: Text(l.clear,
                          style: t.bodySmall
                              ?.copyWith(color: AppColors.goldBright)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
