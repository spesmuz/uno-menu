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
    @Published var items: [NewsItem] = []
    @Published var loading = false
    @Published var failed = false

    func load() {
        guard var c = URLComponents(string: Config.supabaseURL + "/rest/v1/uno_docs") else { return }
        c.queryItems = [URLQueryItem(name: "select", value: "path,data"), URLQueryItem(name: "path", value: "like.news/*")]
        guard let url = c.url else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        loading = true
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
            DispatchQueue.main.async { self.loading = false; self.failed = bad && list.isEmpty; if !bad || !list.isEmpty { self.items = list } }
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
    @StateObject private var news = NewsModel()
    @State private var saved = false
    @FocusState private var focus: Bool

    private var ready: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && phone.filter { $0.isNumber }.count >= 9 }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text(L.t("pf.me")), footer: Text(L.t("pf.hint"))) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Config.gold.opacity(0.18)).frame(width: 52, height: 52)
                            Text(initials).font(.headline).foregroundColor(Config.gold)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L.t("pf.name"), text: $name)
                                .textContentType(.name).disableAutocorrection(true).focused($focus)
                            TextField(L.t("book.phone"), text: $phone)
                                .keyboardType(.phonePad).textContentType(.telephoneNumber).focused($focus)
                        }
                    }
                    .padding(.vertical, 4)
                    Button(action: save) {
                        HStack {
                            Spacer()
                            Label(saved ? L.t("pf.saved") : L.t("pf.save"), systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!ready)
                    .foregroundColor(ready ? .black : .secondary)
                    .listRowBackground(ready ? Config.gold : Config.card)
                }

                Section(header: Text(L.t("pf.news"))) {
                    if news.items.isEmpty {
                        HStack {
                            Spacer()
                            if news.loading { ProgressView().tint(Config.gold) }
                            else { Text(news.failed ? L.t("offline.text") : L.t("pf.noNews")).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center) }
                            Spacer()
                        }.padding(.vertical, 24)
                    }
                    ForEach(news.items) { n in
                        VStack(alignment: .leading, spacing: 10) {
                            if let u = n.image {
                                AsyncImage(url: u) { ph in
                                    switch ph {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: Rectangle().fill(Config.card).overlay(ProgressView().tint(Config.gold))
                                    }
                                }
                                .frame(maxWidth: .infinity).frame(height: 210).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            if !n.title.isEmpty { Text(n.title).font(.headline) }
                            if !n.text.isEmpty { Text(n.text).font(.subheadline).foregroundColor(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
                            if let d = n.at { Text(Self.fmt.string(from: d)).font(.caption).foregroundColor(.secondary) }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L.t("tab.profile"))
            .refreshable { news.load() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("done")) { focus = false }.font(.body.bold()).foregroundColor(Config.gold)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { if news.items.isEmpty { news.load() } }
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
