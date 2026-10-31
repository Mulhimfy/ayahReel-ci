import Flutter
import UIKit
import onnxruntime_objc

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the engine's life, with the handler on it.
  private var renderChannel: FlutterMethodChannel?
  private var appsChannel: FlutterMethodChannel?
  private var listenBridge: ListenBridge?

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
        switch call.method {
        case "keepScreenOn":
          let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
          UIApplication.shared.isIdleTimerDisabled = on
          result(true)
        case "physicalMemory":
          // The phone's memory in kB, as Android's /proc/meminfo gives
          // it: what PhoneBudget plans a save by (export_budget.dart).
          result(Int(ProcessInfo.processInfo.physicalMemory / 1024))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      renderChannel = channel
    }
    // The listening model (AyahReel Listen): see ListenBridge below.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AyahReelListen") {
      listenBridge = ListenBridge(messenger: registrar.messenger())
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

/// The listening model on the phone (channel "ayahreel/listen"), as
/// ListenBridge.kt is on Android: ONNX Runtime with one session at a
/// time, every call on a queue of its own so a long run never holds the
/// main thread.
///
///  - load {path, threads}: opens the model file (again only if it changed)
///  - run {wave: Float32List, 16 kHz mono}: {logp: Float32List, frames, width}
///  - unload: lets the session and its memory go
final class ListenBridge {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "ayahreel.listen", qos: .userInitiated)
  private var env: ORTEnv?
  private var session: ORTSession?
  private var loadedPath: String?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ayahreel/listen", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func fail(_ result: @escaping FlutterResult, _ code: String, _ error: Error) {
    DispatchQueue.main.async {
      result(FlutterError(code: code, message: "\(error)", details: nil))
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "load":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "load", message: "no path", details: nil))
        return
      }
      let threads = args["threads"] as? Int ?? 2
      queue.async {
        do {
          if self.loadedPath != path || self.session == nil {
            self.session = nil
            self.loadedPath = nil
            if self.env == nil {
              self.env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
            }
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(Int32(threads))
            try options.setGraphOptimizationLevel(ORTGraphOptimizationLevel.all)
            self.session = try ORTSession(
              env: self.env!, modelPath: path, sessionOptions: options)
            self.loadedPath = path
          }
          self.reply(result, ["ok": true])
        } catch {
          self.fail(result, "load", error)
        }
      }
    case "run":
      guard let wave = args["wave"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "run", message: "no wave", details: nil))
        return
      }
      queue.async {
        do {
          guard let session = self.session else {
            throw NSError(domain: "listen", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "not loaded"])
          }
          let n = wave.data.count / MemoryLayout<Float>.size
          let input = try ORTValue(
            tensorData: NSMutableData(data: wave.data),
            elementType: ORTTensorElementDataType.float,
            shape: [1, NSNumber(value: n)])
          let outputs = try session.run(
            withInputs: ["wave": input], outputNames: ["logp"], runOptions: nil)
          guard let value = outputs["logp"] else {
            throw NSError(domain: "listen", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "no logp"])
          }
          let shape = try value.tensorTypeAndShapeInfo().shape.map { $0.intValue }
          let data = try value.tensorData() as Data
          self.reply(result, [
            "logp": FlutterStandardTypedData(float32: data),
            "frames": shape.first ?? 0,
            "width": shape.count > 1 ? shape[1] : 0,
          ])
        } catch {
          self.fail(result, "run", error)
        }
      }
    case "unload":
      queue.async {
        self.session = nil
        self.loadedPath = nil
        self.reply(result, true)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
