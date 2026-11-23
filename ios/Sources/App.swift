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
    @ObservedObject private var news = NewsModel.shared
    @ObservedObject private var lang = LangStore.shared
    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            let safeB = UNOBar.homeIndicator(geo.safeAreaInsets.bottom)   /* the screen edge, not the keyboard */
            ZStack(alignment: .bottom) {
                page(0) { MenuView() }
                page(1) { BookingView().id(lang.lang).environment(\.locale, L.locale).safeAreaInset(edge: .bottom) { Color.clear.frame(height: UNOBar.height(land)) } }
                page(2) { AboutView().id(lang.lang).environment(\.locale, L.locale).safeAreaInset(edge: .bottom) { Color.clear.frame(height: UNOBar.height(land)) } }
                page(3) { ProfileView().id(lang.lang).environment(\.locale, L.locale).safeAreaInset(edge: .bottom) { Color.clear.frame(height: UNOBar.height(land)) } }
                /* our own floating bar: bigger buttons, nothing behind it, the menu background runs to the very bottom */
                UNOTabBar(tab: $tab, landscape: land, lang: lang.lang, dot: news.unseen && tab != 3 ? 3 : nil)
                    .padding(.bottom, UNOBar.bottomPad(land, safe: safeB))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(.all, edges: .bottom)
                    .ignoresSafeArea(.keyboard, edges: .bottom)   /* stays down behind the keyboard instead of riding on top of it */
            }
        }
        .background(Config.bg.ignoresSafeArea())
        .accentColor(Config.gold)
        .onAppear { news.start(); news.visible = tab == 3 }
        .onChange(of: tab) { t in
            news.visible = t == 3
            if t == 3 { news.load(); news.markSeen() }
        }
        .onChange(of: lang.lang) { _ in news.load() }
    }
    @ViewBuilder private func page<V: View>(_ i: Int, @ViewBuilder _ v: () -> V) -> some View {
        v().opacity(tab == i ? 1 : 0).allowsHitTesting(tab == i).accessibilityHidden(tab != i)
    }
}

/* sizes shared with the menu page (it keeps its footer clear of the bar) */
enum UNOBar {
    /* bottom inset of the screen itself; geo.safeAreaInsets grows by the keyboard's height while it is up */
    static func homeIndicator(_ fallback: CGFloat) -> CGFloat {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        return w?.safeAreaInsets.bottom ?? min(fallback, 34)
    }
    static func height(_ landscape: Bool) -> CGFloat { landscape ? 50 : 62 }
    static func bottomPad(_ landscape: Bool, safe: CGFloat) -> CGFloat { landscape ? 6 : max(8, safe - 12) }
    static func reserved(_ landscape: Bool, safe: CGFloat) -> CGFloat { height(landscape) + bottomPad(landscape, safe: safe) + 6 }
}

struct UNOTabBar: View {
    @Binding var tab: Int
    let landscape: Bool
    var lang: String = L.lang   /* a new value redraws the labels */
    var dot: Int? = nil   /* a small gold dot: something new on that tab */
    private let items: [(String, String)] = [("tab.menu", "fork.knife"), ("tab.book", "calendar.badge.plus"),
                                             ("tab.about", "airplane"), ("tab.profile", "person.crop.circle")]
    var body: some View {
        HStack(spacing: landscape ? 6 : 2) {
            ForEach(items.indices, id: \.self) { i in
                let on = tab == i
                Button {
                    if tab != i { tab = i; UISelectionFeedbackGenerator().selectionChanged() }
                } label: {
                    Group {
                        if landscape {
                            HStack(spacing: 8) {
                                Image(systemName: items[i].1).font(.system(size: 18, weight: .semibold)).overlay(badge(i), alignment: .topTrailing)
                                Text(L.t(items[i].0)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            }
                            .padding(.horizontal, 18)
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: items[i].1).font(.system(size: 20, weight: .semibold)).overlay(badge(i), alignment: .topTrailing)
                                Text(L.t(items[i].0)).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: UNOBar.height(landscape) - 10)
                    .foregroundColor(on ? Config.gold : Color.white.opacity(0.8))
                    .background(Capsule().fill(on ? Color.white.opacity(0.13) : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(5)
        .frame(height: UNOBar.height(landscape))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 6)
        .padding(.horizontal, landscape ? 0 : 14)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.18), value: tab)
    }
    @ViewBuilder private func badge(_ i: Int) -> some View {
        if dot == i {
            Circle().fill(Color(red: 1, green: 0.32, blue: 0.3)).frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1.5))
                .offset(x: 5, y: -3)
        }
    }
}
