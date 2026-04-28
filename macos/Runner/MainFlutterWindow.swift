import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    registerShareChannel(registry: flutterViewController)
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func registerShareChannel(registry: FlutterPluginRegistry) {
    let registrar = registry.registrar(forPlugin: "LectureVaultShare")
    let channel = FlutterMethodChannel(
      name: "lecture_vault/share",
      binaryMessenger: registrar.messenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareFiles" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let view = self?.contentViewController?.view
      else {
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
        let picker = NSSharingServicePicker(items: items)
        let anchor = NSRect(
          x: view.bounds.midX,
          y: view.bounds.midY,
          width: 1,
          height: 1
        )
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        result(nil)
      }
    }
  }
}
