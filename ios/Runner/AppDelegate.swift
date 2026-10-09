import AuthenticationServices
import Flutter
import UIKit
import YandexLoginSDK

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PddYandexAuth") {
      PddYandexAuth.register(with: registrar)
    }
  }
}

/// LoginSDK uses a Yandex app if available, otherwise a system browser session.
/// The token is passed to Flutter once and exchanged for our server session.
final class PddYandexAuth: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate,
  YandexLoginSDKObserver {
  private let registrar: FlutterPluginRegistrar
  private var pendingResult: FlutterResult?
  private var activated = false

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    do {
      try YandexLoginSDK.shared.activate(with: "94aa539db4634e44bf0b209d9a2205d2")
      YandexLoginSDK.shared.add(observer: self)
      activated = true
    } catch {
      // Never log SDK errors: they may contain callback URLs or credentials.
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PddYandexAuth(registrar: registrar)
    let channel = FlutterMethodChannel(name: "pdd/yandex_auth", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard activated else {
      result(FlutterError(code: "sdk_unavailable", message: "Yandex SDK is unavailable", details: nil))
      return
    }
    switch call.method {
    case "signIn":
      guard pendingResult == nil else {
        result(FlutterError(code: "sign_in_in_progress", message: "Login is already running", details: nil))
        return
      }
      guard var presenter = registrar.viewController else {
        result(FlutterError(code: "no_presenter", message: "Login screen is unavailable", details: nil))
        return
      }
      while let presented = presenter.presentedViewController { presenter = presented }
      pendingResult = result
      do {
        // Always allow choosing an account; the app session has its own lifetime.
        try YandexLoginSDK.shared.logout()
        try YandexLoginSDK.shared.authorize(with: presenter, webAuthorizationMethod: .system)
      } catch {
        finish(FlutterError(code: "sign_in_failed", message: "Yandex login failed", details: nil))
      }
    case "signOut":
      do {
        try YandexLoginSDK.shared.logout()
        result(nil)
      } catch {
        result(FlutterError(code: "sign_out_failed", message: "Yandex logout failed", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func didFinishLogin(with result: Result<LoginResult, Error>) {
    switch result {
    case .success(let login):
      let token = login.token
      // Our server session owns persistence, so discard the SDK's cached token.
      try? YandexLoginSDK.shared.logout()
      finish(token.isEmpty ? FlutterError(code: "missing_credential", message: "Empty Yandex token", details: nil) : token)
    case .failure(let error):
      let systemError = error as NSError
      if systemError.domain == ASWebAuthenticationSessionError.errorDomain &&
          systemError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
        finish(nil)
      } else {
        finish(FlutterError(code: "sign_in_failed", message: "Yandex login failed", details: nil))
      }
    }
  }

  private func finish(_ value: Any?) {
    let callback = pendingResult
    pendingResult = nil
    callback?(value)
  }

  func application(_ application: UIApplication, open url: URL,
                   options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    YandexLoginSDK.shared.tryHandleOpenURL(url)
  }

  func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                   restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    YandexLoginSDK.shared.tryHandleUserActivity(userActivity)
  }

  func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) -> Bool {
    for context in contexts where YandexLoginSDK.shared.tryHandleOpenURL(context.url) { return true }
    return false
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    YandexLoginSDK.shared.tryHandleUserActivity(userActivity)
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options: UIScene.ConnectionOptions?) -> Bool {
    guard let options else { return false }
    for activity in options.userActivities where YandexLoginSDK.shared.tryHandleUserActivity(activity) { return true }
    for context in options.urlContexts where YandexLoginSDK.shared.tryHandleOpenURL(context.url) { return true }
    return false
  }
}
