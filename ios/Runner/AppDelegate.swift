import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var deepLinkChannel: FlutterMethodChannel?
  private var initialUrl: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      initialUrl = url.absoluteString
    }

    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let widgetChannel = FlutterMethodChannel(
        name: "com.example.flutter_pgi/task_widget",
        binaryMessenger: controller.binaryMessenger
      )

      widgetChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, channelResult: @escaping FlutterResult) in
        if call.method == "refreshTaskWidget" {
          var token: String?
          var baseUrl: String?
          var tasksJson: String?

          if let args = call.arguments as? [String: Any] {
            token = args["token"] as? String
            baseUrl = args["baseUrl"] as? String
            tasksJson = args["tasksJson"] as? String
          }

          self?.saveToSharedStorage(token: token, baseUrl: baseUrl, tasksJson: tasksJson)

          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          channelResult(true)
        } else {
          channelResult(FlutterMethodNotImplemented)
        }
      }

      let dlChannel = FlutterMethodChannel(
        name: "com.example.flutter_pgi/deep_link",
        binaryMessenger: controller.binaryMessenger
      )
      self.deepLinkChannel = dlChannel
      dlChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, channelResult: @escaping FlutterResult) in
        if call.method == "getInitialUrl" {
          channelResult(self?.initialUrl)
        } else {
          channelResult(FlutterMethodNotImplemented)
        }
      }
    }

    return result
  }

  private func getAppGroupCandidates() -> [String] {
    var candidates = ["group.com.example.flutterPgi"]
    if let bundleId = Bundle.main.bundleIdentifier {
      let base = bundleId.replacingOccurrences(of: ".TaskWidgetExtension", with: "")
      candidates.append("group.\(base)")
      let parts = base.split(separator: ".")
      if let last = parts.last, last.count >= 8 {
        candidates.append("group.com.example.flutterPgi.\(last)")
      }
    }
    return candidates
  }

  private func saveToSharedStorage(token: String?, baseUrl: String?, tasksJson: String?) {
    let candidates = getAppGroupCandidates()

    for group in candidates {
      if let defaults = UserDefaults(suiteName: group) {
        if let token = token { defaults.set(token, forKey: "task_widget_token") }
        if let baseUrl = baseUrl { defaults.set(baseUrl, forKey: "task_widget_base_url") }
        if let tasksJson = tasksJson { defaults.set(tasksJson, forKey: "task_widget_tasks") }
        defaults.synchronize()
      }

      if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
        if let tasksJson = tasksJson {
          let fileURL = containerURL.appendingPathComponent("tasks.json")
          try? tasksJson.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        if let token = token {
          let fileURL = containerURL.appendingPathComponent("token.txt")
          try? token.write(to: fileURL, atomically: true, encoding: .utf8)
        }
      }
    }

    // Also persist to standard UserDefaults
    let standard = UserDefaults.standard
    if let token = token { standard.set(token, forKey: "task_widget_token") }
    if let baseUrl = baseUrl { standard.set(baseUrl, forKey: "task_widget_base_url") }
    if let tasksJson = tasksJson { standard.set(tasksJson, forKey: "task_widget_tasks") }
    standard.synchronize()
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    initialUrl = url.absoluteString
    deepLinkChannel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
    return super.application(app, open: url, options: options)
  }
}
