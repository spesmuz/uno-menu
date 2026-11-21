import SwiftUI
import UIKit
import UserNotifications

struct Booking: Codable, Identifiable {
    var id: Int
    var at: Date
    var guests: Int
    var zone: String
    var occasion: String
}

enum BookingStore {
    private static let key = "uno.bookings"
    static func load() -> [Booking] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let l = try? JSONDecoder().decode([Booking].self, from: d) else { return [] }
        return l
    }
    static func save(_ l: [Booking]) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: key) }
    }
}

enum BookingError: Error { case server(String), network }

enum BookingAPI {
    /* sends the booking to the restaurant (Supabase → Telegram group of the operators) */
    static func send(name: String, phone: String, at: Date, guests: Int, zone: String?, occasion: String?, note: String,
                     done: @escaping (Result<Int, BookingError>) -> Void) {
        guard let url = URL(string: Config.supabaseURL + "/rest/v1/rpc/uno_booking_create") else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["p_name": name, "p_phone": phone, "p_at": iso.string(from: at), "p_guests": guests,
                                   "p_note": note, "p_source": "ios"]
        if let z = zone { body["p_zone"] = z }
        if let o = occasion { body["p_occasion"] = o }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var result: Result<Int, BookingError> = .failure(.network)
            if err == nil, let data = data {
                let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                if (200..<300).contains(code) { result = .success((j?["id"] as? Int) ?? 0) }
                else { result = .failure(.server((j?["message"] as? String) ?? "")) }
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }
}

struct BookingView: View {
    private static let zones = ["z.any", "z.family", "z.comfort", "z.business", "z.terrace", "z.vip", "z.conf"]
    private static let occasions = ["o.visit", "o.bday", "o.wedding", "o.conf", "o.meeting"]

    @AppStorage("uno.name") private var name = ""
    @AppStorage("uno.phone") private var phone = "+998 "
    @State private var date = BookingView.defaultDate()
    @State private var guests = 2
    @State private var zone = 0
    @State private var occasion = 0
    @State private var note = ""
    @AppStorage("uno.remind") private var remind = true
    @State private var sending = false
    @State private var alert: AlertInfo?
    @State private var mine = BookingStore.load()

    struct AlertInfo: Identifiable { let id = UUID(); let title: String; let text: String; let ok: Bool }

    static func defaultDate() -> Date {
        /* next round half hour, at least one hour from now */
        let cal = Calendar.current
        let d = Date().addingTimeInterval(3600)
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let m = c.minute ?? 0
        c.minute = m == 0 ? 0 : (m <= 30 ? 30 : 0)
        c.second = 0
        var r = cal.date(from: c) ?? d
        if m > 30 { r = r.addingTimeInterval(3600) }
        return r
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(L.t("book.guest"))) {
                    TextField(L.t("book.name"), text: $name)
                        .textContentType(.name)
                        .disableAutocorrection(true)
                    TextField(L.t("book.phone"), text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                Section(header: Text(L.t("book.when"))) {
                    DatePicker(L.t("book.date"), selection: $date,
                               in: Date()...Date().addingTimeInterval(180 * 86400))
                        .accentColor(Config.gold)
                    Stepper(value: $guests, in: 1...350) {
                        HStack {
                            Text(L.t("book.guests"))
                            Spacer()
                            Text("\(guests)").bold().foregroundColor(Config.gold)
                        }
                    }
                    Picker(L.t("book.zone"), selection: $zone) {
                        ForEach(0..<Self.zones.count, id: \.self) { Text(L.t(Self.zones[$0])).tag($0) }
                    }
                    Picker(L.t("book.occasion"), selection: $occasion) {
                        ForEach(0..<Self.occasions.count, id: \.self) { Text(L.t(Self.occasions[$0])).tag($0) }
                    }
                    TextField(L.t("book.note"), text: $note)
                    Toggle(L.t("book.remind"), isOn: $remind).tint(Config.gold)
                }
                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if sending { ProgressView().tint(.black) }
                            else { Label(L.t("book.send"), systemImage: "checkmark.circle.fill").font(.headline) }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .disabled(sending)
                    .listRowBackground(Config.gold)
                    .foregroundColor(.black)
                }
                Section(header: Text(L.t("book.call")), footer: Text(L.t("book.call24"))) {
                    Button(action: callUs) {
                        Label(Config.phonePretty, systemImage: "phone.fill").foregroundColor(Config.gold)
                    }
                }
                if !upcoming.isEmpty {
                    Section(header: Text(L.t("book.mine"))) {
                        ForEach(upcoming) { b in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.fmt.string(from: b.at)).font(.headline)
                                Text("\(b.guests) \(L.t("book.people")) · \(L.t(b.zone)) · \(L.t(b.occasion))")
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { idx in
                            let ids = idx.map { upcoming[$0].id }
                            mine.removeAll { ids.contains($0.id) }
                            BookingStore.save(mine)
                            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids.map { "uno.booking.\($0)" })
                        }
                    }
                }
            }
            .navigationTitle(L.t("book.title"))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("done")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.font(.body.bold()).foregroundColor(Config.gold)
                }
            }
            .alert(item: $alert) { a in
                if a.ok { return Alert(title: Text(a.title), message: Text(a.text), dismissButton: .default(Text(L.t("ok")))) }
                return Alert(title: Text(a.title), message: Text(a.text),
                             primaryButton: .default(Text(L.t("callNow")), action: callUs),
                             secondaryButton: .cancel(Text(L.t("ok"))))
            }
        }
        .navigationViewStyle(.stack)
    }

    private var upcoming: [Booking] { mine.filter { $0.at > Date().addingTimeInterval(-3 * 3600) }.sorted { $0.at < $1.at } }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        f.locale = Locale(identifier: L.lang == "uz" ? "uz_Latn_UZ" : L.lang); return f
    }()

    private func callUs() {
        if let u = URL(string: "tel://" + Config.phone) { UIApplication.shared.open(u) }
    }

    private func submit() {
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = phone.filter { $0.isNumber }
        if nm.count < 2 { alert = AlertInfo(title: L.t("book.err.t"), text: L.t("book.err.name"), ok: true); return }
        if digits.count < 9 { alert = AlertInfo(title: L.t("book.err.t"), text: L.t("book.err.phone"), ok: true); return }
        if date < Date() { alert = AlertInfo(title: L.t("book.err.t"), text: L.t("book.err.time"), ok: true); return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sending = true
        let zKey = Self.zones[zone], oKey = Self.occasions[occasion]
        /* the restaurant always gets the Uzbek names */
        let zTxt = zone == 0 ? nil : L.d["uz"]?[zKey]
        let oTxt = L.d["uz"]?[oKey]
        let when = date, people = guests
        BookingAPI.send(name: nm, phone: phone, at: when, guests: people, zone: zTxt, occasion: oTxt, note: note) { res in
            sending = false
            switch res {
            case .success(let id):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let b = Booking(id: id, at: when, guests: people, zone: zKey, occasion: oKey)
                mine.append(b); BookingStore.save(mine)
                if remind { scheduleReminder(b) }
                note = ""
                alert = AlertInfo(title: L.t("book.ok.t"), text: L.t("book.ok"), ok: true)
            case .failure(let e):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                var text = L.t("book.err")
                if case .server(let m) = e {
                    if m.contains("bad_phone") { text = L.t("book.err.phone") }
                    else if m.contains("bad_name") { text = L.t("book.err.name") }
                    else if m.contains("bad_time") { text = L.t("book.err.time") }
                    else if m.contains("too_many") { text = L.t("book.err.many") }
                }
                alert = AlertInfo(title: L.t("book.err.t"), text: text, ok: false)
            }
        }
    }

    private func scheduleReminder(_ b: Booking) {
        let fire = b.at.addingTimeInterval(-2 * 3600)
        guard fire > Date().addingTimeInterval(60) else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = L.t("remind.title")
            let tf = DateFormatter(); tf.dateFormat = "HH:mm"
            c.body = String(format: L.t("remind.body"), tf.string(from: b.at))
            c.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let req = UNNotificationRequest(identifier: "uno.booking.\(b.id)", content: c,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(req)
        }
    }
}
