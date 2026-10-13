import Flutter
import UIKit

/// The iOS half of Meta's "Sharing to Reels" handoff.
///
/// Instagram takes no file and no intent here: the video's *bytes* go on
/// the general pasteboard under `com.instagram.sharedSticker.backgroundVideo`,
/// and opening `instagram-reels://share` makes Instagram read them and open
/// its reel composer with the video loaded. A Meta App ID goes on beside it
/// when the build has one — it earns the attribution line on the finished
/// reel, and the composer opens either way.
/// The items expire after five minutes so a reel does not sit in the
/// user's clipboard for the rest of the day.
///
/// The Stories half (`shareStory`) is the same contract with a picture:
/// PNG bytes under `com.instagram.sharedSticker.backgroundImage`, then
/// `instagram-stories://share`, and Instagram opens its story composer
/// with the picture as the story's full-bleed background.
///
/// Returns false to Dart — without having shown anything — whenever the
/// handoff can't be made, which is Dart's cue to open the share sheet.
enum InstagramShare {
  private static let channelName = "ayahreel/instagram"
  private static let shareURL = URL(string: "instagram-reels://share")!
  private static let storyURL = URL(string: "instagram-stories://share")!

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "shareReel" || call.method == "shareStory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String
      else {
        result(FlutterError(code: "bad_args",
                            message: "path is required",
                            details: nil))
        return
      }
      // On iOS the app id is admission: without a Meta App ID Instagram
      // opens and refuses the share. Empty means this build has none.
      let appID = args["appId"] as? String ?? ""
      if call.method == "shareStory" {
        result(shareStory(path: path, appID: appID))
      } else {
        result(share(path: path, appID: appID))
      }
    }
  }

  private static func shareStory(path: String, appID: String) -> Bool {
    // `instagram-stories` must be in LSApplicationQueriesSchemes or this
    // answers false on a phone that has Instagram installed.
    guard UIApplication.shared.canOpenURL(storyURL) else { return false }
    guard let image = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
      return false
    }
    // One item carrying both keys, the shape Meta's own sample uses for
    // Stories.
    var item: [String: Any] = ["com.instagram.sharedSticker.backgroundImage": image]
    if !appID.isEmpty {
      item["com.instagram.sharedSticker.appID"] = appID
    }
    UIPasteboard.general.setItems(
      [item],
      options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
    )
    // The id rides on the url as well as the pasteboard; Meta's docs
    // name it there, and Instagram reads whichever it looks at.
    var url = storyURL
    if !appID.isEmpty,
       var parts = URLComponents(url: storyURL, resolvingAgainstBaseURL: false)
    {
      parts.queryItems = [URLQueryItem(name: "source_application", value: appID)]
      url = parts.url ?? storyURL
    }
    UIApplication.shared.open(url)
    return true
  }

  private static func share(path: String, appID: String) -> Bool {
    // Instagram missing, or too old to know the scheme. `instagram-reels`
    // must also be in LSApplicationQueriesSchemes or this answers false
    // on a phone that has Instagram installed.
    guard UIApplication.shared.canOpenURL(shareURL) else { return false }
    guard let video = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
      return false
    }

    var items: [[String: Any]] = [
      ["com.instagram.sharedSticker.backgroundVideo": video]
    ]
    if !appID.isEmpty {
      items.append(["com.instagram.sharedSticker.appID": appID])
    }
    UIPasteboard.general.setItems(
      items,
      options: [.expirationDate: Date().addingTimeInterval(5 * 60)]
    )
    UIApplication.shared.open(shareURL)
    return true
  }
}
