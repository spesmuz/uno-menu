import SwiftUI
import UIKit
import UserNotifications

enum Config {
    static let siteURL = URL(string: "https://spesmuz.github.io/uno-menu/")!
    static let privacyURL = URL(string: "https://spesmuz.github.io/uno-menu/privacy.html")!
    static let supabaseURL = "https://eaxavnixuqgwashplnhz.supabase.co"
    static let supabaseKey = "sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril"
    static let phone = "+998918816979"
    static let phonePretty = "+998 91 881 69 79"
    static let instagram = "uno_airways_restaurante"
    static let address = "Farg'ona sh., Sohibqiron Temur ko'chasi, 30"
    static let gold = Color(red: 0xE8 / 255, green: 0xB0 / 255, blue: 0x4B / 255)
    static let bg = Color(red: 0x0E / 255, green: 0x0F / 255, blue: 0x12 / 255)
    static let card = Color(red: 0x1A / 255, green: 0x1B / 255, blue: 0x20 / 255)
    static let uiBg = UIColor(red: 0x0E / 255, green: 0x0F / 255, blue: 0x12 / 255, alpha: 1)
    static let uiGold = UIColor(red: 0xE8 / 255, green: 0xB0 / 255, blue: 0x4B / 255, alpha: 1)
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        /* see-through tab bar: the menu background runs to the bottom edge */
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        if #available(iOS 26.0, *) { } else {
            tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            tab.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        }
        tab.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) { UITabBar.appearance().scrollEdgeAppearance = tab }
        UITabBar.appearance().tintColor = Config.uiGold
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.55)
        return true
    }
    /* show the booking reminder even while the app is open */
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct UNOAirwaysApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.dark).statusBarHidden(true).fullScreenOverlays() }
    }
}

/* full screen: no clock / battery bar, home line fades out */
extension View {
    @ViewBuilder func fullScreenOverlays() -> some View {
        if #available(iOS 16.0, *) { self.persistentSystemOverlays(.hidden) } else { self }
    }
}

struct RootView: View {
    @State private var tab: Int = {
        /* screenshots in CI open a chosen tab: -tab 1 */
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-tab"), i + 1 < a.count, let n = Int(a[i + 1]) { return n }
        return 0
    }()
    var body: some View {
        TabView(selection: $tab) {
            MenuView()
                .tabItem { Label(L.t("tab.menu"), systemImage: "fork.knife") }
                .tag(0)
            BookingView()
                .tabItem { Label(L.t("tab.book"), systemImage: "calendar.badge.plus") }
                .tag(1)
            AboutView()
                .tabItem { Label(L.t("tab.about"), systemImage: "airplane") }
                .tag(2)
        }
        .accentColor(Config.gold)
        .onChange(of: tab) { _ in UISelectionFeedbackGenerator().selectionChanged() }
    }
}
