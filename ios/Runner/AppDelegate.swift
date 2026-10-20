import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let widgetChannel = FlutterMethodChannel(
      name: "com.example.flutter_pgi/task_widget",
      binaryMessenger: controller.binaryMessenger
    )

    widgetChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
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
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
