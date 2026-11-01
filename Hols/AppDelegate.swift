import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let web = WebViewController()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // calls and voice messages keep playing with the silent switch on and in the background
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default,
                                                         options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = WebViewController.background
        w.rootViewController = web
        w.makeKeyAndVisible()
        window = w
        if let url = launchOptions?[.url] as? URL { web.open(external: url) }
        return true
    }

    /// hols://username, hols://+invite, hols://Wallet?start=CODE → the same path on the site
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        web.open(external: url)
        return true
    }

    /// https://hols-chat.ru/... links (Universal Links, when the associated domain is configured)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if let url = userActivity.webpageURL { web.open(external: url); return true }
        return false
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
    }
}
