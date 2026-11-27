import SwiftUI
import UIKit

/* Birthday gift in the Profile tab: a shiny box that opens (with fireworks) only on the guest's birthday.
   The server decides "today is the birthday" by the Tashkent date and the locked birthday, so changing the phone's date does not open it. */
struct BdayGift: Equatable {
    var on = false
    var has = false
    var open = false
    var days = 0
    var birthday = ""
    var today = ""
    var text = ""
    var name = ""
}

extension CustomerAPI {
    static func bdayGift(_ done: @escaping (BdayGift?) -> Void) {
        guard let url = URL(string: Config.supabaseURL + "/rest/v1/rpc/uno_bday_gift") else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + Config.supabaseKey, forHTTPHeaderField: "Authorization")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["p_device": device, "p_lang": L.lang])
        URLSession.shared.dataTask(with: r) { data, resp, err in
            var out: BdayGift? = nil
            if err == nil, ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300, let data = data,
               let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                var g = BdayGift()
                g.on = (j["on"] as? Bool) ?? false
                g.has = (j["has"] as? Bool) ?? false
                g.open = (j["open"] as? Bool) ?? false
                g.days = (j["days"] as? Int) ?? 0
                g.birthday = (j["birthday"] as? String) ?? ""
                g.today = (j["today"] as? String) ?? ""
                g.text = (j["text"] as? String) ?? ""
                g.name = (j["name"] as? String) ?? ""
                out = g
            }
            DispatchQueue.main.async { done(out) }
        }.resume()
    }
}

struct GiftCard: View {
    let g: BdayGift
    let opened: Bool
    let guestName: String
    var onOpen: () -> Void

    @State private var anim = false
    @State private var shake: CGFloat = 0
    @State private var lidOff = false

    private let wine = Color(red: 0.71, green: 0.07, blue: 0.31)

    var body: some View {
        VStack(spacing: 8) {
            if opened && g.open { revealed } else { closed }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { anim = true } }
    }

    private var background: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 1, green: 0.69, blue: 0.23), Color(red: 1, green: 0.31, blue: 0.43), Color(red: 0.48, green: 0.18, blue: 0.97)],
                           center: .top, startRadius: 0, endRadius: 420)
            /* confetti dots, drawn once */
            Canvas { ctx, size in
                let cols: [Color] = [.white.opacity(0.4), Color(red: 1, green: 0.88, blue: 0.54).opacity(0.7), Color(red: 0.49, green: 0.96, blue: 1).opacity(0.5)]
                var seed: UInt64 = 7
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
                for i in 0..<70 {
                    let x = rnd() * size.width, y = rnd() * size.height, r = 1.4 + rnd() * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(cols[i % 3]))
                }
            }
        }
        .drawingGroup()
    }

    @ViewBuilder private var closed: some View {
        Text(L.t("bg.title")).font(.system(size: 21, weight: .heavy)).foregroundColor(.white)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        Button(action: tap) {
            GiftBox(anim: anim, lidOff: lidOff, ready: g.open && g.has)
                .frame(width: 156, height: 150)
                .modifier(Shake(amount: shake))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("bg.title"))
        if !g.has {
            sub(L.t("bg.need"))
        } else if g.open {
            sub(L.t("bg.tap")).font(.system(size: 15, weight: .bold))
        } else {
            sub(L.t("bg.lock"))
            if g.days > 0 {
                Text("⏳ " + String(format: L.t("bg.days"), "\(g.days)"))
                    .font(.system(size: 14, weight: .heavy)).foregroundColor(Color(red: 1, green: 0.88, blue: 0.54))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.25)))
            }
        }
    }

    @ViewBuilder private var revealed: some View {
        Text("🎉").font(.system(size: 46))
        Text(L.t("bg.happy") + (firstName.isEmpty ? "" : ", " + firstName) + "!")
            .font(.system(size: 21, weight: .heavy)).foregroundColor(.white).multilineTextAlignment(.center)
        Text(g.text.isEmpty ? L.t("bd.def") : g.text)
            .font(.system(size: 18, weight: .heavy)).foregroundColor(wine).multilineTextAlignment(.center)
            .padding(12).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.95)))
        Text("\(L.t("bg.today")): \(Self.dmy(g.today)) · 🎂 \(Self.dmy(g.birthday))")
            .font(.system(size: 14, weight: .heavy)).foregroundColor(Color(red: 1, green: 0.88, blue: 0.54))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.25)))
        sub(L.t("bg.show"))
    }

    private func sub(_ t: String) -> Text {
        Text(t).font(.subheadline).foregroundColor(Color.white.opacity(0.95))
    }

    private var firstName: String {
        let n = guestName.isEmpty ? g.name : guestName
        return n.split(separator: " ").first.map(String.init) ?? ""
    }

    static func dmy(_ iso: String) -> String {
        let p = iso.prefix(10).split(separator: "-")
        return p.count == 3 ? "\(p[2]).\(p[1]).\(p[0])" : iso
    }

    private func tap() {
        if g.open && g.has {
            if lidOff { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { lidOff = true }
            onOpen()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.5)) { shake += 1 }
        }
    }
}

/* the box itself: glow, sparkles, red box with a gold ribbon and bow; it floats, and wiggles when it can be opened */
struct GiftBox: View {
    let anim: Bool
    let lidOff: Bool
    let ready: Bool

    private let gold = Color(red: 1, green: 0.84, blue: 0.29)
    private var ribbon: LinearGradient { LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.69), Color(red: 0.96, green: 0.71, blue: 0)], startPoint: .top, endPoint: .bottom) }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.94, blue: 0.67).opacity(0.95), Color(red: 1, green: 0.82, blue: 0.35).opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: 80))
                .scaleEffect(lidOff ? 1.6 : (anim ? 1.05 : 0.9))
                .opacity(anim || lidOff ? 1 : 0.6)
            sparkles
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.23, blue: 0.42), Color(red: 0.71, green: 0.07, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Rectangle().fill(ribbon).frame(width: 18))
                    .overlay(
                        LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 30).rotationEffect(.degrees(18)).offset(x: anim ? 60 : -60)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(width: 90, height: 66)
                    .offset(y: 30)
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.57), Color(red: 0.85, green: 0.11, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Rectangle().fill(ribbon).frame(width: 18)
                    HStack(spacing: 2) {
                        Ellipse().stroke(gold, lineWidth: 6).frame(width: 24, height: 16).rotationEffect(.degrees(-24))
                        Ellipse().stroke(gold, lineWidth: 6).frame(width: 24, height: 16).rotationEffect(.degrees(24))
                    }
                    .offset(y: -19)
                }
                .frame(width: 100, height: 24)
                .rotationEffect(.degrees(lidOff ? 38 : 0), anchor: .bottomLeading)
                .offset(x: lidOff ? 34 : 0, y: lidOff ? -78 : 0)
                .opacity(lidOff ? 0 : 1)
            }
            .frame(width: 100, height: 100)
            .offset(y: anim ? 2 : 8)
            .rotationEffect(.degrees(ready && !lidOff ? (anim ? 5 : -5) : 0))
        }
    }

    private var sparkles: some View {
        let xs: [CGFloat] = [16, 140, 136, 30], ys: [CGFloat] = [40, 24, 110, 126], sz: [CGFloat] = [16, 12, 15, 11]
        return ZStack {
            ForEach(0..<4, id: \.self) { i in
                let on = (i % 2 == 0) == anim
                Image(systemName: "sparkle").font(.system(size: sz[i], weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.97, blue: 0.76))
                    .shadow(color: Color(red: 1, green: 0.88, blue: 0.54), radius: 4)
                    .scaleEffect(on ? 1.15 : 0.6).opacity(on ? 1 : 0.25)
                    .position(x: xs[i], y: ys[i])
            }
        }
        .frame(width: 156, height: 150)
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(amount * .pi * 4), y: 0))
    }
}

/* fireworks over the whole screen for about four seconds */
struct FireworksView: View {
    private struct Pt { let x: Double, y: Double, vx: Double, vy: Double, t0: Double; let c: Color }
    private let pts: [Pt]
    private let start = Date()

    init(size: CGSize) {
        let cols: [Color] = [Color(red: 1, green: 0.84, blue: 0.29), Color(red: 1, green: 0.31, blue: 0.43), Color(red: 0.49, green: 0.96, blue: 1),
                             Color(red: 0.7, green: 0.53, blue: 1), Color(red: 0.41, green: 0.94, blue: 0.68), Color(red: 1, green: 0.6, blue: 0.24)]
        var list: [Pt] = []
        for b in 0..<9 {
            let cx = Double(size.width) * Double.random(in: 0.15...0.85)
            let cy = Double(size.height) * Double.random(in: 0.12...0.5)
            let col = cols.randomElement() ?? .white
            let m = 54
            for i in 0..<m {
                let a = Double.pi * 2 * Double(i) / Double(m), sp = Double.random(in: 2.2...5.6)
                list.append(Pt(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, t0: Double(b) * 0.32, c: Double.random(in: 0...1) < 0.25 ? .white : col))
            }
        }
        pts = list
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, _ in
                let t = tl.date.timeIntervalSince(start)
                let d = 0.982, g = 0.055, life = 1.35
                ctx.blendMode = .plusLighter
                for p in pts {
                    let dt = t - p.t0
                    if dt <= 0 || dt > life { continue }
                    let n = dt * 60, s = (1 - pow(d, n)) / (1 - d)      /* the same motion as the menu page: drag and gravity per frame */
                    let x = p.x + p.vx * s
                    let y = p.y + p.vy * s + g * (n - s) / (1 - d)
                    ctx.opacity = 1 - dt / life
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.3, y: y - 2.3, width: 4.6, height: 4.6)), with: .color(p.c))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
