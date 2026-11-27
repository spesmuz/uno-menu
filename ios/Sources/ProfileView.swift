import SwiftUI
import UIKit
import PhotosUI
import UserNotifications

/* "Profil" tab: the guest's name and phone (filled in everywhere automatically) + restaurant news with photos */
struct NewsItem: Identifiable, Equatable {
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
    var active = true     /* app in the foreground: only then the timer asks the server */
    private var started = false

    /* new posts show up by themselves: checked every 2 minutes while the app is open and whenever it comes back */
    func start() {
        if started { return }; started = true
        load()
        let t = Timer(timeInterval: 120, repeats: true) { [weak self] _ in if self?.active == true { self?.load() } }
        t.tolerance = 20          /* lets iOS bundle the wake-up with others: less battery */
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.load() }
    }
    private var newestKey: String { items.first.map { $0.id + "|" + String($0.at?.timeIntervalSince1970 ?? 0) } ?? "" }
    func markSeen() { if !items.isEmpty { UserDefaults.standard.set(newestKey, forKey: "uno.newsSeen") }; if unseen { unseen = false } }

    func load() {
        guard var c = URLComponents(string: Config.supabaseURL + "/rest/v1/uno_docs") else { return }
        c.queryItems = [URLQueryItem(name: "select", value: "path,data"), URLQueryItem(name: "path", value: "like.news/*")]
        guard let url = c.url else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        if items.isEmpty && !loading { loading = true }
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
            /* only real changes are published: every publish redraws all four tabs */
            DispatchQueue.main.async {
                if self.loading { self.loading = false }
                let f = bad && list.isEmpty
                if self.failed != f { self.failed = f }
                if !bad || !list.isEmpty {
                    if self.items != list { self.items = list }
                    let u = !list.isEmpty && UserDefaults.standard.string(forKey: "uno.newsSeen") != self.newestKey
                    if self.unseen != u { self.unseen = u }
                    if self.visible { self.markSeen() }
                }
            }
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
    @AppStorage("uno.bday") private var bday = ""          /* YYYY-MM-DD, empty = not given */
    @AppStorage("uno.bdayLocked") private var bdayLocked = false   /* saved on the server: only the restaurant can change it */
    @ObservedObject private var news = NewsModel.shared
    @State private var photo: UIImage? = nil
    @State private var photoRead = false
    @State private var picking = false
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
                            Menu {
                                Button { picking = true } label: { Label(photo == nil ? L.t("pf.photo") : L.t("pf.photoChange"), systemImage: "photo.on.rectangle") }
                                if photo != nil {
                                    Button(role: .destructive) { setPhoto(nil) } label: { Label(L.t("pf.photoDel"), systemImage: "trash") }
                                }
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    ZStack {
                                        Circle().fill(LinearGradient(colors: [Config.gold.opacity(0.35), Config.gold.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        if let p = photo { Image(uiImage: p).resizable().scaledToFill() }
                                        else { Text(initials).font(.system(size: 24, weight: .bold)).foregroundColor(Config.gold) }
                                    }
                                    .frame(width: 76, height: 76)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Config.gold.opacity(0.6), lineWidth: 1.5))
                                    Image(systemName: "camera.fill").font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 0.1, green: 0.07, blue: 0.02))
                                        .frame(width: 26, height: 26)
                                        .background(Circle().fill(Config.gold))
                                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                                }
                            }
                            VStack(spacing: 10) {
                                glassField(L.t("pf.name"), text: $name, kb: .default, ct: .name)
                                glassField(L.t("book.phone"), text: $phone, kb: .phonePad, ct: .telephoneNumber)
                            }
                        }
                        bdayRow
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
        .onAppear {
            news.start(); CustomerAPI.syncOnLaunch()
            if !photoRead { photoRead = true; photo = CustomerAPI.localPhoto() }
            refreshBday()
        }
        .sheet(isPresented: $picking) { PhotoPicker { img in if let img = img { setPhoto(img) } } }
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

    static var fmt: DateFormatter { L.dateFormatter(time: false) }

    private func setPhoto(_ img: UIImage?) {
        photo = img.map { CustomerAPI.square($0, side: 360) }
        CustomerAPI.storeLocal(photo)
        if ready { CustomerAPI.sync(name: name, phone: phone, photoChanged: true) }
    }

    /* birthday: the guest gives it once; a week before it the restaurant's offer arrives as a notification */
    private static let isoDay: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    private var bdayDate: Binding<Date> {
        Binding(get: { ProfileView.isoDay.date(from: bday) ?? (Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? Date()) },
                set: { bday = ProfileView.isoDay.string(from: $0) })
    }
    private var bdayRange: ClosedRange<Date> {
        (Calendar.current.date(from: DateComponents(year: 1920, month: 1, day: 1)) ?? Date.distantPast)...Date()
    }
    private var bdayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("🎂 " + L.t("pf.bday")).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Spacer(minLength: 6)
                if bdayLocked && !bday.isEmpty {
                    Text(ProfileView.longDay(bday)).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Image(systemName: "lock.fill").font(.system(size: 13)).foregroundColor(Color.white.opacity(0.45))
                } else if bday.isEmpty {
                    Button { bday = ProfileView.isoDay.string(from: bdayDate.wrappedValue) } label: {
                        Text(L.t("pf.bdayAdd")).font(.system(size: 14, weight: .bold)).foregroundColor(Config.gold)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Capsule().fill(Config.gold.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Config.gold.opacity(0.45), lineWidth: 1))
                    }.buttonStyle(.plain)
                } else {
                    DatePicker("", selection: bdayDate, in: bdayRange, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact).colorScheme(.dark).environment(\.locale, L.locale)
                    Button { bday = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(Color.white.opacity(0.4)) }
                        .buttonStyle(.plain)
                }
            }
            if bdayLocked && !bday.isEmpty {
                Text(L.t("pf.bdayLocked")).font(.footnote).foregroundColor(Color.white.opacity(0.6))
            } else {
                Text((bday.isEmpty ? L.t("pf.bdayHint") + " " : "") + L.t("pf.bdayOnce")).font(.footnote).foregroundColor(Color.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    /* the server keeps the date per phone number: show what it has (also after a reinstall) */
    private func refreshBday() {
        guard ready else { return }
        CustomerAPI.myBirthday { v in
            guard let v = v else { return }          /* no answer: keep what we have */
            if let d = v { bday = d; bdayLocked = true }
            else if bdayLocked { bday = ""; bdayLocked = false }   /* the restaurant cleared it: may be entered again */
        }
    }
    static func longDay(_ iso: String) -> String {
        guard let d = isoDay.date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .none; f.locale = L.locale
        return f.string(from: d)
    }

    private func save() {
        let b = bdayLocked ? "" : bday
        CustomerAPI.sync(name: name.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines), photoChanged: true) {
            if !b.isEmpty {
                CustomerAPI.birthday(b) { server in
                    DispatchQueue.main.async {
                        if let s = server { bday = s; bdayLocked = true; CustomerAPI.scheduleBirthday(s) } else { refreshBday() }
                    }
                }
            } else { DispatchQueue.main.async { refreshBday() } }
        }
        CustomerAPI.scheduleBirthday(b)
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
            .drawingGroup()      /* drawn once into a single bitmap; the big glow is not re-blurred while scrolling */
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
            .environment(\.colorScheme, .dark)
    }
}
extension View { func glassCard(padding: CGFloat = 16) -> some View { modifier(GlassCard(padding: padding)) } }


/* the guest's profile also goes to the restaurant (admin → "Mijozlar") */
enum CustomerAPI {
    static var device: String {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "uno.device"), !v.isEmpty { return v }
        let v = UUID().uuidString; d.set(v, forKey: "uno.device"); return v
    }
    private static var photoURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile.jpg") }
    static func localPhoto() -> UIImage? { (try? Data(contentsOf: photoURL)).flatMap { UIImage(data: $0) } }
    static func storeLocal(_ img: UIImage?) {
        if let img = img, let data = img.jpegData(compressionQuality: 0.8) { try? data.write(to: photoURL) }
        else { try? FileManager.default.removeItem(at: photoURL) }
    }
    /* centre-cropped square, small enough to travel as text */
    static func square(_ img: UIImage, side: CGFloat) -> UIImage {
        let s = min(img.size.width, img.size.height)
        let k = side / s
        let size = CGSize(width: side, height: side)
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            img.draw(in: CGRect(x: (side - img.size.width * k) / 2, y: (side - img.size.height * k) / 2, width: img.size.width * k, height: img.size.height * k))
        }
    }
    private static var launched = false
    static func syncOnLaunch() {
        if launched { return }; launched = true
        let d = UserDefaults.standard
        let n = d.string(forKey: "uno.name") ?? "", p = d.string(forKey: "uno.phone") ?? ""
        if n.trimmingCharacters(in: .whitespaces).count >= 2 && p.filter({ $0.isNumber }).count >= 9 && !d.bool(forKey: "uno.custSynced") {
            sync(name: n, phone: p, photoChanged: true)
        }
    }
    /* birthday to the restaurant (admin → "Tug'ilgan kunlar"); needs growth.sql */
    static func birthday(_ iso: String, done: ((String?) -> Void)? = nil) {
        guard let url = URL(string: Config.supabaseURL + "/rest/v1/rpc/uno_customer_extra") else { return }
        var r = URLRequest(url: url, timeoutInterval: 25)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["p_device": device, "p_birthday": iso])
        /* answer: the date the server keeps (an earlier one if it was already given: "bday_locked") */
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            let ok = ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300
            let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            done?(ok ? (j?["birthday"] as? String) : nil)
        }.resume()
    }
    /* nil = no answer; .some(nil) = no date on the server; .some(date) = the locked date */
    static func myBirthday(_ done: @escaping (String??) -> Void) {
        guard let url = URL(string: Config.supabaseURL + "/rest/v1/rpc/uno_my_birthday") else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["p_device": device])
        URLSession.shared.dataTask(with: r) { data, resp, err in
            var out: String?? = nil
            if err == nil, ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300, let data = data,
               let v = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                if let s = v as? String, s.count == 10 { out = .some(s) } else if v is NSNull { out = .some(nil) }
            }
            DispatchQueue.main.async { done(out) }
        }.resume()
    }
    /* a week before the birthday at 11:00, every year - only when the admin turned the birthday offer on */
    static func scheduleBirthday(_ iso: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["uno.bday"])
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return }
        var c = URLComponents(string: Config.supabaseURL + "/rest/v1/uno_docs")!
        c.queryItems = [URLQueryItem(name: "select", value: "data"), URLQueryItem(name: "path", value: "eq.settings/main")]
        guard let url = c.url else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, _, _ in
            guard let data = data, let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let d = rows.first?["data"] as? [String: Any], let g = d["grow"] as? [String: Any], (g["bdayOn"] as? Bool) == true else { return }
            let lang = L.lang
            var text = (lang != "uz" ? g["bdayText_" + lang] as? String : nil) ?? ""
            if text.isEmpty { text = (g["bdayText"] as? String) ?? "" }
            if text.isEmpty { text = L.t("bd.def") }
            /* the day 7 days before the birthday, as month/day (repeats yearly) */
            let cal = Calendar(identifier: .gregorian)
            guard let bd = cal.date(from: DateComponents(year: 2001, month: p[1], day: p[2])), let wk = cal.date(byAdding: .day, value: -7, to: bd) else { return }
            var dc = cal.dateComponents([.month, .day], from: wk); dc.hour = 11; dc.minute = 0
            let content = UNMutableNotificationContent()
            content.title = L.t("bd.push"); content.body = text; content.sound = .default
            center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                guard ok else { return }
                center.add(UNNotificationRequest(identifier: "uno.bday", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
            }
        }.resume()
    }
    static func sync(name: String, phone: String, photoChanged: Bool, then: (() -> Void)? = nil) {
        guard let url = URL(string: Config.supabaseURL + "/rest/v1/rpc/uno_customer_save") else { return }
        var body: [String: Any] = ["p_device": device, "p_name": name, "p_phone": phone, "p_platform": "ios", "p_lang": L.lang]
        if photoChanged {
            if let img = localPhoto(), let data = img.jpegData(compressionQuality: 0.72) { body["p_photo"] = "data:image/jpeg;base64," + data.base64EncodedString() }
            else { body["p_photo"] = "" }
        }
        var r = URLRequest(url: url, timeoutInterval: 25)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            if let h = resp as? HTTPURLResponse, (200..<300).contains(h.statusCode) { UserDefaults.standard.set(true, forKey: "uno.custSynced"); then?() }
        }.resume()
    }
}

/* photo library picker (works from iOS 14, no permission prompt needed) */
struct PhotoPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var c = PHPickerConfiguration(); c.filter = .images; c.selectionLimit = 1
        let p = PHPickerViewController(configuration: c); p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let done: (UIImage?) -> Void
        init(_ d: @escaping (UIImage?) -> Void) { done = d }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let p = results.first?.itemProvider, p.canLoadObject(ofClass: UIImage.self) else { done(nil); return }
            p.loadObject(ofClass: UIImage.self) { obj, _ in DispatchQueue.main.async { self.done(obj as? UIImage) } }
        }
    }
}
