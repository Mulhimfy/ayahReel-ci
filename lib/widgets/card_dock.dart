import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/card_deck.dart';
import '../data/card_style.dart';
import '../data/dedication.dart';
import '../data/reel_effects.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart' show versePalette;
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'card_frames.dart';
import 'colour_picker.dart';
import 'ambient_pace.dart';

/// The seven things a card is made of. One tool, one panel, one row of
/// choices — nothing nested, nothing behind a second tap.
enum CardTool { words, type, ink, ground, look, frame, deck }

/// The composer's controls.
///
/// A card has a great many knobs and a phone has one screen, so the
/// arrangement matters more than the knobs do: a rail of seven glyphs
/// along the bottom, and above it exactly one short panel belonging to
/// whichever glyph is lit. The card itself never moves and is never
/// covered — it is the thing being worked on, and a control that hides
/// its own result is worse than no control.
///
/// Every panel edits in place: there is no apply, no confirm and no
/// dialog anywhere in here. That is what makes the undo in the top bar
/// the only safety anybody needs.
class CardDock extends StatelessWidget {
  final CardDeck deck;
  final CardSlide slide;
  final CardTextBlock? selected;
  final CardTool? tool;

  final ValueChanged<CardTool?> onTool;

  /// A finger has gone down on a slider, or come off one. What makes a
  /// slider drag one step on the undo stack rather than sixty a
  /// second; see the composer's `_liveBegin`.
  final ValueChanged<bool> onLive;
  final ValueChanged<CardSlide> onSlide;
  final ValueChanged<CardTextBlock> onBlock;

  final VoidCallback onAddText;

  /// Opens the scripture finder and puts what comes back on this card.
  /// Two entries rather than one, because "a verse" and "a hadith" are
  /// two different libraries and somebody knows which they want.
  final VoidCallback onAddVerse;
  final VoidCallback onAddHadith;
  final VoidCallback onEditText;
  final VoidCallback onRemoveText;
  final ValueChanged<CardFormat> onFormat;
  final VoidCallback onAddSlide;
  final VoidCallback onDuplicateSlide;
  final VoidCallback onDeleteSlide;
  final VoidCallback onApplyAll;

  /// Breaks the words on this card across several — null when there
  /// is nothing long enough to be worth breaking up.
  final VoidCallback? onSplit;

  /// Asks who the deck was made for.
  final VoidCallback onDedicate;

  final VoidCallback onPickScene;
  final VoidCallback onPickPhoto;

  const CardDock({
    super.key,
    required this.deck,
    required this.slide,
    required this.selected,
    required this.tool,
    required this.onTool,
    required this.onLive,
    required this.onSlide,
    required this.onBlock,
    required this.onAddText,
    required this.onAddVerse,
    required this.onAddHadith,
    required this.onEditText,
    required this.onRemoveText,
    required this.onFormat,
    required this.onAddSlide,
    required this.onDuplicateSlide,
    required this.onDeleteSlide,
    required this.onApplyAll,
    required this.onSplit,
    required this.onDedicate,
    required this.onPickScene,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The panel rises and falls with the tool; the rail under it
        // never moves, so the glyph you just tapped is still under
        // your thumb.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: tool == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                  child: _panel(context, tool!),
                ),
        ),
        _rail(context),
      ],
    );
  }

  Widget _rail(BuildContext context) {
    final l = L10n.of(context);
    final tools = <(CardTool, IconData, String)>[
      (CardTool.words, Icons.text_fields_rounded, l.cardText),
      (CardTool.type, Icons.font_download_outlined, l.cardType),
      (CardTool.ink, Icons.palette_outlined, l.cardInk),
      (CardTool.ground, Icons.image_outlined, l.cardGround),
      (CardTool.look, Icons.tune_rounded, l.cardLookTool),
      (CardTool.frame, Icons.filter_frames_outlined, l.cardFrameTool),
      (CardTool.deck, Icons.collections_outlined, l.cardShape),
    ];
    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          for (final (id, icon, label) in tools)
            _RailStop(
              icon: icon,
              label: label,
              selected: tool == id,
              onTap: () {
                HapticFeedback.selectionClick();
                onTool(tool == id ? null : id);
              },
            ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, CardTool tool) {
    return switch (tool) {
      CardTool.words => _words(context),
      CardTool.type => _type(context),
      CardTool.ink => _ink(context),
      CardTool.ground => _ground(context),
      CardTool.look => _look(context),
      CardTool.frame => _frame(context),
      CardTool.deck => _deck(context),
    };
  }

  // ---- words -------------------------------------------------------

  Widget _words(BuildContext context) {
    final l = L10n.of(context);
    final block = selected;
    return _Panel(children: [
      _Chips(children: [
        _Chip(label: l.cardAddText, icon: Icons.add_rounded, onTap: onAddText),
        _Chip(
            label: l.cardsFromVerse,
            icon: Icons.menu_book_outlined,
            onTap: onAddVerse),
        _Chip(
            label: l.cardsFromHadith,
            icon: Icons.format_quote_rounded,
            onTap: onAddHadith),
        if (block != null) ...[
          _Chip(
              label: l.cardEditText,
              icon: Icons.edit_outlined,
              onTap: onEditText),
          _Chip(
              label: l.cardRemoveText,
              icon: Icons.delete_outline_rounded,
              onTap: onRemoveText),
        ],
      ]),
      if (block != null) ...[
        _Row(children: [
          // Icon and name from where the text actually lands: start is
          // the right edge of an Arabic block, and "Align" three times
          // over told a screen reader nothing.
          for (final a in CardAlign.values)
            _IconChoice(
              icon: switch (a.resolve(rtl: block.rtl)) {
                TextAlign.left => Icons.format_align_left_rounded,
                TextAlign.right => Icons.format_align_right_rounded,
                _ => Icons.format_align_center_rounded,
              },
              label: switch (a.resolve(rtl: block.rtl)) {
                TextAlign.left => l.cardAlignLeft,
                TextAlign.right => l.cardAlignRight,
                _ => l.cardAlignCentre,
              },
              selected: block.align == a,
              onTap: () => onBlock(block.copyWith(align: a)),
            ),
          const SizedBox(width: 10),
          for (final s in CardSkin.values)
            _TextChoice(
              label: l.cardSkinName(s.name),
              selected: block.skin == s,
              onTap: () => onBlock(block.copyWith(skin: s)),
            ),
        ]),
        _Slider(
          onLive: onLive,
          label: l.cardSize,
          value: block.size,
          min: CardTextBlock.minSize,
          max: CardTextBlock.maxSize,
          onChanged: (v) => onBlock(block.copyWith(size: v)),
        ),
      ],
    ]);
  }

  // ---- type --------------------------------------------------------

  Widget _type(BuildContext context) {
    final l = L10n.of(context);
    final block = selected;
    if (block == null) return _Empty(label: l.cardAddText, onTap: onAddText);
    final faces = CardFace.forScript(arabicScript: block.rtl);
    return _Panel(children: [
      SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: faces.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => _FaceChip(
            face: faces[i],
            selected: faces[i] == block.face,
            onTap: () => onBlock(block.copyWith(face: faces[i])),
          ),
        ),
      ),
      _Slider(
        onLive: onLive,
        label: l.cardLineHeight,
        value: block.lineHeight,
        min: 0.8,
        max: 1.8,
        onChanged: (v) => onBlock(block.copyWith(lineHeight: v)),
      ),
      // Joined script is never tracked — the spacing pulls the joins
      // apart and the word stops being a word — so the control is
      // simply not offered for it.
      if (!block.rtl)
        _Slider(
          onLive: onLive,
          label: l.cardTracking,
          value: block.tracking,
          min: -0.02,
          max: 0.3,
          onChanged: (v) => onBlock(block.copyWith(tracking: v)),
        ),
      _Slider(
        onLive: onLive,
        label: l.cardTurn,
        value: block.rotation,
        min: -CardTextBlock.maxRotation,
        max: CardTextBlock.maxRotation,
        onChanged: (v) => onBlock(block.copyWith(rotation: v)),
      ),
    ]);
  }

  // ---- ink ---------------------------------------------------------

  Widget _ink(BuildContext context) {
    final l = L10n.of(context);
    final block = selected;
    if (block == null) return _Empty(label: l.cardAddText, onTap: onAddText);
    return _Panel(children: [
      _Swatches(
        selected: block.colourArgb,
        onPick: (argb) => onBlock(block.copyWith(colourArgb: argb)),
      ),
      _Slider(
        onLive: onLive,
        label: l.cardOpacity,
        value: block.opacity,
        min: 0.15,
        max: 1,
        onChanged: (v) => onBlock(block.copyWith(opacity: v)),
      ),
    ]);
  }

  // ---- ground ------------------------------------------------------

  Widget _ground(BuildContext context) {
    final l = L10n.of(context);
    final bg = slide.background;
    return _Panel(children: [
      _Chips(children: [
        // The one chip that glows, and the reason it does: the scenery
        // library is four hundred pictures deep and it is the thing a
        // card is most transformed by, but "Ground" is a panel nobody
        // opens twice. A pulse costs one repaint of one pill and is
        // the difference between a library people find and a library
        // they do not.
        _Chip(
            label: l.cardScenery,
            icon: Icons.photo_library_outlined,
            glow: !slide.background.hasPicture,
            onTap: onPickScene),
        _Chip(
            label: l.cardPhoto,
            icon: Icons.add_photo_alternate_outlined,
            onTap: onPickPhoto),
        if (bg.hasPicture)
          _Chip(
            label: l.cardPaper,
            icon: Icons.layers_clear_rounded,
            onTap: () => onSlide(
                slide.copyWith(background: bg.onPaper(bg.paper))),
          ),
      ]),
      SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // The papers, and last the circle that mixes any other ground.
          itemCount: CardPaper.values.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == CardPaper.values.length) {
              return Center(
                child: CustomColourCircle(
                  size: 28,
                  current: bg.paperArgb != 0 ? bg.paperArgb : bg.paper.topArgb,
                  chosen: !bg.hasPicture && bg.paperArgb != 0,
                  onPick: (argb) =>
                      onSlide(slide.copyWith(background: bg.onColour(argb))),
                ),
              );
            }
            final paper = CardPaper.values[i];
            return _PaperChip(
              paper: paper,
              label: l.cardPaperName(paper.name),
              selected:
                  bg.paper == paper && !bg.hasPicture && bg.paperArgb == 0,
              onTap: () => onSlide(
                  slide.copyWith(background: bg.onPaper(paper))),
            );
          },
        ),
      ),
      if (bg.hasPicture) ...[
        _Slider(
          onLive: onLive,
          label: l.cardDim,
          value: bg.dim,
          min: 0,
          max: 0.92,
          onChanged: (v) =>
              onSlide(slide.copyWith(background: bg.copyWith(dim: v))),
        ),
        _Slider(
          onLive: onLive,
          label: l.cardBlur,
          value: bg.blur,
          min: 0,
          max: 1,
          onChanged: (v) =>
              onSlide(slide.copyWith(background: bg.copyWith(blur: v))),
        ),
        _Slider(
          onLive: onLive,
          label: l.cardZoom,
          value: bg.zoom,
          min: 1,
          max: 2.5,
          onChanged: (v) =>
              onSlide(slide.copyWith(background: bg.copyWith(zoom: v))),
        ),
      ],
    ]);
  }

  // ---- look --------------------------------------------------------

  Widget _look(BuildContext context) {
    final l = L10n.of(context);
    final e = slide.effects;
    return _Panel(children: [
      _Row(children: [
        for (final look in ReelLook.values)
          _TextChoice(
            label: l.lookName(look.name),
            selected: e.look == look,
            onTap: () => onSlide(slide.copyWith(effects: e.copyWith(look: look))),
          ),
      ]),
      _Slider(
        onLive: onLive,
        label: l.effectWarmth,
        value: e.warmth,
        min: -1,
        max: 1,
        onChanged: (v) =>
            onSlide(slide.copyWith(effects: e.copyWith(warmth: v))),
      ),
      _Slider(
        onLive: onLive,
        label: l.effectVibrance,
        value: e.vibrance,
        min: -1,
        max: 1,
        onChanged: (v) =>
            onSlide(slide.copyWith(effects: e.copyWith(vibrance: v))),
      ),
      _Slider(
        onLive: onLive,
        label: l.effectVignette,
        value: e.vignette,
        min: 0,
        max: 1,
        onChanged: (v) =>
            onSlide(slide.copyWith(effects: e.copyWith(vignette: v))),
      ),
      _Slider(
        onLive: onLive,
        label: l.effectGrain,
        value: e.grain,
        min: 0,
        max: 1,
        onChanged: (v) =>
            onSlide(slide.copyWith(effects: e.copyWith(grain: v))),
      ),
    ]);
  }

  // ---- frame -------------------------------------------------------

  Widget _frame(BuildContext context) {
    final l = L10n.of(context);
    return _Panel(children: [
      _FrameStrip(
        selected: slide.frame,
        colour: Color(slide.frameArgb),
        nameOf: (f) => l.cardFrameName(f.name),
        onPick: (f) => onSlide(slide.copyWith(frame: f)),
      ),
      const SizedBox(height: 4),
      _Swatches(
        selected: slide.frameArgb,
        onPick: (argb) => onSlide(slide.copyWith(frameArgb: argb)),
      ),
    ]);
  }

  // ---- the deck ----------------------------------------------------

  Widget _deck(BuildContext context) {
    final l = L10n.of(context);
    return _Panel(children: [
      _Row(children: [
        for (final f in CardFormat.values)
          _TextChoice(
            label: l.cardFormatName(f.name),
            selected: deck.format == f,
            onTap: () => onFormat(f),
          ),
      ]),
      _Chips(children: [
        _Chip(
            label: l.cardAdd,
            icon: Icons.add_rounded,
            onTap: deck.isFull ? null : onAddSlide),
        _Chip(
            label: l.cardDuplicateSlide,
            icon: Icons.copy_rounded,
            onTap: deck.isFull ? null : onDuplicateSlide),
        if (deck.slides.length > 1)
          _Chip(
              label: l.cardDeleteSlide,
              icon: Icons.delete_outline_rounded,
              onTap: onDeleteSlide),
        if (deck.slides.length > 1)
          _Chip(
              label: l.cardApplyAll,
              icon: Icons.auto_fix_high_rounded,
              onTap: onApplyAll),
        if (onSplit != null)
          _Chip(
              label: l.cardSplit,
              icon: Icons.call_split_rounded,
              onTap: onSplit),
        // Whose it is. Shown as the dedication itself once there is
        // one, so the control says what the card says.
        _Chip(
          label: deck.dedication.isEmpty
              ? l.dedicateRow
              : l.dedicationLine(
                  deck.dedication.kind, deck.dedication.name),
          icon: deck.dedication.kind == DedicationKind.sadaqah &&
                  deck.dedication.isNotEmpty
              ? Icons.all_inclusive_rounded
              : Icons.card_giftcard_rounded,
          onTap: onDedicate,
        ),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------
// The pieces every panel is built from
// ---------------------------------------------------------------------

class _Panel extends StatelessWidget {
  final List<Widget> children;
  const _Panel({required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.stroke.withValues(alpha: 0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A row of choices that scrolls sideways when there are too many for
/// the width — which there always are on a small phone, and never are
/// on a large one.
class _Row extends StatelessWidget {
  final List<Widget> children;
  const _Row({required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }
}

/// The actions of a panel — add, duplicate, delete, apply.
///
/// A [Wrap] rather than a row that scrolls, unlike the pickers above
/// it: these are the few things a panel *does*, there are never more
/// than four, and an action hidden off the edge of a row is an action
/// nobody finds. A picker of eleven faces is a list and reads as one;
/// four buttons are not a list.
class _Chips extends StatelessWidget {
  final List<Widget> children;
  const _Chips({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: children,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// Draws the chip under a breathing gold light. For the one control
  /// in a panel that is worth finding before the others.
  final bool glow;

  const _Chip({
    required this.label,
    required this.icon,
    this.onTap,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    if (glow && on) return _Glow(child: _pill(context, on));
    return _pill(context, on);
  }

  Widget _pill(BuildContext context, bool on) {
    return A11yTap(
      label: label,
      enabled: on,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: ConstrainedBox(
          // A chip's label is usually two words, and once was always
          // two words — until one of them started carrying somebody's
          // dedication, which is a sentence with a name in it. A row
          // of chips that wraps cannot also widen: past this the label
          // ellipsises, and the reader still hears all of it.
          constraints: const BoxConstraints(maxWidth: 240),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: on ? 0.08 : 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: on ? 0.34 : 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 14,
                    color: on ? AppColors.goldBright : AppColors.stroke),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: on
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
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
}

/// A breathing gold light under a control.
///
/// Its own [RepaintBoundary], for the reason the share button has one:
/// the glow repaints every frame and nothing under it should.
class _Glow extends StatefulWidget {
  final Widget child;
  const _Glow({required this.child});

  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> with AmbientTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: ambient,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  bool _still = false;

  /// Reduce motion holds the light steady at half strength instead
  /// of breathing.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _pulse.value = 0.5; // setting the value stops the controller
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final eased = Curves.easeInOut.transform(_pulse.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.14 + 0.24 * eased),
                  blurRadius: 15,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// The frames as small cards, each wearing its frame in the colour the
/// card's frame is set to. A frame is a picture: "Girih" or "Glass" says
/// almost nothing until it is seen on a card, so every one is shown on
/// one, with its name under it.
class _FrameStrip extends StatelessWidget {
  final CardFrame selected;
  final Color colour;
  final String Function(CardFrame) nameOf;
  final ValueChanged<CardFrame> onPick;

  const _FrameStrip({
    required this.selected,
    required this.colour,
    required this.nameOf,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: CardFrame.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, i) {
          final f = CardFrame.values[i];
          final on = f == selected;
          final name = nameOf(f);
          return A11yTap(
            label: name,
            selected: on,
            onTap: () => onPick(f),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(f);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: 54,
                    height: 67.5,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: on ? AppColors.goldBright : AppColors.stroke,
                        width: on ? 1.6 : 1,
                      ),
                      boxShadow: [
                        if (on)
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _MiniCard(frame: f, colour: colour),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    name,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? AppColors.goldBright : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A card in miniature: the night, two lines where the words would be,
/// and the frame.
class _MiniCard extends CustomPainter {
  final CardFrame frame;
  final Color colour;
  const _MiniCard({required this.frame, required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF263049), Color(0xFF10141C)],
        ).createShader(rect),
    );
    final words = Paint()..color = Colors.white.withValues(alpha: 0.55);
    final w = size.width;
    final y = size.height * 0.46;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w / 2, y), width: w * 0.46, height: w * 0.045),
            Radius.circular(w * 0.03)),
        words);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w / 2, y + w * 0.1),
                width: w * 0.28,
                height: w * 0.03),
            Radius.circular(w * 0.02)),
        Paint()..color = AppColors.gold.withValues(alpha: 0.6));
    CardFramePainter(frame: frame, colour: colour).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_MiniCard old) =>
      old.frame != frame || old.colour != colour;
}

class _TextChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TextChoice(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.6)
                  : AppColors.stroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color:
                  selected ? AppColors.goldBright : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 36,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.6)
                  : AppColors.stroke,
            ),
          ),
          child: Icon(icon,
              size: 16,
              color:
                  selected ? AppColors.goldBright : AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// A type specimen, set in the face it offers. The only honest way to
/// show a face is to set something in it.
class _FaceChip extends StatelessWidget {
  final CardFace face;
  final bool selected;
  final VoidCallback onTap;

  const _FaceChip(
      {required this.face, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: face.label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.6)
                  : AppColors.stroke,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                face.specimen,
                maxLines: 1,
                overflow: TextOverflow.clip,
                textDirection: face.arabicScript
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                style: face.style(
                  size: face.arabicScript ? 17 : 15,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  lineHeight: 0.62,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                face.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  color: selected
                      ? AppColors.goldBright
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperChip extends StatelessWidget {
  final CardPaper paper;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PaperChip({
    required this.paper,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: paper.colours,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.goldBright : AppColors.stroke,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: Color(paper.inkArgb),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's one palette, offered here as it is offered for a verse:
/// light neutrals, dark neutrals, warm, cool. Every swatch is named
/// for a screen reader — see [L10n.colourName].
class _Swatches extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onPick;

  const _Swatches({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final mixed =
        !versePalette.any((c) => (c & 0xFFFFFF) == (selected & 0xFFFFFF));
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The palette, and last the circle that mixes any other colour.
        itemCount: versePalette.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == versePalette.length) {
            return Center(
              child: CustomColourCircle(
                current: selected,
                chosen: mixed,
                onPick: onPick,
              ),
            );
          }
          final argb = versePalette[i];
          final on = (argb & 0xFFFFFF) == (selected & 0xFFFFFF);
          return Center(
            child: A11yTap(
              label: l.a11yColourSwatch(argb),
              selected: on,
              onTap: () => onPick(argb),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPick(argb);
                },
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Color(argb),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: on ? AppColors.goldBright : AppColors.stroke,
                      width: on ? 2.5 : 1,
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

class _Slider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<bool> onLive;

  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onLive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 1.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
            ),
            child: Semantics(
              label: label,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                activeColor: AppColors.gold,
                inactiveColor: AppColors.surfaceRaised,
                semanticFormatterCallback: (v) =>
                    '${(((v - min) / (max - min)) * 100).round()}%',
                onChangeStart: (_) => onLive(true),
                onChangeEnd: (_) => onLive(false),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// What a panel shows when it has nothing to work on: the one button
/// that gives it something.
class _Empty extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _Empty({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Panel(children: [
      _Chips(children: [
        _Chip(label: label, icon: Icons.add_rounded, onTap: onTap),
      ]),
    ]);
  }
}

class _RailStop extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RailStop({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 34,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.gold.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon,
                    size: 17,
                    color: selected
                        ? AppColors.goldBright
                        : AppColors.textSecondary),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppColors.goldBright
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
