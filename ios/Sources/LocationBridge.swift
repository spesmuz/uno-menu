import Foundation
import CoreLocation
import WebKit

/* "Joylashuvimni yuborish" in the delivery form: the page asks, the app reads the phone's GPS and answers */
final class LocationBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    weak var web: WKWebView?
    private let manager = CLLocationManager()
    private var waiting = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        waiting = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()   // answer comes in locationManagerDidChangeAuthorization
        case .denied, .restricted: reply(error: "denied")
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard waiting else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: reply(error: "denied")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard waiting, let l = locations.last else { return }
        waiting = false
        send("{lat:\(l.coordinate.latitude),lng:\(l.coordinate.longitude),acc:\(Int(l.horizontalAccuracy))}")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let e = error as NSError
        reply(error: e.code == CLError.denied.rawValue ? "denied" : "error")
    }

    private func reply(error: String) { waiting = false; send("{error:'\(error)'}") }
    private func send(_ obj: String) {
        DispatchQueue.main.async { self.web?.evaluateJavaScript("window.__unoLoc&&window.__unoLoc(\(obj))", completionHandler: nil) }
    }
}
