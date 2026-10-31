import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';
import 'debug_log.dart';
import 'export_budget.dart';
import 'settings_service.dart';
import 'whole_file.dart';

/// Where a note was written, carried into the submission so a reply
/// can tell "walked to Settings to complain" apart from "answered the
/// prompt after a reel". The two arrive in very different moods and
/// the difference is not recoverable from the text.
enum FeedbackSource {
  /// The Settings row. Always available, opens only on a tap.
  settings,

  /// The prompt that lets itself in after a run of renders.
  afterRender,

  /// The Report button on a save that went wrong: on its failure
  /// message, or on the notice after the app closed in the middle of
  /// one. The note opens already written, and the `export` line in
  /// [FeedbackService.payload] carries what actually happened, so a
  /// user who can say no more than "it didn't save" is still a report
  /// that can be acted on.
  exportTrouble,
}

/// The one channel that carries a sentence from a user back to us.
///
/// Everything else this app knows about its users is a count. Ratings
/// are stars with no text attached, and neither store lets the app
/// read its own reviews. So this is it: a text box, a POST, and an
/// inbox.
///
/// **Why FormSubmit.** This used to post to the Formspree form that
/// ai-simply's website contact form uses, and to share its allowance
/// of fifty submissions a month — website contacts and app notes
/// drawing down one quota, with the app's half of it invisible until
/// an inbox went quiet. FormSubmit asks for no account and keeps no
/// monthly ceiling, and it emails each submission, which is the whole
/// job. Its reserved field names are Formspree's too (`_subject`,
/// `_replyto`), so [payload] carried over unchanged.
///
/// No key ships here either — an endpoint is a destination, not a
/// credential; it accepts posts and hands out nothing. What it does
/// expose is [_inbox], and see there for why that wants to be a
/// token.
///
/// **What it sends.** The note, an optional email the user typed
/// themselves, and the handful of facts that make a bug report
/// actionable: app version, platform, language, how many reels they
/// have made, and how exports are planned on this phone, with the last
/// one that failed. No identifier, no file paths, and nothing at all
/// unless a button was pressed. See [payload].
///
/// **When it asks.** Twice — at the fifteenth render and the fortieth —
/// and never again by itself; see [milestones] and [decide]. Unlike
/// the rating ask there is no store quota here, which means the only
/// thing stopping this from being a nag is the policy in this file.
abstract final class FeedbackService {
  /// Where the notes are delivered.
  ///
  /// **This wants to be a token rather than an address.** FormSubmit
  /// accepts either: the address itself, or the hashed token it hands
  /// back once that address has been confirmed. Both route to the same
  /// inbox, and only one of them survives being read out of a shipped
  /// binary by somebody looking for an address to sell. Swapping this
  /// for the token is a one-line change, and a patch rather than a
  /// build.
  ///
  /// **A new address here delivers nothing until it is confirmed.**
  /// FormSubmit mails a confirmation link on the first submission it
  /// ever receives for an address, and drops submissions until that
  /// link is clicked. So the confirming post has to come from a
  /// terminal before any build carrying a new value reaches anyone:
  ///
  ///     curl -X POST https://formsubmit.co/ajax/<address>
  ///       -H 'Content-Type: application/json'
  ///       -d '{"message":"activating"}'
  static const _inbox = 'wolferman81@gmail.com';

  /// The endpoint the sheet posts to. The `/ajax/` path is the one
  /// that answers in JSON; the bare path answers a redirect to a
  /// thank-you page written for a browser, which this is not.
  static const endpoint = 'https://formsubmit.co/ajax/$_inbox';

  /// Sent as the `Referer`, and load-bearing twice over.
  ///
  /// **It is required.** FormSubmit was built for forms on web pages
  /// and refuses anything arriving without a referring page —
  /// *"Make sure you open this page through a web server"* — which is
  /// what an app's POST looks like to it. Dart's client sends no
  /// `Referer` of its own, so without this line every note is refused.
  /// `Origin` alone does not satisfy it; it has to be this header.
  ///
  /// **It is half of the form's identity.** FormSubmit keys a form on
  /// the pair — [_inbox] and this domain — and activates that pair,
  /// not the address. The same address behind a different domain is a
  /// different, unactivated form that refuses everything until its own
  /// link is clicked. So this string is not decoration and not a
  /// comment: editing it silently detaches the app from the activated
  /// form, and no page is ever fetched to notice.
  ///
  /// The value is a domain we actually own. Nothing ever loads it:
  /// FormSubmit wants a referring origin, not a destination. It is a
  /// real domain rather than a tidier invented one because a string
  /// here is a claim to own something, and shipped source is a poor
  /// place to make a claim that is not true.
  static const _referer = 'https://islamcreate.com/';

  /// Tags every submission. The inbox is no longer shared with a
  /// website contact form, so this is belt and braces now — but it
  /// costs one key, and it is what the inbox filters already match.
  static const _app = 'AyahReel';

  /// Renders at which the prompt opens itself, in order: the fifteenth
  /// reel, and the fortieth. Nothing after that.
  ///
  /// Not early. The first renders belong to the reminder invitation and
  /// the store's rating sheet, and they are also the renders where the
  /// user has the least to say. By the fifteenth reel the app is a habit
  /// and its frictions are known; by the fortieth they are a regular,
  /// and a regular's note is the one worth reading twice. Asking at the
  /// second and fifth, and then at the eighth, came too soon: users said
  /// so (2026-10-21).
  ///
  /// Two entries, so a user who ignores both is left alone for good.
  /// The Settings row does not go anywhere.
  static const milestones = <int>[15, 40];

  /// Longest note accepted. Generous — the whole point is the sentence
  /// — but bounded, so a pasted logfile cannot become the payload.
  static const maxMessageLength = 1200;

  static bool _loaded = false;

  /// Reels rendered and kept. Counts saves and shares alike, exactly
  /// as the rating ask does.
  static int _renders = 0;

  /// How many times the sheet has been opened by us rather than by the
  /// user. Opened, not answered: a sheet somebody swiped away has had
  /// its turn.
  static int _asks = 0;

  /// Set once a note has actually been delivered. Ends the automatic
  /// asking for good — somebody who has written to us has done the
  /// thing being asked for.
  static bool _sent = false;

  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _renders = j['renders'] as int? ?? 0;
      _asks = j['asks'] as int? ?? 0;
      _sent = j['sent'] as bool? ?? false;
      _netTrouble = j['net'] as String?;
      _netAt = DateTime.tryParse(j['netAt'] as String? ?? '');
    } catch (_) {/* an unreadable file just means nobody has been asked */}
  }

  /// Reels kept so far, for the payload and for tests.
  static int get renders => _renders;

  /// The whole policy, with no I/O in it: given what we know, should
  /// this render open the sheet?
  ///
  ///     renders 1–14 ─▶ (the reminder and the rating own the early ones)
  ///     render 15    ─▶ ask
  ///     render 40    ─▶ ask, if the first one went unanswered
  ///     after       ─▶ never, on its own
  ///
  /// Counts only — there is no elapsed-time gate, for the same reason
  /// the rating ladder has none: a user who makes fifteen reels in one
  /// sitting is exactly the user worth asking, and waiting a day to
  /// catch them means catching them somewhere they were not thinking
  /// about the app.
  @visibleForTesting
  static bool decide({
    required int renders,
    required int asks,
    required bool sent,
  }) {
    if (sent) return false;
    if (asks >= milestones.length) return false;
    return renders >= milestones[asks];
  }

  /// Call right after a rendered reel has landed — saved or shared.
  /// Counts the render and returns whether the caller should put
  /// [showFeedbackSheet] on screen.
  ///
  /// Pass `mayAsk: false` when something else already has the moment.
  /// The render is still counted, so the ask simply slides to the next
  /// reel rather than stacking on a dialog already being read — the
  /// same arrangement the reminder invitation and the rating sheet
  /// already have between them. This one goes last of the three: it is
  /// ours, it can be repeated at no cost, and Settings carries it
  /// permanently either way.
  ///
  /// A returned true is recorded as an ask immediately, so a sheet the
  /// user swipes away does not come back on the very next reel.
  ///
  /// Never throws. Nothing here is worth risking a finished export.
  static Future<bool> offerAfterRender({bool mayAsk = true}) async {
    try {
      await init();
      _renders++;
      final ask = mayAsk &&
          decide(renders: _renders, asks: _asks, sent: _sent);
      if (ask) _asks++;
      await _persist();
      if (ask) rlog('feedback: asking at $_renders renders (ask $_asks)');
      return ask;
    } catch (e, s) {
      rlogError('feedback offer', e, s);
      return false;
    }
  }

  /// Everything a submission carries, built where it can be read and
  /// tested rather than inline in the POST.
  ///
  /// **The field names are not arbitrary.** They were chosen while
  /// this posted to a form shared with the website's contact form
  /// (`name`, `email`, `subject`, `message`), and they are kept now
  /// that it no longer does, because the inbox filters are written
  /// against them and FormSubmit — like Formspree before it — labels
  /// its notification with whatever keys a submission carries rather
  /// than with a fixed schema:
  ///
  ///   * `message` — the note itself, and nothing else. Everything
  ///     below it is metadata, kept out of the body so a reply is
  ///     answering a person and not a bug report template.
  ///   * `subject` — always the same string, which is what makes app
  ///     feedback filterable from website contact in one inbox.
  ///   * `email` — the reply-to. FormSubmit treats a field of this
  ///     name as the sender, and honours `_replyto` explicitly; both
  ///     are set, so the notification is replyable whichever one the
  ///     account's settings prefer.
  ///
  /// The address is only ever what the user typed into the optional
  /// field. The app never fills it in from anywhere, and a value that
  /// is not an address goes to `contact` instead — a typo in the
  /// reply-to field is how a whole submission gets rejected as
  /// malformed, and a note that arrives unreplyable still beats one
  /// that does not arrive.
  ///
  /// `name` is deliberately absent even though the contact form has
  /// one. The Settings name exists to greet the user on their own home
  /// screen; sending it to an inbox because they reported a bug is not
  /// what they typed it in for.
  @visibleForTesting
  static Map<String, String> payload({
    required String message,
    String contact = '',
    FeedbackSource source = FeedbackSource.settings,
  }) {
    final note = message.trim();
    final who = contact.trim();
    final emailish = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$').hasMatch(who);
    return {
      'message': note.length > maxMessageLength
          ? note.substring(0, maxMessageLength)
          : note,
      // Shared with the website's contact form: same key, so both land
      // in the same column, and a fixed value so app feedback can be
      // filtered out of it in one click.
      'subject': '$_app feedback',
      if (emailish) 'email': who,
      if (emailish) '_replyto': who,
      if (who.isNotEmpty && !emailish) 'contact': who,
      // Reserved: the subject line of the notification itself.
      '_subject': '$_app feedback · ${source.name}',
      // Reserved, both. There is nothing here that can solve a
      // challenge — no browser, no user watching a page — and an
      // empty honeypot is what a human submission looks like, where a
      // filled one is dropped as spam.
      '_captcha': 'false',
      '_honey': '',
      'app': _app,
      'version': kAppVersion,
      'code': codeDate,
      'platform': Platform.operatingSystem,
      'os': Platform.operatingSystemVersion,
      'language': SettingsService.state.value.lang.code,
      'reels': '$_renders',
      'source': source.name,
      'export': [
        PhoneBudget.summary,
        if (_exportTrouble != null) _exportTrouble!,
      ].join(' · '),
      if (_netTrouble != null) 'net': '$_netTrouble${_ago(_netAt)}',
    };
  }

  /// ", 3 h ago": how long before the note the failure was.
  static String _ago(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.isNegative) return '';
    if (d.inMinutes < 1) return ', just now';
    if (d.inHours < 1) return ', ${d.inMinutes} min ago';
    if (d.inDays < 1) return ', ${d.inHours} h ago';
    return ', ${d.inDays} d ago';
  }

  /// The day of the newest fix this code carries.
  ///
  /// `version` can't tell a phone running a patch from one still on the
  /// store build, because a patch keeps the version. Two notes on
  /// 2026-10-06 could have come from either, so a note now says which
  /// code it was written from. Move it forward in every patch that
  /// changes how a save works.
  static const codeDate = '2026-10-24';

  static String? _exportTrouble;

  static String? _netTrouble;
  static DateTime? _netAt;

  /// Keeps the last download that failed — a voice, a surah's text, a
  /// scenery — for the next note, as its `net` line.
  ///
  /// Kept across a restart, unlike [noteExportTrouble]: a note about a
  /// download is written from Settings, often after the app was closed
  /// and opened again to try once more. A note of 2026-10-30 said only
  /// "it can't download the video, though my internet is strong", and
  /// nothing in it said which download, from which host, or what the
  /// phone was told; this says all three. Hosts and file names are
  /// kept, a link's query (a signed address) and the phone's folders
  /// are not.
  static void noteNetTrouble(String what, Object error) {
    final s = netLine(what, error);
    final at = DateTime.now();
    _netTrouble = s;
    _netAt = at;
    unawaited(() async {
      // Read first, or the write would put the counts back to nothing.
      await init();
      _netTrouble = s;
      _netAt = at;
      await _persist();
    }());
  }

  /// [what] and [error] as one short line: links cut to their host and
  /// file, no query, no folders on the phone.
  @visibleForTesting
  static String netLine(String what, Object error) {
    final s = '$what: $error'
        .replaceAllMapped(RegExp(r'''https?://([^/\s"',)]+)[^\s"',)]*'''),
            (m) {
          final path = m[0]!.split('?').first;
          final file = path.substring(path.lastIndexOf('/') + 1);
          return path.indexOf('/', 8) < 0 ? m[1]! : '${m[1]}/…/$file';
        })
        .replaceAll(RegExp(r'''(?<![\w.…])(?:/[^/\s"']+)+/'''), '…/')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.length <= 240 ? s : '${s.substring(0, 239)}…';
  }

  /// Keeps the last export that failed in this run, for the next note.
  ///
  /// The people a save fails for are the ones least able to say why —
  /// "it refuses to download" was all one report had, from a phone that
  /// had never finished a reel — and every way an export can end has
  /// its own fix. Folders are cut out of whatever FFmpeg said: a file's
  /// name is all a report needs, and the folders above it can carry the
  /// name of the phone's owner.
  static void noteExportTrouble(String what, Object error) {
    final s = '$what: $error'
        .replaceAll(RegExp(r'''(?:/[^/\s"']+)+/'''), '…/')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    _exportTrouble = s.length <= 240 ? s : '…${s.substring(s.length - 240)}';
  }

  /// Posts a note. Returns whether it landed.
  ///
  /// A false is a real failure the caller must show — the text is
  /// still in the box and retrying is one tap. This is the one place
  /// in the app where swallowing an error would lose something the
  /// user wrote by hand.
  ///
  /// On success the automatic asking stops for good, whichever sheet
  /// the note came from.
  static Future<bool> send({
    required String message,
    String contact = '',
    FeedbackSource source = FeedbackSource.settings,
    http.Client? client,
  }) async {
    if (message.trim().isEmpty) return false;
    await init();
    final ok = await post(
      payload(message: message, contact: contact, source: source),
      client: client,
      what: 'feedback',
    );
    if (!ok) return false;
    _sent = true;
    await _persist();
    rlog('feedback: sent from ${source.name}');
    return true;
  }

  /// Posts [fields] to the inbox, the way a note goes, and says whether
  /// FormSubmit took them. Shared with [ArenaShareReport], so the two
  /// can never come to disagree about the [_referer] or what counts as
  /// accepted. Never throws.
  static Future<bool> post(
    Map<String, String> fields, {
    http.Client? client,
    String what = 'post',
  }) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(
            Uri.parse(endpoint),
            headers: const {
              // Said out loud even though the `/ajax/` path already
              // answers in JSON: the other path redirects to a
              // thank-you page, and a 302 is not a clear enough
              // answer to key a snackbar on.
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              // See [_referer]: without this the submission is refused.
              'Referer': _referer,
            },
            body: jsonEncode(fields),
          )
          .timeout(const Duration(seconds: 15));
      final ok = r.statusCode >= 200 && r.statusCode < 300 && accepted(r.body);
      if (!ok) rlog('$what: post ${r.statusCode} ${r.body}');
      return ok;
    } catch (e, s) {
      rlogError('$what send', e, s);
      return false;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Whether FormSubmit actually took the submission.
  ///
  /// **The status code is not the answer.** A refused submission comes
  /// back `200 OK` carrying `{"success":"false"}`: an address that was
  /// never activated, a missing referer, a note caught as spam — all
  /// three look exactly like a delivered one from the status line
  /// alone. Keying the snackbar on the status would tell a user their
  /// note was sent and then drop it, which is the single outcome this
  /// file exists to prevent.
  ///
  /// A body that cannot be parsed counts as refused, for the same
  /// reason: the text is still in the box and retrying is one tap,
  /// where a wrongly cheerful snackbar loses the note for good. Both
  /// spellings of true are accepted because the field arrives as the
  /// string `"true"` and there is no reason to depend on that.
  @visibleForTesting
  static bool accepted(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return false;
      final ok = j['success'];
      return ok == true || '$ok'.toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> _persist() async {
    try {
      await writeWhole(await _file(), jsonEncode({
        'renders': _renders,
        'asks': _asks,
        'sent': _sent,
        if (_netTrouble != null) 'net': _netTrouble,
        if (_netAt != null) 'netAt': _netAt!.toIso8601String(),
      }));
    } catch (_) {/* the ask is best-effort, like the rating it follows */}
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/feedback.json');

  /// Test hook: forgets everything, including the fact that the file
  /// was read, so each case starts from a fresh install.
  @visibleForTesting
  static void resetForTest({int renders = 0, int asks = 0, bool sent = false}) {
    _loaded = true;
    _renders = renders;
    _asks = asks;
    _sent = sent;
    _netTrouble = null;
    _netAt = null;
  }
}
