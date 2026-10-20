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

      widgetChannel.setMethodCallHandler { (call: FlutterMethodCall, channelResult: @escaping FlutterResult) in
        if call.method == "refreshTaskWidget" {
          let appGroup = "group.com.example.flutterPgi"
          let defaults = UserDefaults(suiteName: appGroup) ?? UserDefaults.standard

          if let args = call.arguments as? [String: Any] {
            if let token = args["token"] as? String {
              defaults.set(token, forKey: "task_widget_token")
            }
            if let baseUrl = args["baseUrl"] as? String {
              defaults.set(baseUrl, forKey: "task_widget_base_url")
            }
            if let tasksJson = args["tasksJson"] as? String {
              defaults.set(tasksJson, forKey: "task_widget_tasks")
            }
          }

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
