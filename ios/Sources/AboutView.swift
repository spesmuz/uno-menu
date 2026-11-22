import SwiftUI
import UIKit

struct AboutView: View {
    @State private var sharing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image("Logo").resizable().scaledToFit().frame(width: 132, height: 132)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .shadow(color: Config.gold.opacity(0.25), radius: 18)
                        Text("UNO Airways").font(.system(size: 30, weight: .bold, design: .serif)).foregroundColor(Config.gold)
                        Text(L.t("about.sub")).font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 10) {
                        action("phone.fill", L.t("about.call")) { open("tel://" + Config.phone) }
                        action("map.fill", L.t("about.map")) { openMap() }
                        action("camera.fill", L.t("about.insta")) { openInstagram() }
                        action("square.and.arrow.up", L.t("about.share")) { sharing = true }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.t("about.story.t")).font(.headline).foregroundColor(Config.gold)
                        Text(L.t("about.story")).font(.body).foregroundColor(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 18)

                    VStack(spacing: 0) {
                        row("mappin.and.ellipse", L.t("about.address"), Config.address) { openMap() }
                        Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1).padding(.leading, 56)
                        row("phone.circle.fill", L.t("about.op"), Config.phonePretty) { open("tel://" + Config.phone) }
                        Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1).padding(.leading, 56)
                        row("music.note", L.t("about.music"), L.t("about.music.t"), nil)
                        Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1).padding(.leading, 56)
                        row("person.3.fill", L.t("about.seats"), L.t("about.seats.t"), nil)
                        Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1).padding(.leading, 56)
                        row("gift.fill", L.t("about.events"), L.t("about.events.t"), nil)
                    }
                    .glassCard(padding: 0)

                    VStack(spacing: 6) {
                        Button(L.t("about.privacy")) { UIApplication.shared.open(Config.privacyURL) }
                            .font(.footnote).foregroundColor(Config.gold)
                        Text("\(L.t("about.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 18)
            }
            .background(UNOSky())
            .navigationBarHidden(true)
            .sheet(isPresented: $sharing) {
                ShareSheet(items: [L.t("share.text"), Config.siteURL])
            }
        }
        .navigationViewStyle(.stack)
    }

    private func action(_ icon: String, _ title: String, _ go: @escaping () -> Void) -> some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); go() }) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .foregroundColor(Config.gold)
            .glassCard(padding: 0)
        }
    }

    private func row(_ icon: String, _ title: String, _ text: String, _ go: (() -> Void)?) -> some View {
        let content = HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(Config.gold).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundColor(.white)
                Text(text).font(.footnote).foregroundColor(Color.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if go != nil { Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary) }
        }
        .padding(16)
        .contentShape(Rectangle())
        return Group {
            if let go = go { Button(action: go) { content }.buttonStyle(.plain) } else { content }
        }
    }

    private func open(_ s: String) { if let u = URL(string: s) { UIApplication.shared.open(u) } }

    private func openMap() {
        let q = "UNO Airways Restaurante".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let a = Config.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        open("http://maps.apple.com/?q=\(q)&address=\(a)")
    }

    private func openInstagram() {
        if let app = URL(string: "instagram://user?username=" + Config.instagram), UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else { open("https://www.instagram.com/" + Config.instagram + "/") }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
