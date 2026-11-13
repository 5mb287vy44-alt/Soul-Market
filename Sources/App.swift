import SwiftUI

enum Kind { case stock, crypto, realty }
enum Phase { case pick, play, relic, won, lost }

enum Build: String, CaseIterable {
    case scalper = "Скальпер", holder = "Холдер", rentier = "Рантье"
    var info: String {
        switch self {
        case .scalper: return "Комиссия 0.5% вместо 2%, 4 действия в день"
        case .holder: return "+1% к продаже за каждый день удержания, до 10"
        case .rentier: return "Аренда недвижимости 2% в день вместо 0.5%"
        }
    }
}

enum Relic: String, CaseIterable {
    case insider = "Инсайдер", leverage = "Плечо ×2", loophole = "Налоговая лазейка", parachute = "Золотой парашют"
    var info: String {
        switch self {
        case .insider: return "Видишь завтрашнее событие"
        case .leverage: return "Прибыль и убыток от сделок ×2"
        case .loophole: return "Крипта не облагается налогом"
        case .parachute: return "Один раз +5 дней после провала"
        }
    }
}

struct Ev { let t: String; let s: Double; let c: Double; let r: Double }

struct Asset: Identifiable {
    let id: String
    let kind: Kind
    let vol: Double
    var price: Double
    var qty = 0.0
    var cost = 0.0
    var hold = 0
}

func money(_ v: Double) -> String { "$\(Int(v))" }

final class Game: ObservableObject {
    static let events = [
        Ev(t: "Бум на рынке", s: 0.08, c: 0.10, r: 0.01),
        Ev(t: "Крах крипты", s: -0.06, c: -0.25, r: 0),
        Ev(t: "Ипотечный кризис", s: -0.04, c: 0.03, r: -0.08),
        Ev(t: "Хайп вокруг ИИ", s: 0.10, c: 0.05, r: 0),
        Ev(t: "Проверка регулятора", s: -0.03, c: -0.12, r: -0.01),
        Ev(t: "Тихий день", s: 0, c: 0, r: 0)
    ]

    @Published var phase = Phase.pick
    @Published var build = Build.scalper
    @Published var day = 1
    @Published var cash = 5000.0
    @Published var actions = 3
    @Published var relics: [Relic] = []
    @Published var offer: [Relic] = []
    @Published var log = "Рынок открыт."
    @Published var next = Game.events.randomElement()!
    @Published var assets = [
        Asset(id: "NeoCorp", kind: .stock, vol: 0.03, price: 100),
        Asset(id: "Квант", kind: .stock, vol: 0.04, price: 250),
        Asset(id: "BTX", kind: .crypto, vol: 0.12, price: 1000),
        Asset(id: "ETX", kind: .crypto, vol: 0.10, price: 400),
        Asset(id: "Квартира", kind: .realty, vol: 0.01, price: 3000),
        Asset(id: "Офис", kind: .realty, vol: 0.015, price: 9000)
    ]
    var usedParachute = false

    var soulPrice: Double { 10000 * pow(1.02, Double(day - 1)) }
    var maxActions: Int { build == .scalper ? 4 : 3 }
    var fee: Double { build == .scalper ? 0.005 : 0.02 }
    var worth: Double { cash + assets.reduce(0) { $0 + $1.price * $1.qty } }

    func has(_ r: Relic) -> Bool { relics.contains(r) }

    func start(_ b: Build) {
        build = b
        actions = maxActions
        phase = .play
    }

    func buy(_ i: Int, _ share: Double) {
        guard actions > 0, phase == .play else { return }
        let spend = cash * share
        guard spend > 1 else { return }
        let a = assets[i]
        let units = spend / (a.price * (1 + fee))
        assets[i].cost = (a.cost * a.qty + a.price * units) / (a.qty + units)
        if a.qty == 0 { assets[i].hold = 0 }
        assets[i].qty += units
        cash -= spend
        actions -= 1
    }

    func sell(_ i: Int) {
        let a = assets[i]
        guard actions > 0, a.qty > 0, phase == .play else { return }
        let bonus = build == .holder ? 0.01 * Double(min(a.hold, 10)) : 0
        let gross = a.price * a.qty * (1 + bonus)
        var profit = gross - a.cost * a.qty
        if has(.leverage) { profit *= 2 }
        let taxFree = a.kind == .crypto && has(.loophole)
        let tax = (profit > 0 && !taxFree) ? profit * 0.1 : 0
        cash += max(0, a.cost * a.qty + profit - tax - a.price * a.qty * fee)
        assets[i].qty = 0
        assets[i].cost = 0
        assets[i].hold = 0
        actions -= 1
    }

    func endDay() {
        guard phase == .play else { return }
        let e = next
        for i in assets.indices {
            let k: Double
            switch assets[i].kind {
            case .stock: k = e.s
            case .crypto: k = e.c
            case .realty: k = e.r
            }
            let v = assets[i].vol
            assets[i].price = max(1, assets[i].price * (1 + k + Double.random(in: -v...v)))
            if assets[i].qty > 0 { assets[i].hold += 1 }
            if assets[i].kind == .realty {
                cash += assets[i].price * assets[i].qty * (build == .rentier ? 0.02 : 0.005)
            }
        }
        log = "День \(day): \(e.t)"
        day += 1
        actions = maxActions
        next = Game.events.randomElement()!
        if day > 30 {
            if has(.parachute) && !usedParachute {
                usedParachute = true
                day = 26
                log = "Парашют раскрылся: +5 дней"
            } else {
                phase = .lost
            }
        } else if worth < 50 {
            phase = .lost
        } else if (day - 1) % 5 == 0 {
            offer = Array(Relic.allCases.filter { !relics.contains($0) }.shuffled().prefix(3))
            if !offer.isEmpty { phase = .relic }
        }
    }

    func pick(_ r: Relic) {
        relics.append(r)
        offer = []
        phase = .play
    }

    func buySoul() {
        if cash >= soulPrice { phase = .won }
    }
}

@main
struct SoulMarketApp: App {
    var body: some Scene {
        WindowGroup { Root() }
    }
}

struct Root: View {
    @State private var round = 0
    var body: some View {
        GameView(restart: { round += 1 })
            .id(round)
            .preferredColorScheme(.dark)
    }
}

struct GameView: View {
    @StateObject private var g = Game()
    var restart: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch g.phase {
            case .pick: pick
            case .play: play
            case .relic: relic
            case .won: end("Душа выкуплена", "Ты снова целый. Но Брокер ещё не закончил с тобой.")
            case .lost: end("Контракт провален", "Душа осталась у Брокера.")
            }
        }
    }

    var pick: some View {
        VStack(spacing: 14) {
            Text("SOUL MARKET").font(.largeTitle.bold())
            Text("Ты акционер, упавший на дно. Твою душу выставили на рынок как актив. Копи кассу и выкупи её, пока цена не ушла вверх.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            ForEach(Build.allCases, id: \.self) { b in
                Button { g.start(b) } label: {
                    VStack(alignment: .leading) {
                        Text(b.rawValue).bold()
                        Text(b.info).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    var relic: some View {
        VStack(spacing: 14) {
            Text("Выбери реликвию").font(.title.bold())
            ForEach(g.offer, id: \.self) { r in
                Button { g.pick(r) } label: {
                    VStack(alignment: .leading) {
                        Text(r.rawValue).bold()
                        Text(r.info).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    var play: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("День \(g.day)/30 · \(g.build.rawValue)").font(.headline)
                        Text("Касса \(money(g.cash))")
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Цена души").font(.caption).foregroundColor(.gray)
                        Text(money(g.soulPrice)).font(.headline).foregroundColor(.purple)
                    }
                }
                ProgressView(value: min(1, g.cash / g.soulPrice)).tint(.purple)
                Text(g.log).font(.footnote).foregroundColor(.gray)
                if g.has(.insider) {
                    Text("Завтра: \(g.next.t)").font(.footnote).foregroundColor(.yellow)
                }
                if !g.relics.isEmpty {
                    Text(g.relics.map { $0.rawValue }.joined(separator: " • "))
                        .font(.caption).foregroundColor(.orange)
                }
                ForEach(g.assets.indices, id: \.self) { i in row(i) }
                HStack {
                    Button("Конец дня (\(g.actions) ⚡)") { g.endDay() }
                        .buttonStyle(.borderedProminent)
                    Button("Выкупить душу") { g.buySoul() }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .disabled(g.cash < g.soulPrice)
                }
            }
            .padding()
        }
    }

    func kindName(_ k: Kind) -> String {
        switch k {
        case .stock: return "Акции"
        case .crypto: return "Крипта"
        case .realty: return "Недвижимость"
        }
    }

    func row(_ i: Int) -> some View {
        let a = g.assets[i]
        let q = String(format: "%.2f", a.qty)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(a.id).bold()
                Text(kindName(a.kind)).font(.caption).foregroundColor(.gray)
                Spacer()
                Text(money(a.price))
            }
            if a.qty > 0 {
                Text("В портфеле: \(q) · вложено \(money(a.cost * a.qty))")
                    .font(.caption).foregroundColor(.gray)
            }
            HStack {
                Button("¼ кассы") { g.buy(i, 0.25) }
                Button("Вся касса") { g.buy(i, 1) }
                Button("Продать") { g.sell(i) }.disabled(a.qty == 0)
            }
            .buttonStyle(.bordered)
            .disabled(g.actions == 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.07))
        .cornerRadius(12)
    }

    func end(_ t: String, _ s: String) -> some View {
        VStack(spacing: 14) {
            Text(t).font(.title.bold())
            Text(s).foregroundColor(.gray)
            Text("День \(g.day), касса \(money(g.cash))")
            Button("Новый забег", action: restart).buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
