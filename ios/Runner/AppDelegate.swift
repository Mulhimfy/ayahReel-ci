import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the engine's life, with the handler on it.
  private var renderChannel: FlutterMethodChannel?
  private var appsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Direct-to-Instagram-Reels share, on the same registry the plugins
    // use so it gets the engine's messenger rather than a second one.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AyahReelInstagramShare")
    {
      InstagramShare.register(with: registrar)
    }
    // The home-screen widget's link into the app, and the answer to
    // "is it on the home screen"; see WidgetLink.swift.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AyahReelWidgetLink") {
      WidgetLink.register(with: registrar)
    }
    // A save the user waits on keeps the screen on: iOS encodes in the
    // app, on x264, and a long save outlasts auto-lock. Locked, the app
    // is suspended mid-encode and ended for the memory FFmpeg holds.
    // Android answers the same call in RenderClient.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AyahReelRender") {
      let channel = FlutterMethodChannel(
        name: "ayahreel/render", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "keepScreenOn" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
        UIApplication.shared.isIdleTimerDisabled = on
        result(true)
      }
      renderChannel = channel
    }
    // The reel screen's Share to, for TikTok and YouTube: neither takes
    // a video from another app on iOS without its own SDK and a client
    // key, so Dart saves the reel to the library first and this opens
    // the app by the first of its schemes that answers. The schemes are
    // listed in Info.plist's LSApplicationQueriesSchemes.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AyahReelApps") {
      let channel = FlutterMethodChannel(
        name: "ayahreel/apps", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "open" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let urls = (call.arguments as? [String: Any])?["urls"] as? [String] ?? []
        for raw in urls {
          guard let url = URL(string: raw), UIApplication.shared.canOpenURL(url)
          else { continue }
          UIApplication.shared.open(url, options: [:]) { opened in
            result(opened)
          }
          return
        }
        result(false)
      }
      appsChannel = channel
    }
  }
}
