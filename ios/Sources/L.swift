import Foundation
import Combine

/* The language the menu page chose (UZ / RU / EN); the phone's language until the menu says otherwise */
final class LangStore: ObservableObject {
    static let shared = LangStore()
    private static let key = "uno.lang"
    @Published private(set) var lang: String

    private init() {
        if let s = UserDefaults.standard.string(forKey: LangStore.key), ["uz", "ru", "en"].contains(s) {
            lang = s
        } else {
            let p = (Locale.preferredLanguages.first ?? "uz").lowercased()
            lang = p.hasPrefix("ru") ? "ru" : p.hasPrefix("en") ? "en" : "uz"
        }
    }

    func set(_ l: String) {
        let v = l.lowercased()
        guard ["uz", "ru", "en"].contains(v) else { return }
        let apply = {
            UserDefaults.standard.set(v, forKey: LangStore.key)
            if self.lang != v { self.lang = v }
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }
}

/* App texts in the language chosen in the menu */
enum L {
    static var lang: String { LangStore.shared.lang }
    static var locale: Locale { Locale(identifier: lang == "uz" ? "uz_Latn_UZ" : lang) }

    static func t(_ k: String) -> String { (d[lang]?[k]) ?? (d["uz"]?[k]) ?? k }

    static let d: [String: [String: String]] = [
        "uz": [
            "done": "Tayyor", "tab.profile": "Profil", "pf.photo": "Surat qo'yish", "pf.photoChange": "Suratni almashtirish", "pf.photoDel": "Suratni olib tashlash",  "pf.me": "Mening ma'lumotlarim", "pf.name": "Ism familiya", "pf.hint": "Bir marta yozib qo'ying: bron, yetkazib berish va fikr qoldirishda ism va telefon o'zi to'ldiriladi.", "pf.save": "Saqlash", "pf.saved": "Saqlandi", "pf.news": "Yangiliklar", "pf.noNews": "Hozircha yangilik yo'q.",  "tab.menu": "Menyu", "tab.book": "Bron", "tab.about": "UNO",
            "offline.title": "Internet yo'q", "offline.text": "Menyuni ochish uchun internetga ulaning.", "retry": "Qayta urinish",
            "book.title": "Stol bron qilish", "book.guest": "Mehmon", "book.name": "Ismingiz", "book.phone": "Telefon raqamingiz",
            "book.when": "Qachon", "book.date": "Sana va vaqt", "book.guests": "Mehmonlar soni", "book.zone": "Joy", "book.occasion": "Sabab",
            "book.note": "Izoh (ixtiyoriy)", "book.remind": "2 soat oldin eslatish", "book.send": "Bron qilish",
            "book.call": "Yoki qo'ng'iroq qiling", "book.call24": "Operatorlar 24 soat ishlaydi",
            "book.ok.t": "Rahmat!", "book.ok": "Broningiz qabul qilindi. Operatorimiz tez orada siz bilan bog'lanib, tasdiqlaydi.",
            "book.err.t": "Yuborilmadi", "book.err": "Internetni tekshirib, qayta urinib ko'ring yoki qo'ng'iroq qiling.",
            "book.err.name": "Ismingizni yozing.", "book.err.phone": "Telefon raqamini to'liq yozing.", "book.err.time": "Kelajakdagi vaqtni tanlang.",
            "book.err.many": "Juda ko'p urinish. Birozdan keyin qayta urinib ko'ring yoki qo'ng'iroq qiling.",
            "book.mine": "Mening bronlarim", "book.people": "kishi", "ok": "Yaxshi", "callNow": "Qo'ng'iroq qilish",
            "remind.title": "UNO Airways", "remind.body": "Bugun soat %@ da stolingiz bron qilingan. Sizni kutamiz! ✈️",
            "z.any": "Farqi yo'q", "z.family": "Oilaviy", "z.comfort": "Komfort", "z.business": "Biznes", "z.terrace": "Terassa", "z.vip": "VIP xona", "z.conf": "Konferensiya zali",
            "o.visit": "Oddiy tashrif", "o.bday": "Tug'ilgan kun", "o.wedding": "To'y / marosim", "o.conf": "Konferensiya", "o.meeting": "Biznes uchrashuv",
            "about.sub": "Turk va Yevropa oshxonasi", "about.story.t": "Bizning hikoya",
            "about.story": "UNO — uch aka-uka: Ubaydillo, Nodirbek va Ozodbek ismlarining bosh harflari. «Airways» esa asoschimiz Nodirbekning bolalikdagi uchuvchi bo'lish orzusidan. Shuning uchun ofitsiantlarimiz uchuvchi libosida, bino tepasida esa katta samolyot maketi turadi. Ichkarida ko'plab daraxtlar va tabiiy o'simliklar sizni kutadi.",
            "about.call": "Qo'ng'iroq", "about.map": "Xarita", "about.insta": "Instagram", "about.share": "Ulashish",
            "about.address": "Manzil", "about.music": "Har kuni jonli musiqa", "about.music.t": "Kechqurun jonli musiqa, shou va konsertlar",
            "about.seats": "350 o'rin", "about.seats.t": "Oilaviy, Komfort, Biznes, Terassa, Konferensiya va VIP xonalar",
            "about.events": "Tadbirlar", "about.events.t": "Tug'ilgan kun, to'y, marosim va konferensiyalar",
            "about.op": "24/7 operator", "about.privacy": "Maxfiylik siyosati", "about.version": "Versiya",
            "share.text": "UNO Airways Restaurante — Farg'ona. Menyu:"
        ],
        "ru": [
            "done": "Готово", "tab.profile": "Профиль", "pf.photo": "Добавить фото", "pf.photoChange": "Сменить фото", "pf.photoDel": "Удалить фото",  "pf.me": "Мои данные", "pf.name": "Имя и фамилия", "pf.hint": "Заполните один раз: имя и телефон подставятся сами при брони, доставке и отзывах.", "pf.save": "Сохранить", "pf.saved": "Сохранено", "pf.news": "Новости", "pf.noNews": "Пока новостей нет.",  "tab.menu": "Меню", "tab.book": "Бронь", "tab.about": "UNO",
            "offline.title": "Нет интернета", "offline.text": "Подключитесь к интернету, чтобы открыть меню.", "retry": "Повторить",
            "book.title": "Бронь столика", "book.guest": "Гость", "book.name": "Ваше имя", "book.phone": "Ваш телефон",
            "book.when": "Когда", "book.date": "Дата и время", "book.guests": "Количество гостей", "book.zone": "Место", "book.occasion": "Повод",
            "book.note": "Комментарий (необязательно)", "book.remind": "Напомнить за 2 часа", "book.send": "Забронировать",
            "book.call": "Или позвоните", "book.call24": "Операторы работают круглосуточно",
            "book.ok.t": "Спасибо!", "book.ok": "Бронь принята. Наш оператор скоро свяжется с вами для подтверждения.",
            "book.err.t": "Не отправлено", "book.err": "Проверьте интернет и попробуйте снова или позвоните нам.",
            "book.err.name": "Укажите имя.", "book.err.phone": "Укажите полный номер телефона.", "book.err.time": "Выберите время в будущем.",
            "book.err.many": "Слишком много попыток. Попробуйте позже или позвоните.",
            "book.mine": "Мои брони", "book.people": "чел.", "ok": "Хорошо", "callNow": "Позвонить",
            "remind.title": "UNO Airways", "remind.body": "Сегодня в %@ у вас забронирован столик. Ждём вас! ✈️",
            "z.any": "Неважно", "z.family": "Семейный", "z.comfort": "Комфорт", "z.business": "Бизнес", "z.terrace": "Терраса", "z.vip": "VIP-комната", "z.conf": "Конференц-зал",
            "o.visit": "Обычный визит", "o.bday": "День рождения", "o.wedding": "Свадьба / торжество", "o.conf": "Конференция", "o.meeting": "Деловая встреча",
            "about.sub": "Турецкая и европейская кухня", "about.story.t": "Наша история",
            "about.story": "UNO — первые буквы имён трёх братьев: Убайдилло, Нодирбек и Озодбек. «Airways» — детская мечта основателя Нодирбека стать пилотом. Поэтому наши официанты в форме пилотов, а над зданием — большой макет самолёта. Внутри вас ждут деревья и живые растения.",
            "about.call": "Позвонить", "about.map": "Карта", "about.insta": "Instagram", "about.share": "Поделиться",
            "about.address": "Адрес", "about.music": "Живая музыка каждый день", "about.music.t": "Вечером живая музыка, шоу и концерты",
            "about.seats": "350 мест", "about.seats.t": "Семейный, Комфорт, Бизнес, Терраса, конференц-зал и VIP-комнаты",
            "about.events": "Мероприятия", "about.events.t": "Дни рождения, свадьбы, торжества и конференции",
            "about.op": "Оператор 24/7", "about.privacy": "Политика конфиденциальности", "about.version": "Версия",
            "share.text": "UNO Airways Restaurante — Фергана. Меню:"
        ],
        "en": [
            "done": "Done", "tab.profile": "Profile", "pf.photo": "Add photo", "pf.photoChange": "Change photo", "pf.photoDel": "Remove photo",  "pf.me": "My details", "pf.name": "Full name", "pf.hint": "Fill in once: your name and phone are filled in automatically for bookings, delivery and reviews.", "pf.save": "Save", "pf.saved": "Saved", "pf.news": "News", "pf.noNews": "No news yet.",  "tab.menu": "Menu", "tab.book": "Book", "tab.about": "UNO",
            "offline.title": "No internet", "offline.text": "Connect to the internet to open the menu.", "retry": "Try again",
            "book.title": "Book a table", "book.guest": "Guest", "book.name": "Your name", "book.phone": "Your phone",
            "book.when": "When", "book.date": "Date and time", "book.guests": "Guests", "book.zone": "Seating", "book.occasion": "Occasion",
            "book.note": "Note (optional)", "book.remind": "Remind me 2 hours before", "book.send": "Book now",
            "book.call": "Or call us", "book.call24": "Operators available 24/7",
            "book.ok.t": "Thank you!", "book.ok": "Your booking was received. Our operator will contact you shortly to confirm.",
            "book.err.t": "Not sent", "book.err": "Check your internet and try again, or call us.",
            "book.err.name": "Please enter your name.", "book.err.phone": "Please enter a full phone number.", "book.err.time": "Please choose a future time.",
            "book.err.many": "Too many attempts. Please try later or call us.",
            "book.mine": "My bookings", "book.people": "guests", "ok": "OK", "callNow": "Call",
            "remind.title": "UNO Airways", "remind.body": "Your table is booked today at %@. See you soon! ✈️",
            "z.any": "No preference", "z.family": "Family", "z.comfort": "Comfort", "z.business": "Business", "z.terrace": "Terrace", "z.vip": "VIP room", "z.conf": "Conference hall",
            "o.visit": "Regular visit", "o.bday": "Birthday", "o.wedding": "Wedding / ceremony", "o.conf": "Conference", "o.meeting": "Business meeting",
            "about.sub": "Turkish and European cuisine", "about.story.t": "Our story",
            "about.story": "UNO stands for the first letters of three brothers: Ubaydillo, Nodirbek and Ozodbek. “Airways” comes from founder Nodirbek's childhood dream of becoming a pilot — so our waiters wear pilot uniforms and a large airplane model sits on top of the building. Inside, trees and live plants are waiting for you.",
            "about.call": "Call", "about.map": "Map", "about.insta": "Instagram", "about.share": "Share",
            "about.address": "Address", "about.music": "Live music every day", "about.music.t": "Live music, shows and concerts every evening",
            "about.seats": "350 seats", "about.seats.t": "Family, Comfort, Business, Terrace, Conference and VIP rooms",
            "about.events": "Events", "about.events.t": "Birthdays, weddings, ceremonies and conferences",
            "about.op": "24/7 operator", "about.privacy": "Privacy policy", "about.version": "Version",
            "share.text": "UNO Airways Restaurante — Fergana. Menu:"
        ]
    ]
}
