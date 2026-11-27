import XCTest

/* Walks through the app while CI records the simulator screen (demo video) */
final class DemoTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    func testDemo() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(uz)", "-AppleLocale", "uz_UZ"]
        app.launch()
        pause(12)                                   // menu loads, first dish video starts

        let web = app.webViews.firstMatch
        if web.waitForExistence(timeout: 10) {
            for _ in 0..<3 { web.swipeLeft(); pause(4.5) }
            web.swipeRight(); pause(3)
        }

        /* the app draws its own tab bar (not a system UITabBar): its buttons are found by their labels */
        func tab(_ t: String) { let b = app.buttons[t].firstMatch; if b.waitForExistence(timeout: 3) { b.tap() } }
        tab("Bron")
        pause(2)
        let name = app.textFields["Ismingiz"]
        if name.waitForExistence(timeout: 5) && name.isHittable { name.tap(); pause(0.5); name.typeText("Aziz Karimov"); pause(1) }
        let phone = app.textFields.element(boundBy: 1)
        if phone.exists && phone.isHittable { phone.tap(); pause(0.5); phone.typeText("90 123 45 67"); pause(1) }
        if app.buttons["Tayyor"].exists { app.buttons["Tayyor"].tap() }   // hide keyboard
        pause(1)
        let stepper = app.steppers.firstMatch
        if stepper.exists {
            let plus = stepper.buttons.element(boundBy: 1)
            for _ in 0..<2 { plus.tap(); pause(0.6) }
        }
        let zone = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Joy'")).firstMatch
        if zone.exists {
            zone.tap(); pause(1.5)
            let vip = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'VIP xona'")).firstMatch
            if vip.exists { vip.tap() } else { app.tap() }
            pause(1.5)
        }
        let reason = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sabab'")).firstMatch
        if reason.exists {
            reason.tap(); pause(1.5)
            let bday = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Tug'ilgan kun")).firstMatch
            if bday.exists { bday.tap() } else { app.tap() }
            pause(1.5)
        }
        app.swipeUp(); pause(2.5)
        app.swipeDown(); pause(1.5)

        tab("UNO")
        pause(3)
        app.swipeUp(); pause(2.5)
        app.swipeDown(); pause(2)

        tab("Menyu")
        pause(5)
    }
}
