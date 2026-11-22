import SwiftUI
import WebKit
import UIKit

/* The live UNO menu (photos, videos, prices — always current, managed from the admin panel) */
struct MenuView: View {
    @StateObject private var model = WebModel()
    var body: some View {
        ZStack {
            Config.bg.ignoresSafeArea()
            WebView(model: model).ignoresSafeArea()   /* full screen; the page keeps its header/footer clear of the clock and the tab bar (insets sent from here) */
            if model.loading && !model.failed {
                VStack(spacing: 18) {
                    Image("Logo").resizable().scaledToFit().frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    ProgressView().tint(Config.gold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Config.bg.ignoresSafeArea())
                .transition(.opacity)
            }
            if model.failed {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.slash").font(.system(size: 44)).foregroundColor(Config.gold)
                    Text(L.t("offline.title")).font(.title3.bold())
                    Text(L.t("offline.text")).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button(action: { model.reload() }) {
                        Text(L.t("retry")).bold().padding(.horizontal, 28).padding(.vertical, 12)
                            .background(Config.gold).foregroundColor(.black).clipShape(Capsule())
                    }.padding(.top, 6)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Config.bg.ignoresSafeArea())
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.loading)
    }
}

final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var loading = true
    @Published var failed = false
    weak var web: WKWebView?
    var loc: LocationBridge?
    private var loadedOnce = false

    func reload() {
        failed = false; loading = true
        if let w = web {
            if w.url == nil { w.load(URLRequest(url: Config.siteURL)) } else { w.reload() }
        }
    }

    /* show the menu as soon as the page starts drawing, without waiting for every photo and video */
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        (webView as? InsetWebView)?.resend()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, !self.failed else { return }
            self.loadedOnce = true; self.loading = false
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        (webView as? InsetWebView)?.resend()
        loadedOnce = true; loading = false; failed = false
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        let e = error as NSError
        if e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return }   /* frame load interrupted (handled link) */
        loading = false
        if !loadedOnce { failed = true }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    /* our site stays inside; phone, maps, Instagram, Telegram and other sites open in their own apps */
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "about" || scheme == "blob" || scheme == "data" { decisionHandler(.allow); return }
        if (scheme == "https" || scheme == "http") && url.host == Config.siteURL.host
            && url.path.hasPrefix(Config.siteURL.path) && navigationAction.targetFrame != nil {
            decisionHandler(.allow); return
        }
        if navigationAction.targetFrame?.isMainFrame == false && (scheme == "https" || scheme == "http") {
            decisionHandler(.allow); return     /* embedded frames */
        }
        decisionHandler(.cancel)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    /* target=_blank links */
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.host == Config.siteURL.host { webView.load(navigationAction.request) }
            else { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
        }
        return nil
    }
}

/* tells the page how much of the screen the clock (top) and the tab bar + home line (bottom) cover */
final class InsetWebView: WKWebView {
    private var sent = UIEdgeInsets(top: -1, left: -1, bottom: -1, right: -1)
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let win = window else { return }
        var top = win.safeAreaInsets.top
        var bottom = win.safeAreaInsets.bottom
        let left = win.safeAreaInsets.left, right = win.safeAreaInsets.right
        if let tab = Self.tabBar(in: win.rootViewController), !tab.isHidden {
            let f = tab.convert(tab.bounds, to: self)
            bottom = max(bottom, bounds.maxY - f.minY)
        }
        top = max(0, top); bottom = max(0, bottom)
        if abs(top - sent.top) < 0.5 && abs(bottom - sent.bottom) < 0.5 && abs(left - sent.left) < 0.5 && abs(right - sent.right) < 0.5 { return }
        sent = UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        evaluateJavaScript("window.UNO_INSETS={t:\(Int(top.rounded())),b:\(Int(bottom.rounded())),l:\(Int(left.rounded())),r:\(Int(right.rounded()))};window.dispatchEvent(new Event('resize'));", completionHandler: nil)
    }
    func resend() { sent = UIEdgeInsets(top: -1, left: -1, bottom: -1, right: -1); setNeedsLayout() }
    static func tabBar(in vc: UIViewController?) -> UITabBar? {
        guard let vc = vc else { return nil }
        if let t = vc as? UITabBarController { return t.tabBar }
        for c in vc.children { if let t = tabBar(in: c) { return t } }
        if let p = vc.presentedViewController { return tabBar(in: p) }
        return nil
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebModel
    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []          /* dish videos play by themselves */
        c.applicationNameForUserAgent = "UNOAirwaysApp/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")
        c.websiteDataStore = .default()
        if #available(iOS 14.0, *) { c.limitsNavigationsToAppBoundDomains = true }   /* enables offline cache (service worker) */
        let loc = LocationBridge()
        c.userContentController.add(loc, name: "unoLocate")
        let w = InsetWebView(frame: .zero, configuration: c)
        loc.web = w
        model.loc = loc
        w.navigationDelegate = model
        w.uiDelegate = model
        w.isOpaque = false
        w.backgroundColor = Config.uiBg
        w.scrollView.backgroundColor = Config.uiBg
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.scrollView.bounces = false
        w.allowsBackForwardNavigationGestures = false
        w.allowsLinkPreview = false
        if #available(iOS 16.4, *) { w.isInspectable = false }
        model.web = w
        w.load(URLRequest(url: Config.siteURL))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
