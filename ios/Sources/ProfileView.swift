import SwiftUI
import UIKit

/* "Profil" tab: the guest's name and phone (filled in everywhere automatically) + restaurant news with photos */
struct NewsItem: Identifiable {
    let id: String
    let title: String
    let text: String
    let image: URL?
    let at: Date?
}

final class NewsModel: ObservableObject {
    static let shared = NewsModel()
    @Published var items: [NewsItem] = []
    @Published var loading = false
    @Published var failed = false
    @Published var unseen = false
    private var timer: Timer?
    var visible = false   /* the Profil tab is on screen: new posts count as seen */
    private var started = false

    /* new posts show up by themselves: checked every 45 s while the app is open and whenever it comes back */
    func start() {
        if started { return }; started = true
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in self?.load() }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.load() }
    }
    private var newestKey: String { items.first.map { $0.id + "|" + String($0.at?.timeIntervalSince1970 ?? 0) } ?? "" }
    func markSeen() { if !items.isEmpty { UserDefaults.standard.set(newestKey, forKey: "uno.newsSeen") }; unseen = false }

    func load() {
        guard var c = URLComponents(string: Config.supabaseURL + "/rest/v1/uno_docs") else { return }
        c.queryItems = [URLQueryItem(name: "select", value: "path,data"), URLQueryItem(name: "path", value: "like.news/*")]
        guard let url = c.url else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        if items.isEmpty { loading = true }
        URLSession.shared.dataTask(with: r) { data, resp, err in
            var list: [NewsItem] = []
            var bad = err != nil
            if let data = data, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let iso2 = ISO8601DateFormatter()
                for row in rows {
                    guard let path = row["path"] as? String, let d = row["data"] as? [String: Any] else { continue }
                    if (d["hidden"] as? Bool) == true { continue }
                    func pick(_ k: String) -> String {
                        let loc = (d[k + "_" + L.lang] as? String) ?? ""
                        return loc.isEmpty ? ((d[k] as? String) ?? "") : loc
                    }
                    let img = (d["imgId"] as? String) ?? ""
                    var u: URL? = nil
                    if !img.isEmpty {
                        if img.hasPrefix("http") || img.contains("/") { u = URL(string: img) }
                        else { u = URL(string: Config.supabaseURL + "/storage/v1/object/public/uno-media/" + (img.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? img)) }
                    }
                    let atS = (d["at"] as? String) ?? ""
                    list.append(NewsItem(id: path, title: pick("title"), text: pick("text"), image: u,
                                         at: iso.date(from: atS) ?? iso2.date(from: atS)))
                }
                list.sort { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
            } else { bad = true }
            DispatchQueue.main.async { self.loading = false; self.failed = bad && list.isEmpty; if !bad || !list.isEmpty { self.items = list
                    self.unseen = !list.isEmpty && UserDefaults.standard.string(forKey: "uno.newsSeen") != self.newestKey
                    if self.visible { self.markSeen() } } }
        }.resume()
    }
}

/* the page in the Menu tab reads this to fill name/phone in delivery, reviews… */
enum ProfileBridge {
    static func script() -> String {
        let d = UserDefaults.standard
        let o: [String: String] = ["name": d.string(forKey: "uno.name") ?? "", "phone": d.string(forKey: "uno.phone") ?? ""]
        let json = (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "try{localStorage.setItem('uno_profile', JSON.stringify(\(json)));}catch(e){}"
    }
}

struct ProfileView: View {
    @AppStorage("uno.name") private var name = ""
    @AppStorage("uno.phone") private var phone = "+998 "
    @ObservedObject private var news = NewsModel.shared
    @State private var saved = false
    @FocusState private var focus: Bool

    private var ready: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && phone.filter { $0.isNumber }.count >= 9 }

    var body: some View {
        ZStack {
            UNOSky()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L.t("tab.profile"))
                        .font(.system(size: 34, weight: .bold)).foregroundColor(.white)
                        .padding(.top, 8)

                    /* my details */
                    sectionTitle(L.t("pf.me"))
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [Config.gold.opacity(0.35), Config.gold.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Circle().strokeBorder(Config.gold.opacity(0.55), lineWidth: 1)
                                Text(initials).font(.system(size: 20, weight: .bold)).foregroundColor(Config.gold)
                            }
                            .frame(width: 56, height: 56)
                            VStack(spacing: 10) {
                                glassField(L.t("pf.name"), text: $name, kb: .default, ct: .name)
                                glassField(L.t("book.phone"), text: $phone, kb: .phonePad, ct: .telephoneNumber)
                            }
                        }
                        Button(action: save) {
                            Label(saved ? L.t("pf.saved") : L.t("pf.save"), systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .foregroundColor(ready ? Color(red: 0.1, green: 0.07, blue: 0.02) : Color.white.opacity(0.45))
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(ready ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.54), Color(red: 1, green: 0.79, blue: 0.30)], startPoint: .top, endPoint: .bottom))
                                                    : AnyShapeStyle(Color.white.opacity(0.08)))
                                )
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(ready ? 0 : 0.14), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(!ready)
                    }
                    .glassCard()
                    Text(L.t("pf.hint")).font(.footnote).foregroundColor(Color.white.opacity(0.6)).padding(.horizontal, 6)

                    /* news */
                    HStack {
                        sectionTitle(L.t("pf.news"))
                        Spacer()
                        Button { news.load() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Config.gold).frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    if news.items.isEmpty {
                        HStack {
                            Spacer()
                            if news.loading { ProgressView().tint(Config.gold) }
                            else { Text(news.failed ? L.t("offline.text") : L.t("pf.noNews")).font(.subheadline).foregroundColor(Color.white.opacity(0.6)).multilineTextAlignment(.center) }
                            Spacer()
                        }
                        .padding(.vertical, 26)
                        .glassCard()
                    }
                    ForEach(news.items) { n in newsCard(n) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .modifier(Refresh { news.load() })
        }
        .onAppear { news.start() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L.t("done")) { focus = false }.font(.body.bold()).foregroundColor(Config.gold)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 13, weight: .bold)).kerning(1.2).foregroundColor(Config.gold.opacity(0.9)).padding(.horizontal, 6)
    }

    private func glassField(_ ph: String, text: Binding<String>, kb: UIKeyboardType, ct: UITextContentType) -> some View {
        TextField("", text: text, prompt: Text(ph).foregroundColor(Color.white.opacity(0.4)))
            .keyboardType(kb).textContentType(ct).disableAutocorrection(true).focused($focus)
            .foregroundColor(.white).font(.system(size: 16))
            .padding(.horizontal, 14).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.01, green: 0.03, blue: 0.08).opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }

    /* photo area: 8.5 × 2.8 (wide banner), fills the frame without spilling over */
    private func newsCard(_ n: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let u = n.image {
                Color.clear
                    .aspectRatio(8.5 / 2.8, contentMode: .fit)
                    .overlay(
                        AsyncImage(url: u) { ph in
                            switch ph {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Rectangle().fill(Color.white.opacity(0.06)).overlay(ProgressView().tint(Config.gold))
                            }
                        }
                    )
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 6) {
                if !n.title.isEmpty { Text(n.title).font(.system(size: 18, weight: .bold)).foregroundColor(.white) }
                if !n.text.isEmpty { Text(n.text).font(.subheadline).foregroundColor(Color.white.opacity(0.82)).fixedSize(horizontal: false, vertical: true) }
                if let d = n.at {
                    Label(Self.fmt.string(from: d), systemImage: "calendar").font(.caption).foregroundColor(Config.gold.opacity(0.85))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard(padding: 0)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return s.isEmpty ? "?" : s
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        f.locale = Locale(identifier: L.lang == "uz" ? "uz_Latn_UZ" : L.lang); return f
    }()

    private func save() {
        focus = false
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        NotificationCenter.default.post(name: .unoProfileChanged, object: nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}

extension Notification.Name { static let unoProfileChanged = Notification.Name("unoProfileChanged") }

/* pull to refresh where the system supports it on a ScrollView */
struct Refresh: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) { content.refreshable { action() } } else { content }
    }
}

/* the menu's night sky: deep blue, soft glows and the curve of the earth at the bottom */
struct UNOSky: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, r = max(w, h) * 1.6
            ZStack {
                LinearGradient(colors: [Color(red: 0.008, green: 0.016, blue: 0.047), Color(red: 0.024, green: 0.063, blue: 0.165), Color(red: 0.031, green: 0.086, blue: 0.204)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 0.31, green: 0.43, blue: 1).opacity(0.18), .clear], center: UnitPoint(x: 0.18, y: 0.08), startRadius: 0, endRadius: w * 0.8)
                RadialGradient(colors: [Color(red: 1, green: 0.67, blue: 0.35).opacity(0.10), .clear], center: UnitPoint(x: 0.9, y: 0.16), startRadius: 0, endRadius: w * 0.7)
                /* earth */
                Circle()
                    .fill(Color(red: 0.016, green: 0.035, blue: 0.09))
                    .overlay(Circle().stroke(Color(red: 0.55, green: 0.8, blue: 1), lineWidth: 2).blur(radius: 1))
                    .shadow(color: Color(red: 0.25, green: 0.55, blue: 1).opacity(0.9), radius: 22)
                    .frame(width: r * 2, height: r * 2)
                    .position(x: w / 2, y: h - h * 0.06 + r)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }
}

/* frosted glass card, like the menu's tickets */
struct GlassCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 10)
            .environment(\.colorScheme, .dark)
    }
}
extension View { func glassCard(padding: CGFloat = 16) -> some View { modifier(GlassCard(padding: padding)) } }
