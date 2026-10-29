/// Where to send someone who wants the app. One place, so the invite
/// copy in both languages can never drift from the real listings.
///
/// Both are the region-neutral canonical forms:
///
/// Apple hands out the listing URL as `/us/app/<title-slug>/id<n>`. The
/// slug is cosmetic and the `/us/` pins the link to the American
/// storefront — the wrong store for most of this app's audience, and a
/// dead end for anyone whose Apple ID lives elsewhere. Stripped to the
/// numeric ID, Apple redirects each visitor to their own store, and the
/// ID never changes.
///
/// Google's is keyed on the applicationId, which can never be changed
/// once an app has been uploaded. That makes it the one link that
/// survives every track promotion — it already points at the right
/// place while the app is in closed testing (testers only), and starts
/// resolving for everyone the day production goes live, unchanged.
const appStoreUrl = 'https://apps.apple.com/app/id6794389870';
const playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.ayahreel.app';

/// The Apple listing aimed at the review composer rather than the
/// product page. Apple documents `action=write-review` as the way to
/// open the sheet with the stars and the text field already up, which
/// is the whole point of a "Rate us" tap — the plain listing lands on
/// screenshots and leaves the user to find the ratings section.
///
/// Play has no equivalent parameter. Its listing already carries the
/// star row above the fold, so [playStoreUrl] is the review link there.
const appStoreReviewUrl = '$appStoreUrl?action=write-review';
