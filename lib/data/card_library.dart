import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:path_provider/path_provider.dart';

import 'card_deck.dart';
import 'debug_log.dart';
import 'whole_file.dart';

/// The decks the user has made, kept inside the app.
///
/// Same shape as [ReelLibrary] and for the same reasons: a folder and
/// one JSON index, no database. What is different is what is stored —
/// a reel is a finished file the library keeps, a card is a *recipe*
/// the composer can always redraw, so nothing here holds an exported
/// PNG. A deck is a few kilobytes of JSON and one small cover, and it
/// re-renders at full size whenever the user asks for it again.
///
/// That is also what makes a card editable forever: there is no
/// flattening step to undo.
abstract final class CardLibrary {
  /// Bumped on every change, so the tab can rebuild without polling.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// How many decks are kept. Past this the oldest is dropped on the
  /// next save — a card library is a workbench, not an archive, and
  /// every deck the user actually wanted is already in their gallery.
  static const maxDecks = 60;

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/cards');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<File> _indexFile() async =>
      File('${(await _dir()).path}/decks.json');

  /// The cover for [deck] — the first card, rendered small, written
  /// when the deck is saved.
  static Future<File> coverFile(String deckId) async =>
      File('${(await _dir()).path}/$deckId.png');

  /// Newest first.
  static Future<List<CardDeck>> load() async {
    try {
      final index = await _indexFile();
      if (!index.existsSync()) return [];
      final raw = jsonDecode(await index.readAsString()) as List;
      // One deck this build can't read costs only itself, not the shelf
      // the next save writes back.
      final decks = <CardDeck>[];
      for (final e in raw) {
        try {
          decks.add(CardDeck.fromJson((e as Map).cast<String, dynamic>()));
        } catch (_) {}
      }
      decks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return decks;
    } catch (e) {
      rlog('cards: index unreadable, starting fresh — $e');
      return [];
    }
  }

  /// Writes [deck] into the library, replacing whatever was there
  /// under the same id. [cover] is a small PNG of the first card.
  static Future<void> save(CardDeck deck, {Uint8List? cover}) async {
    final all = await load();
    final kept = [
      deck,
      ...all.where((d) => d.id != deck.id),
    ];
    while (kept.length > maxDecks) {
      final dropped = kept.removeLast();
      await _deleteCover(dropped.id);
    }
    if (cover != null) {
      try {
        final f = await coverFile(deck.id);
        await f.writeAsBytes(cover, flush: true);
        // The shelf draws covers through the image cache, keyed by path:
        // without this, a deck changed and saved again keeps showing its
        // old first card until the app restarts.
        await FileImage(f).evict();
      } catch (e) {
        rlog('cards: cover write failed — $e');
      }
    }
    await _write(kept);
  }

  static Future<void> remove(String deckId) async {
    final all = await load();
    await _deleteCover(deckId);
    await _write(all.where((d) => d.id != deckId).toList());
  }

  static Future<void> _deleteCover(String deckId) async {
    try {
      final f = await coverFile(deckId);
      if (f.existsSync()) await f.delete();
    } catch (_) {/* a missing cover is not worth a failure */}
  }

  static Future<void> _write(List<CardDeck> decks) async {
    final index = await _indexFile();
    await writeWhole(index, jsonEncode([for (final d in decks) d.toJson()]));
    revision.value++;
  }

  /// What the library and the storage sheet weigh.
  static Future<int> bytes() async {
    try {
      final d = await _dir();
      return d
          .listSync()
          .whereType<File>()
          .fold<int>(0, (a, f) => a + f.lengthSync());
    } catch (_) {
      return 0;
    }
  }
}
