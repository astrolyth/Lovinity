import Flutter
import UIKit

/// Delivers text shared via the Share extension (which stores it in the App
/// Group under `pending_share` and opens `lovinity://share`) to Dart over the
/// "lovinity/share" channel, mirroring MainActivity.kt: a cold-start share is
/// pulled with getInitialShare; later shares are pushed with onShare.
class SceneDelegate: FlutterSceneDelegate {
  private static let appGroup = "group.com.lovinity.lovinity"
  private static let pendingKey = "pending_share"

  private var channel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "lovinity/share", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        if call.method == "getInitialShare" {
          result(Self.takePendingShare())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      self.channel = channel
    }
    // A cold-start share link stays in the App Group until Dart pulls it.
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts
    where context.url.scheme == "lovinity" && context.url.host == "share" {
      if let payload = Self.takePendingShare() {
        channel?.invokeMethod("onShare", arguments: payload)
      }
    }
  }

  /// Read-and-clear, so a share is delivered exactly once.
  private static func takePendingShare() -> [String: Any]? {
    guard let defaults = UserDefaults(suiteName: appGroup),
      let payload = defaults.dictionary(forKey: pendingKey)
    else { return nil }
    defaults.removeObject(forKey: pendingKey)
    return payload
  }
}
