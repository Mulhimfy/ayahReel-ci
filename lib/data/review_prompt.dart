import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'debug_log.dart';
import 'store_links.dart';
import 'whole_file.dart';

/// What an export earned, if anything.
enum ReviewAsk {
  /// Nothing this time.
  none,

  /// The OS sheet was called. Whether the user saw it is unknowable.
  native,

  /// Our own sheet should be shown. The caller owns this one, because
  /// only the caller still has a BuildContext on screen.
  banner,
}

/// When to ask for a rating, and what to do about the fact that the
/// asking is not ours to control.
///
/// Both stores hand their prompt out on their own terms:
///
///   * iOS shows StoreKit's sheet at most **three times in any 365-day
///     window, per user, per app**, and the call is a silent no-op
///     after that.
///   * Play enforces a quota it deliberately does not publish,
///     throttles repeat flows inside a month, and can change either
///     without notice.
///   * Neither one reports back. `requestReview` completes identically
///     whether the sheet appeared, was swallowed, or was dismissed.
///
/// That last point rules out the obvious design. "Show ours if the
/// native ask failed" cannot be written, because failure is not
/// observable — only *spent* is. So the policy keys on what we do
/// know: how many exports have happened, and whether the OS sheet has
/// had its go. See [decide].
///
/// The two platforms then diverge, and not by taste.
///
/// **iOS: the OS sheet, three times, and nothing else of ours.**
/// Apple's allowance is three a year and the full [milestones] ladder
/// spends exactly three, so an iOS user already gets every automatic
/// ask that platform permits. Adding our own on top would buy at most
/// a fourth — and guideline 5.6.1 disallows custom review prompts.
/// This app cannot pay that: a refused build burns the version train,
/// not just the day (0.1.0, 0.1.1 and 1.0 are already spent that way).
/// A near-zero gain against a version number is not a trade worth
/// taking, so on iOS nothing of ours ever appears by itself. The
/// Settings row stays — it is user-initiated, which is precisely what
/// 5.6.1 does not touch.
///
/// **Android: one OS sheet, then ours, repeating.** Play's quota makes
/// a second and third `launchReviewFlow` near-certain no-ops, so the
/// ladder there is one rung and our own sheet takes every rung after —
/// every [bannerEveryExports] exports, for as long as the user keeps
/// making reels. Google has no rule against it, and this is where the
/// real gap was: without it an Android user who missed the one flow
/// had no automatic route to the listing at all.
///
/// Both stop dead the moment the user opens the listing.
abstract final class ReviewPrompt {
  /// Successful exports at which the OS sheet fires, in order — iOS
  /// runs the whole ladder, Android only its first rung.
  ///
  /// The first entry is deliberate. Apple sets no floor: there is no
  /// "not before the Nth use" rule anywhere in the guidelines, and
  /// nothing in App Review can see when the call is made, so the
  /// earliest legal moment is taken. A first export is a user watching
  /// something they made finish, which is as close to a peak as this
  /// app has.
  ///
  /// It will not always land on the literal first export: the reminder
  /// invitation gets first refusal on that moment, so where
  /// notification permission was declined at onboarding this slides to
  /// the first export with a clear screen. That is the intent —
  /// earliest *clean* moment, not earliest moment.
  ///
  /// Three entries, so the ladder can never overrun what iOS allows.
  /// 6 catches the user who waved the first one away while still
  /// finding their feet; 30 is one last go at someone who has made
  /// thirty reels and never rated. Nothing after that.
  static const milestones = <int>[1, 6, 30];

  /// How often our own sheet takes an export on Android, once the OS
  /// sheet has had its go. Every fifth reel, until the listing opens.
  static const bannerEveryExports = 5;

  static bool _loaded = false;

  /// Successful exports counted so far — saves and shares both, since
  /// either one is a reel the user decided to keep.
  static int _exports = 0;

  /// How many OS sheets have been called for. Not how many showed:
  /// nothing can know that.
  static int _asks = 0;

  /// Set once the user has opened the listing. They have been handed
  /// the store; asking again would be nagging, and this is the only
  /// signal that ever stops the loop.
  static bool _wentToListing = false;

  /// Set once the user has picked their stars in our sheet. Whatever
  /// they picked, our own sheet does not come back by itself: they have
  /// answered it, and the store's button was in front of them either way.
  static bool _answered = false;

  /// Swappable so tests never touch a method channel.
  @visibleForTesting
  static InAppReview review = InAppReview.instance;

  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _exports = j['exports'] as int? ?? 0;
      _asks = j['asks'] as int? ?? 0;
      _wentToListing = j['wentToListing'] as bool? ?? false;
      _answered = j['answered'] as bool? ?? false;
    } catch (_) {/* an unreadable file just means nobody has been asked */}
  }

  /// The whole policy, with no I/O in it, so it can be tested without a
  /// device: given what we know, what has this export earned?
  ///
  ///     iOS       1 ─▶ OS sheet   6 ─▶ OS sheet   30 ─▶ OS sheet   ∎
  ///     Android   1 ─▶ OS sheet   5 ─▶ ours  10 ─▶ ours  15 ─▶ …
  ///
  /// Counts alone decide it. There is deliberately no elapsed-time
  /// gate anywhere: a user who reaches every milestone in one
  /// afternoon gets every ask that afternoon, and iOS will show what
  /// its own 3-per-365 allowance permits and swallow the rest without
  /// saying so.
  ///
  /// Ours never precedes the OS sheet on either platform. The
  /// store-owned prompt is strictly better where it is available — one
  /// tap, no app switch, no guideline attached — so it always gets the
  /// first and best moment.
  @visibleForTesting
  static ReviewAsk decide({
    required int exports,
    required int asks,
    required bool wentToListing,
    required bool android,
    bool answered = false,
  }) {
    if (wentToListing) return ReviewAsk.none;
    final ladder = android ? milestones.take(1).toList() : milestones;
    if (asks < ladder.length && exports >= ladder[asks]) {
      return ReviewAsk.native;
    }
    // iOS stops here, always. See the class doc for why ours may never
    // open itself there.
    if (!android || answered) return ReviewAsk.none;
    if (asks == 0) return ReviewAsk.none;
    if (exports % bannerEveryExports != 0) return ReviewAsk.none;
    return ReviewAsk.banner;
  }

  /// Call right after a reel has actually landed — saved to the
  /// gallery or handed to a share sheet. Counts the export and returns
  /// what it earned.
  ///
  /// A [ReviewAsk.native] has already been fired by the time this
  /// returns. A [ReviewAsk.banner] is the caller's to show.
  ///
  /// Pass `mayAsk: false` when something else already has the screen —
  /// the reminder invitation gets first refusal on this moment. The
  /// export is still counted, so nothing is lost; the ask simply lands
  /// on the next reel instead of stacking on a dialog the user is
  /// already reading.
  ///
  /// Never throws. A rating prompt that could break an export the user
  /// just watched finish would be a bad trade at any conversion rate.
  static Future<ReviewAsk> offerAfterExport({bool mayAsk = true}) async {
    try {
      await init();
      _exports++;
      if (!mayAsk) {
        await _persist();
        return ReviewAsk.none;
      }
      final ask = decide(
        exports: _exports,
        asks: _asks,
        wentToListing: _wentToListing,
        android: Platform.isAndroid,
        answered: _answered,
      );
      if (ask != ReviewAsk.native) {
        await _persist();
        return ask;
      }
      // Asked before the rung is spent: `isAvailable` is false on a
      // device with no Play Store and on anything below iOS 10.3, and
      // there the sheet can never appear. Marking it spent would hand
      // an Android user straight to our sheet having never been
      // offered the store's — so leave the count alone and let the
      // next export try again.
      if (!await review.isAvailable()) {
        await _persist();
        return ReviewAsk.none;
      }
      await review.requestReview();
      _asks++;
      await _persist();
      rlog('review: native ask at $_exports exports (ask $_asks)');
      return ReviewAsk.native;
    } catch (e, s) {
      rlogError('review ask', e, s);
      return ReviewAsk.none;
    }
  }

  /// The store listing itself — what our sheet's button opens, and
  /// what the Settings row opens.
  ///
  /// This is the half that cannot be swallowed. Whatever either store
  /// has decided about its own prompt — quota spent, dialog declined,
  /// shown three times already this year — the listing is a web page
  /// and it always opens.
  ///
  /// Reaching it also ends the loop for good: [_wentToListing] is set
  /// before the launch is even attempted, because a user who tapped
  /// "Open the App Store" has done everything that was asked of them
  /// whether or not the browser cooperated.
  ///
  /// Returns whether it opened, so the caller can say something when
  /// it doesn't rather than leaving a dead tap.
  static Future<bool> openListing() async {
    await init();
    _wentToListing = true;
    await _persist();
    final url = Platform.isIOS ? appStoreReviewUrl : playStoreUrl;
    try {
      // `canLaunchUrl` is skipped for the same reason the privacy
      // policy skips it: on Android 11+ it needs a <queries> entry to
      // answer truthfully, and an https URL never needs one.
      return await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (e, s) {
      rlogError('open listing', e, s);
      return false;
    }
  }

  /// The user picked their stars in our sheet; see [_answered].
  static Future<void> answered() async {
    await init();
    if (_answered) return;
    _answered = true;
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      await writeWhole(await _file(), jsonEncode({
        'exports': _exports,
        'asks': _asks,
        'wentToListing': _wentToListing,
        'answered': _answered,
      }));
    } catch (_) {/* the ask is best-effort, like the rewards it follows */}
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/review.json');

  /// Back to a fresh install, for tests.
  @visibleForTesting
  static void resetForTest({
    int exports = 0,
    int asks = 0,
    bool wentToListing = false,
    bool answered = false,
  }) {
    _loaded = true;
    _exports = exports;
    _asks = asks;
    _wentToListing = wentToListing;
    _answered = answered;
  }
}
