import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
  }
}
