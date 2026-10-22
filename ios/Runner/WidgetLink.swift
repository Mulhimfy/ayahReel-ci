import Flutter
import UIKit
import WidgetKit

/// The app's side of the home-screen widget; see HomeWidgetService in
/// Dart for what each call is for.
///
/// The widget itself (the AyahWidget target) needs nothing from the
/// app: it carries its own list and its own clock. What crosses this
/// channel is only a tap on it — `ayahreel://verse/2/152`, arriving
/// through the scene delegate, at launch or while the app is open —
/// and whether the widget is on the home screen at all, which
/// WidgetCenter can answer and which is what stops the nudges.
class WidgetLink: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var channel: FlutterMethodChannel?

  /// A tap the app was opened with, held until Dart asks for it.
  /// Cleared on hand-over, so a hot restart does not replay it.
  private var pendingLink: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = WidgetLink()
    let channel = FlutterMethodChannel(
      name: "ayahreel/widget", binaryMessenger: registrar.messenger())
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.addSceneDelegate(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getLaunchLink":
      result(pendingLink)
      pendingLink = nil
    case "isInstalled":
      WidgetCenter.shared.getCurrentConfigurations { answer in
        let installed = (try? answer.get())?.contains { $0.kind == "AyahWidget" } ?? false
        DispatchQueue.main.async { result(installed) }
      }
    case "canRequestPin", "requestPin":
      // iOS has no API for placing a widget; the sheet in the app
      // shows the steps instead.
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Scene events

  /// A cold launch from the widget: the link rides in the connection
  /// options. Dart is not up yet, so it waits for `getLaunchLink`.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let url = connectionOptions?.urlContexts.first(where: Self.isOurs)?.url else {
      return false
    }
    pendingLink = url.absoluteString
    return false  // observed, not consumed: let the rest of launch proceed
  }

  /// A tap while the app is open (or suspended). Handed straight to
  /// Dart if it is listening, kept for it otherwise.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    guard let url = URLContexts.first(where: Self.isOurs)?.url else { return false }
    if let channel = channel {
      channel.invokeMethod("onLink", arguments: url.absoluteString)
    } else {
      pendingLink = url.absoluteString
    }
    return true
  }

  private static func isOurs(_ context: UIOpenURLContext) -> Bool {
    context.url.scheme == "ayahreel"
  }
}
