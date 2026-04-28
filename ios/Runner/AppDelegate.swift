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

    let shareChannel = FlutterMethodChannel(
      name: "lecture_vault/share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    shareChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareFiles" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.handleShare(call: call, result: result)
    }
  }

  private func handleShare(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "bad_args",
          message: "分享參數缺失。",
          details: nil
        )
      )
      return
    }

    let text = (arguments["text"] as? String) ?? ""
    let subject = (arguments["subject"] as? String) ?? ""
    let filePaths = (arguments["filePaths"] as? [String]) ?? []

    var items: [Any] = []
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      items.append(text)
    }
    items.append(contentsOf: filePaths.map { URL(fileURLWithPath: $0) })

    guard !items.isEmpty else {
      result(
        FlutterError(
          code: "empty_payload",
          message: "沒有可分享的內容。",
          details: nil
        )
      )
      return
    }

    DispatchQueue.main.async {
      guard let presenter = self.topViewController() else {
        result(
          FlutterError(
            code: "share_unavailable",
            message: "無法取得分享視窗。",
            details: nil
          )
        )
        return
      }

      let controller = UIActivityViewController(
        activityItems: items,
        applicationActivities: nil
      )
      if !subject.isEmpty {
        controller.setValue(subject, forKey: "subject")
      }
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 1,
          height: 1
        )
      }

      presenter.present(controller, animated: true)
      result(nil)
    }
  }

  private func topViewController(
    from root: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?
      .rootViewController
  ) -> UIViewController? {
    if let navigationController = root as? UINavigationController {
      return topViewController(from: navigationController.visibleViewController)
    }
    if let tabBarController = root as? UITabBarController {
      return topViewController(from: tabBarController.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }
    return root
  }
}
