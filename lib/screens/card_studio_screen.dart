import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../data/card_compose.dart';
import '../data/card_deck.dart';
import '../data/card_images.dart';
import '../data/card_library.dart';
import '../data/card_style.dart';
import '../data/debug_log.dart';
import '../data/gallery_saver.dart';
import '../data/instagram_share.dart';
import '../data/platform_share.dart';
import '../data/quran_repository.dart';
import '../data/rewards_service.dart';
import '../data/settings_service.dart';
import '../data/share_origin.dart';
import '../l10n/l10n.dart';
import '../render/card_exporter.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/card_canvas.dart';
import '../widgets/card_dock.dart';
import '../widgets/card_scene_sheet.dart';
import '../widgets/telegram_invite.dart';
import '../widgets/dedicate_sheet.dart';
import '../widgets/gallery_blocked_dialog.dart';
import '../widgets/scripture_finder.dart';
import '../widgets/share_to.dart';

/// The composer.
///
/// One card on screen, one rail of tools under it, and a filmstrip
/// between them when the deck holds more than one. Everything is
/// edited in place and every edit is undoable, so nothing here needs a
/// confirmation and nothing needs a preview — the card *is* the
/// preview, drawn by the same widget that will be rasterized.
///
/// ## What the gestures mean
///
/// Tap a block to take it; drag it to move it; pinch it to size it.
/// Drag anywhere else and the picture behind moves instead, which is
/// how a 9:16 photograph is framed into a square card. Nothing else is
/// a gesture: everything a card can be is in the rail, where it can be
/// found.
class CardStudioScreen extends StatefulWidget {
  final CardDeck deck;

  /// Opens the words editor as soon as the screen settles — what a
  /// blank card wants, and nothing else does.
  final bool writeImmediately;

  /// The deck was just made, and its scenery was drawn at random for
  /// it rather than chosen: the gold line under the card keeps
  /// offering the library until the user picks a ground of their own.
  final bool drawnScenery;

  const CardStudioScreen({
    super.key,
    required this.deck,
    this.writeImmediately = false,
    this.drawnScenery = false,
  });

  @override
  State<CardStudioScreen> createState() => _CardStudioScreenState();
}

class _CardStudioScreenState extends State<CardStudioScreen> {
  late CardDeck _deck = widget.deck;
  int _index = 0;
  String? _selectedId;
  CardTool? _tool;

  /// Whole decks, kept as they were before each change.
  ///
  /// A deck is an immutable tree of small immutable values, so an
  /// entry in here shares everything the change did not touch: an
  /// undo stack thirty deep costs a few hundred bytes, and undo is a
  /// list assignment. That is the whole reason the model is shaped the
  /// way it is.
  final List<CardDeck> _undo = [];
  final List<CardDeck> _redo = [];
  static const _undoDepth = 30;

  /// Backgrounds still arriving, so a rebuild does not start a second
  /// decode of the same file.
  final Set<String> _resolving = {};

  /// A scenery being downloaded right now, 0..1.
  double? _fetching;

  /// Whether the ground is one the user picked — a scenery from the
  /// library or a photo of their own — rather than one drawn for them.
  late bool _ownGround = !widget.drawnScenery;

  bool _exporting = false;

  /// Whether a continuous gesture is under way — a drag across the
  /// card, or a finger on a slider — and whether it has already put
  /// its entry on the undo stack.
  ///
  /// Without this, one slider drag is sixty changes a second and fills
  /// a thirty-deep stack in half of one, throwing away everything the
  /// user might actually want back. With it, a gesture is one step.
  bool _live = false;
  bool _livePushed = false;

  /// The gold lines shown while a block snaps to the middle or to a
  /// third of the card.
  double? _guideX;
  double? _guideY;

  /// What the block being dragged looked like when the drag started —
  /// a pinch reports its scale against the start of the gesture, not
  /// against the last frame.
  CardTextBlock? _dragFrom;
  CardBackground? _panFrom;

  CardSlide get _slide => _deck.slides[_index.clamp(0, _deck.slides.length - 1)];
  CardTextBlock? get _selected => _slide.block(_selectedId);

  @override
  void initState() {
    super.initState();
    _resolvePictures();
    if (widget.writeImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addText();
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ---- the deck ----------------------------------------------------

  /// Every change to the deck goes through here: one place that keeps
  /// the undo stack.
  ///
  /// Nothing is written to disk on the way. A card is kept when it is
  /// *made* — saved to the gallery or shared — and not before: the
  /// shelf in the Cards tab is what you have produced, not a pile of
  /// everything you have ever tapped at, and a library that fills
  /// itself with half-started drafts is a library nobody opens twice.
  void _change(CardDeck next, {bool undoable = true}) {
    final push = undoable && !(_live && _livePushed);
    if (_live) _livePushed = true;
    setState(() {
      if (push) {
        _undo.add(_deck);
        if (_undo.length > _undoDepth) _undo.removeAt(0);
        _redo.clear();
      }
      _deck = next.copyWith(updatedAt: DateTime.now());
      if (_index >= _deck.slides.length) _index = _deck.slides.length - 1;
    });
    _resolvePictures();
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _redo.add(_deck);
      _deck = _undo.removeLast();
      if (_index >= _deck.slides.length) _index = _deck.slides.length - 1;
    });
    _resolvePictures();
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _undo.add(_deck);
      _deck = _redo.removeLast();
      if (_index >= _deck.slides.length) _index = _deck.slides.length - 1;
    });
    _resolvePictures();
  }

  void _setSlide(CardSlide slide) => _change(_deck.withSlide(slide));

  void _setBlock(CardTextBlock block) =>
      _setSlide(_slide.withBlock(block));

  /// Leaving costs nothing and saves nothing: an unexported card is a
  /// card that was never made.
  void _close() => Navigator.of(context).pop();

  /// Keeps the deck, once it has actually been produced.
  ///
  /// Called from the export and nowhere else — this is what puts a
  /// card on the shelf. Deliberately free of this widget's state so it
  /// can outlive the screen: the deck is written *first* and the cover
  /// second, because drawing a cover is rasterization, which can fail
  /// on a device out of memory, and nothing about a picture of the
  /// card is worth the words on it.
  static Future<void> _keep(CardDeck deck) async {
    try {
      await CardLibrary.save(deck);
    } catch (e) {
      rlog('cards: save failed — $e');
      return;
    }
    try {
      final picture = await CardImages.resolve(deck.slides.first.background);
      final cover = await CardExporter.cover(
        deck: deck,
        slide: deck.slides.first,
        picture: picture,
      );
      // Drawing takes a while, and the deck may have been deleted from
      // the shelf meanwhile: saving it again would bring it back.
      final kept = await CardLibrary.load();
      if (!kept.any((d) => d.id == deck.id)) return;
      await CardLibrary.save(deck, cover: Uint8List.fromList(cover));
    } catch (e) {
      rlog('cards: cover failed — $e');
    }
  }

  // ---- pictures ----------------------------------------------------

  /// Decodes whatever the deck's slides stand on, one at a time, and
  /// redraws as each lands.
  ///
  /// The pictures themselves live in [CardImages], which keeps a few
  /// and lets the rest go — a decoded scenery is about 8 MB, and a
  /// composer that held one per card of a ten-card deck would be
  /// holding eighty. Nothing is cached here; this only asks, and asks
  /// for the card being worked on first.
  Future<void> _resolvePictures() async {
    final current = _slide;
    for (final slide in [current, ..._deck.slides]) {
      final bg = slide.background;
      if (!bg.hasPicture) continue;
      final key = CardImages.keyOf(bg);
      if (_resolving.contains(key) || CardImages.peek(bg) != null) continue;
      _resolving.add(key);
      final isCurrent = slide.id == current.id;
      if (isCurrent && mounted) setState(() => _fetching = 0);
      final image = await CardImages.resolve(
        bg,
        onProgress: isCurrent
            ? (p) {
                if (mounted) setState(() => _fetching = p);
              }
            : null,
      );
      _resolving.remove(key);
      if (!mounted) return;
      setState(() => _fetching = null);
      if (image == null && isCurrent) {
        // A drawn scenery that could not be fetched — no network, most
        // likely — is swapped for one that draws offline, quietly and
        // off the undo stack: the user never chose the first one, and
        // a new card should not open on the bare dark for want of it.
        if (!_ownGround && _undo.isEmpty && bg.sceneId.isNotEmpty) {
          final ready = CardCompose.randomReadyScene(not: bg.sceneId);
          if (ready.isNotEmpty) {
            rlog('cards: ${bg.sceneId} unavailable, drew $ready instead');
            _change(
              _deck.copyWith(slides: [
                for (final s in _deck.slides)
                  s.background.sceneId == bg.sceneId
                      ? s.copyWith(
                          background: s.background.copyWith(sceneId: ready))
                      : s,
              ]),
              undoable: false,
            );
            return;
          }
        }
        // Nothing to draw: the card stands on its paper, which is
        // what it was standing on anyway.
        rlog('cards: ${CardImages.keyOf(bg)} could not be decoded');
      }
    }
  }

  ui.Image? _pictureFor(CardSlide slide) =>
      CardImages.peek(slide.background);

  // ---- words -------------------------------------------------------

  /// A verse or a hadith, added to the card that is already open.
  ///
  /// The four ways into the Cards tab all make a *new* deck, which is
  /// the wrong shape for "this card needs the ayah under it as well":
  /// the words were already there to be found, and the only way to
  /// get them onto a card in progress was to find them somewhere else
  /// and type them out again. This is the same finder, opened from
  /// the words panel, and what comes back lands as blocks on this
  /// card — the quotation, and its translation under it when it has
  /// one.
  Future<void> _addScripture({required bool hadith}) async {
    final quotes = await showScriptureFinder(context, hadith: hadith);
    if (quotes == null || quotes.isEmpty || !mounted) return;
    final quote = quotes.first;
    final added = <CardTextBlock>[];
    var id = _addWords(quote.text, of: added);
    if (quote.translation.isNotEmpty) {
      id = _addWords(quote.translation, of: added, small: true);
    }
    if (added.isEmpty) return;
    _setSlide(_slide.copyWith(blocks: [..._slide.blocks, ...added]));
    setState(() {
      _selectedId = id;
      _tool = CardTool.words;
    });
  }

  /// One block of [text], sized and placed the way [_addText] places
  /// one, appended to [of]. Returns its id.
  ///
  /// [small] is the supporting line — a translation under a verse — and
  /// is set at a supporting line's size rather than sized to fill.
  String _addWords(String text, {
    required List<CardTextBlock> of,
    bool small = false,
  }) {
    final rtl = CardTextBlock.rtlText(text);
    final onPaper = _slide.background.isPaper;
    final taken = _slide.blocks.length + of.length;
    final block = CardTextBlock(
      id: newId(),
      text: text.trim(),
      face: CardFace.defaultFor(arabicScript: rtl),
      size: 0.06,
      colourArgb: onPaper ? _slide.background.groundInk : 0xFFFFFFFF,
      x: 0.5,
      // Each one lands under whatever is already on the card, and
      // under the one before it, so nothing arrives invisible.
      y: taken == 0 ? 0.46 : (taken == 1 ? 0.72 : 0.86),
      width: 0.8,
      skin: onPaper ? CardSkin.none : CardSkin.shadow,
      rtl: rtl,
    );
    final sized = block.copyWith(
      size: small
          ? 0.036
          : math.min(
              0.075,
              CardCompose.sizeToFill(block, _deck.format, share: 0.3),
            ),
    );
    of.add(sized);
    return sized.id;
  }

  Future<void> _addText() async {
    final text = await _askForWords(context, '');
    if (text == null || text.trim().isEmpty) return;
    final rtl = CardTextBlock.rtlText(text);
    final onPaper = _slide.background.isPaper;
    final block = CardTextBlock(
      id: newId(),
      text: text.trim(),
      face: CardFace.defaultFor(arabicScript: rtl),
      size: 0.06,
      colourArgb:
          onPaper ? _slide.background.groundInk : 0xFFFFFFFF,
      x: 0.5,
      // New words land under whatever is already on the card rather
      // than on top of it, so a second block is never invisible.
      y: _slide.blocks.isEmpty ? 0.46 : 0.72,
      width: 0.8,
      skin: onPaper ? CardSkin.none : CardSkin.shadow,
      rtl: rtl,
    );
    // Sized to fill a share of the card, the way a quotation is —
    // never larger than a third of it, since this one is arriving
    // beside whatever is already there.
    final sized = block.copyWith(
      size: math.min(
        0.075,
        CardCompose.sizeToFill(block, _deck.format, share: 0.3),
      ),
    );
    _setSlide(_slide.copyWith(blocks: [..._slide.blocks, sized]));
    setState(() {
      _selectedId = sized.id;
      _tool = CardTool.words;
    });
  }

  Future<void> _editText() async {
    final block = _selected;
    if (block == null) return;
    final text = await _askForWords(context, block.text);
    if (text == null) return;
    if (text.trim().isEmpty) {
      _removeText();
      return;
    }
    _setBlock(block.copyWith(
      text: text.trim(),
      // A block rewritten from English into Arabic is an Arabic block
      // now, and has to be set in a face that can shape it.
      rtl: CardTextBlock.rtlText(text),
      face: CardTextBlock.rtlText(text) == block.face.arabicScript
          ? block.face
          : CardFace.defaultFor(
              arabicScript: CardTextBlock.rtlText(text)),
    ));
  }

  void _removeText() {
    final block = _selected;
    if (block == null) return;
    HapticFeedback.selectionClick();
    _setSlide(_slide.withoutBlock(block.id));
    setState(() => _selectedId = null);
  }

  /// The words editor: one field, and Done.
  ///
  /// The controller belongs to the sheet rather than to this call, and
  /// that is not a style choice — a controller disposed when the
  /// future completes is disposed while the sheet is still animating
  /// out, and the field rebuilds against it on the way down.
  Future<String?> _askForWords(BuildContext context, String initial) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _WordsSheet(initial: initial),
    );
  }

  // ---- the cards ---------------------------------------------------

  void _addSlide() {
    if (_deck.isFull) {
      _say(L10n.of(context).cardDeckFull, ToastTone.info);
      return;
    }
    // A new card inherits the look of the one it was added from and
    // none of its words: the deck stays one deck, and the blank is
    // ready to be written on.
    final fresh = CardCompose.carry(_slide, CardSlide(id: newId()))
        .copyWith(background: _slide.background);
    _change(_deck.copyWith(slides: [..._deck.slides, fresh]));
    setState(() {
      _index = _deck.slides.length - 1;
      _selectedId = null;
    });
    _addText();
  }

  void _duplicateSlide() {
    if (_deck.isFull) {
      _say(L10n.of(context).cardDeckFull, ToastTone.info);
      return;
    }
    final copy = _slide.copyWith(
      blocks: [for (final b in _slide.blocks) b.copyWith()],
    );
    // Same everything, new identity — a duplicate that shared ids
    // would be edited in two places at once.
    final clone = CardSlide(
      id: newId(),
      background: copy.background,
      effects: copy.effects,
      frame: copy.frame,
      frameArgb: copy.frameArgb,
      blocks: [
        for (final b in copy.blocks)
          CardTextBlock(
            id: newId(),
            text: b.text,
            face: b.face,
            size: b.size,
            colourArgb: b.colourArgb,
            align: b.align,
            x: b.x,
            y: b.y,
            width: b.width,
            rotation: b.rotation,
            skin: b.skin,
            lineHeight: b.lineHeight,
            tracking: b.tracking,
            opacity: b.opacity,
            rtl: b.rtl,
          ),
      ],
      source: copy.source,
    );
    final slides = [..._deck.slides];
    slides.insert(_index + 1, clone);
    _change(_deck.copyWith(slides: slides));
    setState(() {
      _index = _index + 1;
      _selectedId = null;
    });
  }

  void _deleteSlide() {
    if (_deck.slides.length <= 1) return;
    HapticFeedback.selectionClick();
    final slides = [
      for (final s in _deck.slides)
        if (s.id != _slide.id) s
    ];
    _change(_deck.copyWith(slides: slides));
    setState(() {
      _index = _index.clamp(0, slides.length - 1);
      _selectedId = null;
    });
  }

  void _applyAll() {
    HapticFeedback.selectionClick();
    final source = _slide;
    _change(_deck.copyWith(slides: [
      for (final s in _deck.slides)
        s.id == source.id ? s : CardCompose.carry(source, s),
    ]));
    _say(L10n.of(context).cardAppliedAll, ToastTone.done);
  }

  /// Breaks a passage across a run of cards.
  ///
  /// What "turn this into a carousel" means for something somebody
  /// pasted in: the words are cut on sentence ends where they can be
  /// (see [CardCompose.paginate]), the first piece stays where it is,
  /// and the rest become cards that carry this one's look. Every other
  /// block on the card — a translation, a reference — is left on the
  /// first, since a reference repeated on ten cards is noise.
  void _split() {
    final block = _selected ?? _longestBlock();
    if (block == null) return;
    final pieces = CardCompose.paginate(
      block.text,
      max: CardDeck.maxSlides - _deck.slides.length + 1,
    );
    if (pieces.length < 2) return;
    HapticFeedback.selectionClick();
    final first = _slide.withBlock(block.copyWith(text: pieces.first));
    final rest = <CardSlide>[];
    for (final piece in pieces.skip(1)) {
      final fresh = CardCompose.carry(_slide, CardSlide(id: newId()))
          .copyWith(background: _slide.background, blocks: [
        CardTextBlock(
          id: newId(),
          text: piece,
          face: block.face,
          size: block.size,
          colourArgb: block.colourArgb,
          align: block.align,
          x: block.x,
          y: block.y,
          width: block.width,
          rotation: block.rotation,
          skin: block.skin,
          lineHeight: block.lineHeight,
          tracking: block.tracking,
          opacity: block.opacity,
          rtl: block.rtl,
        ),
      ]);
      // Each piece is a different length, so each card is set at the
      // size that piece wants rather than at the first one's.
      rest.add(fresh.copyWith(
        blocks: CardCompose.fit(fresh.blocks, _deck.format),
      ));
    }
    final slides = [..._deck.slides];
    final at = slides.indexWhere((s) => s.id == _slide.id);
    slides[at] = first.copyWith(
      blocks: CardCompose.fit(first.blocks, _deck.format),
    );
    slides.insertAll(at + 1, rest);
    _change(_deck.copyWith(slides: slides));
    setState(() => _selectedId = null);
  }

  /// The block a split would break up when nothing is selected: the
  /// one with the most words on it.
  CardTextBlock? _longestBlock() {
    CardTextBlock? best;
    for (final b in _slide.blocks) {
      if (best == null || b.text.length > best.text.length) best = b;
    }
    return best;
  }

  /// Whether there is anything worth breaking up: words long enough to
  /// make two cards, and room in the deck for the second.
  bool get _canSplit {
    if (_deck.isFull) return false;
    final block = _selected ?? _longestBlock();
    if (block == null) return false;
    return CardCompose.paginate(block.text).length > 1;
  }

  /// Who the deck is for. One dedication for the whole deck — a
  /// carousel is one gift — drawn on every card of it above the mark.
  Future<void> _dedicate() async {
    final picked = await showDedicateSheet(context,
        dedication: _deck.dedication);
    if (picked == null || picked == _deck.dedication || !mounted) return;
    _change(_deck.copyWith(dedication: picked));
  }

  /// The dedication as a sentence, in the language the app is in.
  String get _dedicationLine => _deck.dedication.isEmpty
      ? ''
      : L10n.of(context)
          .dedicationLine(_deck.dedication.kind, _deck.dedication.name);

  void _setFormat(CardFormat format) {
    if (format == _deck.format) return;
    HapticFeedback.selectionClick();
    final from = _deck.format;
    _change(_deck.copyWith(
      format: format,
      slides: [
        for (final s in _deck.slides) CardCompose.reshape(s, from, format),
      ],
    ));
  }

  // ---- the ground --------------------------------------------------

  Future<void> _pickScene() async {
    final id = await showCardSceneSheet(context,
        selectedId: _slide.background.sceneId.isEmpty
            ? null
            : _slide.background.sceneId);
    if (id == null || !mounted) return;
    _ownGround = true;
    _setSlide(_slide.copyWith(
      background: _slide.background.copyWith(sceneId: id, filePath: ''),
    ));
  }

  Future<void> _pickPhoto() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      _ownGround = true;
      _setSlide(_slide.copyWith(
        background:
            _slide.background.copyWith(filePath: picked.path, sceneId: ''),
      ));
    } catch (e) {
      rlog('cards: photo pick failed — $e');
      if (mounted) _say(L10n.of(context).galleryBlockedTitle);
    }
  }

  // ---- export ------------------------------------------------------

  /// The apps Share to offers for a card. YouTube takes videos only, so
  /// it is not among them; Instagram's two doors follow the reel's
  /// setting for them, and WhatsApp's hand-off is Android's alone.
  List<ShareTarget> get _shareTargets {
    final s = SettingsService.state.value;
    final ig = InstagramShare.supported && s.instagramDirectShare;
    return [
      if (ig) ...[ShareTarget.instagramPost, ShareTarget.instagramStory],
      ShareTarget.tiktok,
      ShareTarget.facebook,
      if (defaultTargetPlatform == TargetPlatform.android &&
          s.whatsappDirectShare)
        ShareTarget.whatsapp,
    ];
  }

  /// The surah a verse card quotes, for its caption's tag.
  String? get _surahName {
    final src = _deck.source;
    if (!src.isVerse || src.surah < 1 || src.surah > 114) return null;
    return QuranRepository.surahInfo(src.surah).nameEnglish;
  }

  /// Straight into one app, from Share to: the card handed over, and the
  /// caption with that app's hashtags on the clipboard, the mark among
  /// them.
  ///
  /// Instagram's story is the story door it always was: one picture,
  /// re-cut to 9:16 by [CardExporter.prepare] — every position on a
  /// card is a fraction, so it costs nothing — with the mark climbing
  /// into the strip that opens up, clear of Instagram's own bottom bar.
  /// Every other app gets the card, the whole carousel where there is
  /// one, in its own composer on Android; on iOS the cards go to the
  /// gallery and the app opens with them first in its picker. Anything
  /// that stops the hand-off ends in the share sheet rather than in
  /// nothing.
  Future<void> _shareTo(ShareTarget target, Rect origin) async {
    if (_exporting) return;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    setState(() => _exporting = true);
    try {
      final story = target == ShareTarget.instagramStory;
      final files = await CardExporter.render(_deck, asStory: story);
      if (!mounted || files.isEmpty) return;
      final text = PlatformShare.caption(target,
          line: l.cardShareLine, surahName: _surahName);
      await PlatformShare.copy(text);
      final app = target.app(l);
      var handed = false;
      if (story) {
        handed = await InstagramShare.shareStory(files.first);
      } else if (ios) {
        var saved = 0;
        for (var i = 0; i < files.length; i++) {
          final r = await GallerySaver.saveImage(files[i],
              name: CardExporter.name(_deck, i));
          if (r.ok) saved++;
        }
        handed = saved > 0 && await PlatformShare.sendImages(target, files);
        if (handed && mounted) {
          messenger
            ..clearSnackBars()
            ..showSnackBar(toast(l.shareCardOpenHint(app),
                tone: ToastTone.done, duration: const Duration(seconds: 9)));
        }
      } else {
        handed = await PlatformShare.sendImages(target, files, text: text);
      }
      if (!handed) {
        if (mounted) {
          _say(story ? l.instagramUnavailable : l.shareAppMissing(app));
        }
        await SharePlus.instance.share(ShareParams(
          files: [
            for (final f in story ? [files.first] : files)
              XFile(f.path, mimeType: 'image/png'),
          ],
          text: story ? null : text,
          sharePositionOrigin: origin,
        ));
      } else if (mounted && !ios) {
        // iOS said where the card went; Instagram's story on iOS takes
        // the clipboard for the picture, so there is nothing to paste.
        messenger
          ..clearSnackBars()
          ..showSnackBar(toast(l.shareCaptionCopied, tone: ToastTone.done));
      }
      unawaited(_kept());
    } catch (e, s) {
      rlogError('card share to', e, s);
      if (mounted) _say(l.cardExportFailed);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// What a made card earns, and it is not points.
  ///
  /// The lever on a habit is how often, not how much: a card counts
  /// toward the same daily streak a reel does, so a day somebody only
  /// had a minute is still a day they made something. It does *not*
  /// count toward the reel badges — those count reels, and a badge
  /// that could be earned two ways is a badge that means neither.
  Future<void> _kept() async {
    await _keep(_deck);
    await _rememberLook(_deck);
    await RewardsService.recordCardMade();
    unawaited(TelegramInvite.after(TelegramMoment.card));
  }

  /// The look and the shape a made card leaves behind, so the next one
  /// opens on them.
  ///
  /// This is the whole of what `cardTemplate` and `cardFormat` are for
  /// now that the Cards tab no longer asks up front — and nothing had
  /// written either since the tab's row of specimens came off, which
  /// left every new card on the default look whatever the last one was
  /// made in. The choice is made here, on the card, where the result of
  /// it is on screen, and it is remembered at the one moment it is
  /// known to have been wanted: the card was exported.
  ///
  /// A deck on a mix that is no template leaves the previous look
  /// standing rather than resetting it to the default.
  static Future<void> _rememberLook(CardDeck deck) async {
    final template = CardTemplate.matching(deck.slides.first);
    final s = SettingsService.state.value;
    if (template?.name == s.cardTemplate && deck.format.name == s.cardFormat) {
      return;
    }
    await SettingsService.update(s.copyWith(
      cardTemplate: template?.name,
      cardFormat: deck.format.name,
    ));
  }

  Future<void> _export({required bool share, Rect? origin}) async {
    if (_exporting) return;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final files = await CardExporter.render(_deck);
      if (!mounted) return;
      if (share) {
        // A dedicated deck is handed to a person rather than posted to
        // a feed, so it goes with a message written to them — and that
        // message carries the store links, so the gift can be answered
        // with one.
        final d = _deck.dedication;
        await SharePlus.instance.share(ShareParams(
          files: [for (final f in files) XFile(f.path, mimeType: 'image/png')],
          text: d.isEmpty
              ? null
              : l.dedicationShareMessage(d.kind, d.name),
          sharePositionOrigin: origin ?? Rect.zero,
        ));
        // A dedicated card goes out with both store links on it, which
        // is what the invitation in Settings is: it earns the same
        // point, under the same once-a-day cap, so it cannot be
        // farmed by tapping share twice.
        if (d.isNotEmpty) unawaited(RewardsService.recordAppShared());
      } else {
        var saved = 0;
        GallerySaveResult? last;
        for (var i = 0; i < files.length; i++) {
          last = await GallerySaver.saveImage(files[i],
              name: CardExporter.name(_deck, i));
          if (last.ok) saved++;
        }
        if (!mounted) return;
        if (saved == 0 && last != null &&
            last.status == GallerySaveStatus.denied) {
          await showGalleryBlockedDialog(context);
        } else if (saved > 0) {
          messenger
            ..clearSnackBars()
            ..showSnackBar(toast(l.cardSavedToGallery(saved), tone: ToastTone.done));
        } else {
          _say(last != null && last.outOfSpace
              ? l.phoneStorageFull
              : l.cardExportFailed);
        }
      }
      // Made, and so kept: the shelf in the Cards tab holds what has
      // been saved or shared, and nothing else.
      unawaited(_kept());
    } catch (e, s) {
      rlogError('card export', e, s);
      if (mounted) _say(l.cardExportFailed);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _say(String message, [ToastTone tone = ToastTone.problem]) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(toast(message, tone: tone));
  }

  // ---- gestures ----------------------------------------------------

  /// Which block is under [point], topmost first. The rectangle is the
  /// block's own laid-out box, measured the way the canvas lays it
  /// out, so what you can see is what you can take.
  String? _blockAt(Offset point, double width) {
    final scale = width / CardFormat.exportWidth;
    final height = width / _deck.format.aspect;
    for (final block in _slide.blocks.reversed) {
      final w = block.width * width;
      final h = CardCompose.heightOf(block, _deck.format) * scale;
      final rect = Rect.fromCenter(
        center: Offset(block.x * width, block.y * height),
        width: w,
        // A short line is a thin target; nothing on a card is worth
        // missing by four pixels.
        height: math.max(h, 26),
      );
      if (rect.contains(point)) return block.id;
    }
    return null;
  }

  /// A tap takes whatever is under it; a tap on what is already taken
  /// opens its words.
  ///
  /// Tap-again rather than double-tap, and the difference is not
  /// stylistic: registering a double tap makes the framework hold
  /// *every* single tap for the 300ms it takes to find out whether a
  /// second one is coming, so selecting a block would answer a third
  /// of a second late for as long as anything was selected.
  void _tap(Offset point, double width) {
    final id = _blockAt(point, width);
    if (id != null && id == _selectedId) {
      _editText();
      return;
    }
    if (id == _selectedId) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedId = id);
  }

  void _dragStart(Offset point, double width) {
    _liveBegin();
    final id = _blockAt(point, width);
    setState(() {
      _selectedId = id;
      if (id != null) {
        _dragFrom = _slide.block(id);
        _panFrom = null;
      } else {
        // Taking hold of the picture lets go of the words: what is
        // under the finger is what is being moved, and a block that
        // stayed selected while the photograph moved under it would be
        // the next thing to move by mistake.
        _dragFrom = null;
        _panFrom = _slide.background;
      }
    });
  }

  /// Snap points: the middle of the card, and its thirds. Anything
  /// within [_snap] of one lands on it exactly, with a tick, because
  /// centring a line of type by eye on a phone is not possible and
  /// every card in the world is centred.
  static const _snap = 0.014;

  double _snapped(double v, List<double> targets, void Function(double?) show) {
    for (final t in targets) {
      if ((v - t).abs() < _snap) {
        show(t);
        return t;
      }
    }
    show(null);
    return v;
  }

  void _dragUpdate(ScaleUpdateDetails d, double width) {
    final height = width / _deck.format.aspect;
    final from = _dragFrom;
    if (from != null) {
      final live = _slide.block(from.id);
      if (live == null) return;
      var next = live;
      if (d.pointerCount > 1 && d.scale != 1) {
        next = next.copyWith(size: from.size * d.scale);
      }
      var x = next.x + d.focalPointDelta.dx / width;
      var y = next.y + d.focalPointDelta.dy / height;
      final wasX = _guideX, wasY = _guideY;
      x = _snapped(x, const [0.5], (g) => _guideX = g);
      y = _snapped(y, const [1 / 3, 0.5, 2 / 3], (g) => _guideY = g);
      if ((wasX == null) != (_guideX == null) ||
          (wasY == null) != (_guideY == null)) {
        HapticFeedback.selectionClick();
      }
      _setBlockLive(next.copyWith(x: x, y: y));
      return;
    }
    // Nothing selected: the photograph moves instead. Dragging the
    // picture down has to show more of its top, which is why the
    // delta is subtracted rather than added.
    final bg = _panFrom;
    if (bg == null || !_slide.background.hasPicture) return;
    _setBackgroundLive(_slide.background.copyWith(
      focusX: _slide.background.focusX - d.focalPointDelta.dx / width,
      focusY: _slide.background.focusY - d.focalPointDelta.dy / height,
    ));
  }

  void _setBlockLive(CardTextBlock block) =>
      _change(_deck.withSlide(_slide.withBlock(block)));

  void _setBackgroundLive(CardBackground bg) =>
      _change(_deck.withSlide(_slide.copyWith(background: bg)));

  /// A gesture begins: whatever it changes, it changes as one step.
  void _liveBegin() {
    _live = true;
    _livePushed = false;
  }

  void _liveEnd() => _live = false;

  void _dragEnd() {
    _liveEnd();
    setState(() {
      _dragFrom = null;
      _panFrom = null;
      _guideX = null;
      _guideY = null;
    });
  }

  // ---- the screen --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(l),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => _stage(box),
              ),
            ),
            if (!_slide.background.hasPicture || !_ownGround)
              _sceneryNote(l),
            if (_deck.slides.length > 1 || _tool == CardTool.deck)
              _filmstrip(l),
            CardDock(
              deck: _deck,
              slide: _slide,
              selected: _selected,
              tool: _tool,
              onTool: (t) => setState(() => _tool = t),
              onLive: (live) => live ? _liveBegin() : _liveEnd(),
              onSlide: _setSlide,
              onBlock: _setBlock,
              onAddText: _addText,
              onAddVerse: () => _addScripture(hadith: false),
              onAddHadith: () => _addScripture(hadith: true),
              onEditText: _editText,
              onRemoveText: _removeText,
              onFormat: _setFormat,
              onAddSlide: _addSlide,
              onDuplicateSlide: _duplicateSlide,
              onDeleteSlide: _deleteSlide,
              onApplyAll: _applyAll,
              onSplit: _canSplit ? _split : null,
              onDedicate: _dedicate,
              onPickScene: _pickScene,
              onPickPhoto: _pickPhoto,
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(L10n l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 0),
      child: Row(
        children: [
          // Back, not Done: closing keeps nothing, and a screen reader
          // saying "Done" promised the edits would stay.
          A11yTap(
            label: l.back,
            onTap: _close,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              color: AppColors.textPrimary,
              onPressed: _close,
              visualDensity: VisualDensity.compact,
            ),
          ),
          _Ghost(
            icon: Icons.undo_rounded,
            label: l.cardUndo,
            onTap: _undo.isEmpty ? null : _undoOnce,
          ),
          const SizedBox(width: 2),
          _Ghost(
            icon: Icons.redo_rounded,
            label: l.cardRedo,
            onTap: _redo.isEmpty ? null : _redoOnce,
          ),
          const Spacer(),
          if (_exporting)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.gold),
              ),
            ),
          _Ghost(
            icon: Icons.download_rounded,
            label: l.cardSaveToGallery,
            onTap: _exporting ? null : () => _export(share: false),
          ),
          // The two share buttons are bounded together, because
          // together is where the row runs out of room: four glyphs and
          // the bar's padding take about 178dp before either is drawn,
          // leaving 182 on a 360dp screen for a Share to pill that
          // wants about 90 and a gold button whose label is a
          // translated word. "Bagikan" and "Teilen" overrun that on
          // their own, and the spinner that appears while exporting
          // takes 28 more. Inside the bound both ellipsise instead of
          // painting past the edge —
          // which in release is a clipped Share button, not the debug
          // stripes. On a wide screen the bound exceeds what they ask
          // for and nothing changes.
          Flexible(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Builder(
                    builder: (button) => ShareToButton(
                      compact: true,
                      targets: _shareTargets,
                      note: l.shareToCardNote,
                      onPick: _exporting
                          ? null
                          : (t) => _shareTo(t, shareOriginOf(button)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Builder(
                    builder: (button) => A11yTap(
                      label: l.cardShare,
                      enabled: !_exporting,
                      onTap: _exporting
                          ? null
                          : () => _export(
                              share: true, origin: shareOriginOf(button)),
                      child: FilledButton.icon(
                        onPressed: _exporting
                            ? null
                            : () => _export(
                                share: true, origin: shareOriginOf(button)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: const Color(0xFF14100A),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 15),
                        // The button wraps its label in a Flexible
                        // already, so this ellipsises the moment the
                        // button is the one being squeezed.
                        label: Text(l.cardShare,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The card, as large as the room allows.
  Widget _stage(BoxConstraints box) {
    const margin = 18.0;
    final maxW = box.maxWidth - margin * 2;
    final maxH = box.maxHeight - margin * 2;
    // Never below zero: with the keyboard up the room can be smaller
    // than the margins, and a negative width throws in layout.
    final width = math.max(0.0, math.min(maxW, maxH * _deck.format.aspect));
    final l = L10n.of(context);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          A11yTap(
            label: l.a11yCardPreview,
            hint: l.a11ySelectsBlock,
            button: false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition, width),
              onScaleStart: (d) => _dragStart(d.localFocalPoint, width),
              onScaleUpdate: (d) => _dragUpdate(d, width),
              onScaleEnd: (_) => _dragEnd(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: CardCanvas(
                  slide: _slide,
                  format: _deck.format,
                  width: width,
                  picture: _pictureFor(_slide),
                  selectedId: _selectedId,
                  guideX: _guideX,
                  guideY: _guideY,
                  dedication: _dedicationLine,
                ),
              ),
            ),
          ),
          if (_fetching != null)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                value: _fetching == 0 ? null : _fetching,
                strokeWidth: 2.5,
                color: AppColors.goldBright,
                backgroundColor: Colors.black.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }

  /// One gold line under a card that is still standing on paper — or
  /// on a scenery drawn for it rather than chosen: "Pick your own
  /// scenery".
  ///
  /// The scenery library is the single thing a card is most changed
  /// by and the one nobody goes looking for — the glowing chip in the
  /// ground panel makes the same argument one level deeper in. Gold
  /// because it is an invitation rather than a warning, one line
  /// because a card that is fine on paper should not be nagged about,
  /// and it takes the tap itself so the advice and the door are the
  /// same thing.
  Widget _sceneryNote(L10n l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: A11yTap(
        label: l.cardSceneryNote,
        onTap: _pickScene,
        child: GestureDetector(
          onTap: _pickScene,
          behavior: HitTestBehavior.opaque,
          // An 11px glyph and an 11.5px line come to about 16dp, and
          // this is a door, not a caption. The height is inside the
          // opaque detector so the whole of it takes the tap, and it
          // costs the screen nothing: the stage above is Expanded, so
          // the card gives up the difference.
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 11, color: AppColors.gold),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l.cardSceneryNote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      letterSpacing: 0.2,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The deck, small, in order. The card you are on is lit; a tap
  /// moves to another.
  Widget _filmstrip(L10n l) {
    const height = 62.0;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _deck.slides.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final slide = _deck.slides[i];
          final on = i == _index;
          final w = (height - 14) * _deck.format.aspect;
          return Center(
            child: A11yTap(
              label: l.cardNumberOf(i + 1, _deck.slides.length),
              selected: on,
              onTap: () => setState(() {
                _index = i;
                _selectedId = null;
              }),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _index = i;
                    _selectedId = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: on ? AppColors.goldBright : AppColors.stroke,
                      width: on ? 1.6 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: IgnorePointer(
                      child: CardCanvas(
                        slide: slide,
                        format: _deck.format,
                        width: w,
                        picture: _pictureFor(slide),
                        dedication: _dedicationLine,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A quiet square button in the top bar.
class _Ghost extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _Ghost({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return A11yTap(
      label: label,
      enabled: on,
      onTap: onTap,
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: on ? AppColors.textPrimary : AppColors.stroke,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// The words of one block, being written.
class _WordsSheet extends StatefulWidget {
  final String initial;
  const _WordsSheet({required this.initial});

  @override
  State<_WordsSheet> createState() => _WordsSheetState();
}

class _WordsSheetState extends State<_WordsSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      // The keyboard: the field rides above it rather than under it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 6,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, height: 1.5),
                decoration: InputDecoration(
                  hintText: l.cardWriteHint,
                  filled: true,
                  fillColor: AppColors.bg.withValues(alpha: 0.6),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.stroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.gold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_controller.text),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: const Color(0xFF14100A),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(l.doneLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
