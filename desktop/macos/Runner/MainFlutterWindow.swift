import Cocoa
import CFNetwork
import FlutterMacOS
import ImageIO
import Security
import UserNotifications

class MainFlutterWindow: NSWindow {
  private var nativeBridge: XingyuNativeBridge?

  override func awakeFromNib() {
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let controller = FlutterViewController(project: project)
    contentViewController = controller
    title = "仓库 · 星屿"
    minSize = NSSize(width: 720, height: 600)
    setContentSize(NSSize(width: 1280, height: 820))
    center()
    tabbingMode = .disallowed
    RegisterGeneratedPlugins(registry: controller)
    nativeBridge = XingyuNativeBridge(messenger: controller.engine.binaryMessenger)
    super.awakeFromNib()
  }
}

/// Local login Keychain, scoped to this app. No password or session file fallback.
final class XingyuKeychain {
  static let service = "moe.cangku.xingyu.macos.secure.v1"
  enum Failure: Error { case arguments, keychain(OSStatus), data }

  static func query(_ key: String) throws -> [String: Any] {
    guard !key.isEmpty, key.utf8.count <= 120,
          key.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
          !key.contains("..") else { throw Failure.arguments }
    // Omit synchronizable/data-protection/access-group attributes: the standard
    // macOS login Keychain works with a local ad-hoc test signature, without a
    // paid team/provisioning profile. Items are not enrolled in iCloud sync.
    return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key]
  }

  static func read(_ key: String) throws -> String? {
    var request = try query(key)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw Failure.keychain(status) }
    guard let bytes = value as? Data, bytes.count <= 65536,
          let text = String(data: bytes, encoding: .utf8) else { throw Failure.data }
    return text
  }

  static func write(_ key: String, value: String) throws {
    let request = try query(key), bytes = Data(value.utf8)
    guard bytes.count <= 65536 else { throw Failure.arguments }
    let status = SecItemUpdate(request as CFDictionary,
                               [kSecValueData as String: bytes] as CFDictionary)
    if status == errSecItemNotFound {
      var item = request
      item[kSecValueData as String] = bytes
      item[kSecAttrLabel as String] = "星屿 · 本机会话"
      let added = SecItemAdd(item as CFDictionary, nil)
      guard added == errSecSuccess else { throw Failure.keychain(added) }
    } else if status != errSecSuccess { throw Failure.keychain(status) }
  }

  static func delete(_ key: String) throws {
    let status = SecItemDelete(try query(key) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure.keychain(status)
    }
  }
}

final class XingyuNativeBridge {
  private let storage: FlutterMethodChannel
  private let clipboard: FlutterMethodChannel
  private let platform: FlutterMethodChannel
  private let notifications: XingyuNotifications

  init(messenger: FlutterBinaryMessenger) {
    notifications = XingyuNotifications(messenger: messenger)
    storage = FlutterMethodChannel(name: "moe.cangku.xingyu/secure_storage", binaryMessenger: messenger)
    clipboard = FlutterMethodChannel(name: "moe.cangku.xingyu/image_clipboard", binaryMessenger: messenger)
    platform = FlutterMethodChannel(name: "moe.cangku.xingyu/platform", binaryMessenger: messenger)
    storage.setMethodCallHandler { call, result in
      guard ["read", "write", "delete"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      do {
        guard let arguments = call.arguments as? [String: Any],
              let key = arguments["key"] as? String else { throw XingyuKeychain.Failure.arguments }
        switch call.method {
        case "read": result(try XingyuKeychain.read(key))
        case "write":
          guard let value = arguments["value"] as? String else { throw XingyuKeychain.Failure.arguments }
          try XingyuKeychain.write(key, value: value)
          result(nil)
        default: try XingyuKeychain.delete(key); result(nil)
        }
      } catch {
        result(FlutterError(code: "secure_storage", message: "系统钥匙串暂不可用，请确认登录钥匙串已解锁。", details: nil))
      }
    }
    clipboard.setMethodCallHandler { call, result in
      guard call.method == "readImage" else { result(FlutterMethodNotImplemented); return }
      do {
        result(try Self.readClipboardImage().map { FlutterStandardTypedData(bytes: $0) })
      } catch {
        result(FlutterError(code: "clipboard_image", message: "图片不能超过 1 MB，或图片格式无法识别。", details: nil))
      }
    }
    platform.setMethodCallHandler { call, result in
      guard call.method == "proxy" else { result(FlutterMethodNotImplemented); return }
      result(Self.systemProxy())
    }
  }

  static func readClipboardImage() throws -> Data? {
    let board = NSPasteboard.general
    if let png = board.data(forType: .png) {
      guard png.count <= 1024 * 1024 else { throw XingyuKeychain.Failure.data }
      try validateImage(png)
      return png
    }
    guard let data = board.data(forType: .tiff) else { return nil }
    guard data.count <= 16 * 1024 * 1024 else { throw XingyuKeychain.Failure.data }
    let source = try validateImage(data)
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
          png.count <= 1024 * 1024 else { throw XingyuKeychain.Failure.data }
    return png
  }

  @discardableResult
  static func validateImage(_ data: Data) throws -> CGImageSource {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 10000, height <= 10000,
          width * height <= 40000000 else { throw XingyuKeychain.Failure.data }
    return source
  }

  static func systemProxy() -> [String: Any] {
    guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
      return ["host": "", "port": 0]
    }
    for (enabled, host, port) in [
      (kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort),
      (kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort),
    ] {
      if (settings[enabled as String] as? NSNumber)?.intValue == 1,
         let name = settings[host as String] as? String,
         let number = settings[port as String] as? NSNumber {
        return ["host": name, "port": number.intValue]
      }
    }
    return ["host": "", "port": 0]
  }
}


/// Uses macOS notification permission and the system Notification Center.
final class XingyuNotifications: NSObject, UNUserNotificationCenterDelegate {
  private let channel: FlutterMethodChannel
  private var owner = 0, enabled = false
  private var pending: [String: Any] = [:]
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "moe.cangku.xingyu/notifications", binaryMessenger: messenger)
    super.init()
    UNUserNotificationCenter.current().delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "status":
        center.getNotificationSettings { settings in
          DispatchQueue.main.async { result(["supported": true, "granted": settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional]) }
        }
      case "request":
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in DispatchQueue.main.async { result(granted) } }
      case "settings":
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        result(nil)
      case "takeOpen": result(self.pending); self.pending = [:]
      case "configure":
        let args = call.arguments as? [String: Any] ?? [:]
        let nextOwner = args["uid"] as? Int ?? 0
        let nextEnabled = args["enabled"] as? Bool == true && nextOwner > 0
        if nextOwner != self.owner || !nextEnabled {
          self.pending = [:]; center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
        }
        self.owner = nextOwner; self.enabled = nextEnabled; result(nil)
      case "show":
        guard let args = call.arguments as? [String: Any], self.enabled,
              args["uid"] as? Int == self.owner, let key = args["key"] as? String else { result(nil); return }
        let content = UNMutableNotificationContent()
        content.title = args["title"] as? String ?? "星屿 · 新消息"
        content.body = args["body"] as? String ?? "点击查看新消息"
        content.sound = .default
        content.userInfo = args.filter { ["uid", "key", "kind", "target", "channel"].contains($0.key) }
        center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) { error in
          DispatchQueue.main.async {
            if error != nil { result(FlutterError(code: "notification", message: "系统通知暂不可用，请检查权限", details: nil)) } else { result(nil) }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    DispatchQueue.main.async {
      if info["uid"] as? Int == self.owner && self.enabled {
        self.pending = Dictionary(uniqueKeysWithValues: info.compactMap { key, value in (key as? String).map { ($0, value) } })
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        self.channel.invokeMethod("opened", arguments: nil)
      }
      completionHandler()
    }
  }
}
