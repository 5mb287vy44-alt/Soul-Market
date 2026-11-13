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
    var hist: [Double] = []
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
    @Published var worthHist: [Double] = [5000]
    var usedParachute = false

    init() {
        for i in assets.indices {
            var p = assets[i].price
            var h = [p]
            let v = assets[i].vol
            for _ in 0..<23 {
                p /= 1 + Double.random(in: -v...v)
                h.insert(p, at: 0)
            }
            assets[i].hist = h
        }
    }

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
            assets[i].hist.append(assets[i].price)
            if assets[i].hist.count > 40 { assets[i].hist.removeFirst() }
            if assets[i].kind == .realty {
                cash += assets[i].price * assets[i].qty * (build == .rentier ? 0.02 : 0.005)
            }
        }
        worthHist.append(worth)
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

// MARK: - Theme

extension Build {
    var icon: String {
        switch self {
        case .scalper: return "⚡️"
        case .holder: return "💎"
        case .rentier: return "🏢"
        }
    }
}

extension Relic {
    var icon: String {
        switch self {
        case .insider: return "👁"
        case .leverage: return "🎲"
        case .loophole: return "📜"
        case .parachute: return "🪂"
        }
    }
}

enum T {
    static let bg1 = Color(red: 0.09, green: 0.03, blue: 0.18)
    static let bg2 = Color(red: 0.02, green: 0.09, blue: 0.15)
    static let panel = Color(red: 0.12, green: 0.12, blue: 0.19)
    static let up = Color(red: 0.055, green: 0.80, blue: 0.51)
    static let down = Color(red: 0.96, green: 0.27, blue: 0.36)
    static let gold = Color(red: 0.94, green: 0.73, blue: 0.04)
    static let violet = Color(red: 0.62, green: 0.40, blue: 1.0)
    static func f(_ s: CGFloat, _ w: Font.Weight = .heavy) -> Font {
        .system(size: s, weight: w, design: .rounded)
    }
}

struct Felt: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [T.bg1, T.bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                AngularGradient(colors: [T.down, T.violet, T.up, T.violet, T.down],
                                center: .center, angle: .degrees(t * 6))
                    .scaleEffect(1.8)
                    .blur(radius: 70)
                    .opacity(0.28)
            }
        }
        .ignoresSafeArea()
    }
}

struct CRT: View {
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.black.opacity(0.16)))
                    y += 4
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center,
                           startRadius: 220, endRadius: 560)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct Panel: ViewModifier {
    var edge: Color
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(T.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(edge, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.75), radius: 0, x: 0, y: 5)
    }
}

extension View {
    func panel(_ edge: Color = Color.white.opacity(0.18)) -> some View {
        modifier(Panel(edge: edge))
    }
}

struct Chunky: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var on

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.f(13))
            .foregroundColor(.black)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(color))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.35), lineWidth: 2))
            .shadow(color: .black.opacity(0.85), radius: 0, x: 0, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 3 : 0)
            .opacity(on ? 1 : 0.4)
    }
}

struct Spark: View {
    let pts: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let lo = pts.min() ?? 0
            let hi = pts.max() ?? 1
            let rng = max(hi - lo, 0.0001)
            let step = geo.size.width / CGFloat(max(pts.count - 1, 1))
            let ys: [CGFloat] = pts.map { geo.size.height * (1 - CGFloat(($0 - lo) / rng)) }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    for (i, y) in ys.enumerated() {
                        p.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
                    }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    for (i, y) in ys.enumerated() {
                        let pt = CGPoint(x: CGFloat(i) * step, y: y)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct BigCard: View {
    let icon: String
    let title: String
    let info: String
    let tilt: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon).font(.system(size: 44))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased()).font(T.f(20)).foregroundColor(T.gold)
                    Text(info).font(T.f(13, .semibold))
                        .foregroundColor(Color.white.opacity(0.8))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .panel(T.gold.opacity(0.7))
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(tilt))
    }
}

// MARK: - App

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
            Felt()
            switch g.phase {
            case .pick: pick
            case .play: play
            case .relic: relic
            case .won: end("Душа выкуплена", "Ты снова целый. Но Брокер ещё не закончил с тобой.", T.gold)
            case .lost: end("Контракт провален", "Душа осталась у Брокера.", T.down)
            }
            CRT()
        }
    }

    var pick: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("SOUL\nMARKET").font(T.f(48)).multilineTextAlignment(.center)
                .foregroundColor(T.gold).shadow(color: T.down, radius: 0, x: 3, y: 4)
            Text("Твою душу выставили на рынок как актив. Выбери стиль и выкупи её.")
                .font(T.f(14, .semibold)).foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
            ForEach(Array(Build.allCases.enumerated()), id: \.offset) { i, b in
                BigCard(icon: b.icon, title: b.rawValue, info: b.info, tilt: Double(i - 1) * 1.5) {
                    g.start(b)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    var relic: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("ВЫБЕРИ РЕЛИКВИЮ").font(T.f(30)).foregroundColor(T.gold)
                .shadow(color: T.down, radius: 0, x: 3, y: 4)
            ForEach(Array(g.offer.enumerated()), id: \.offset) { i, r in
                BigCard(icon: r.icon, title: r.rawValue, info: r.info, tilt: Double(i - 1) * 2) {
                    g.pick(r)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    var play: some View {
        VStack(spacing: 10) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    banner
                    ForEach(g.assets.indices, id: \.self) { i in row(i) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            footer
        }
    }

    var header: some View {
        let up = (g.worthHist.last ?? 0) >= (g.worthHist.first ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ДЕНЬ \(g.day)/30").font(T.f(13)).foregroundColor(Color.white.opacity(0.6))
                Text(g.build.rawValue.uppercased()).font(T.f(11))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(T.violet)).foregroundColor(.black)
                Spacer()
                Text("ДУША  \(money(g.soulPrice))").font(T.f(14)).foregroundColor(T.gold)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("КАПИТАЛ").font(T.f(11)).foregroundColor(Color.white.opacity(0.5))
                    Text(money(g.worth)).font(T.f(34)).foregroundColor(.white)
                    Text("Касса \(money(g.cash))").font(T.f(12, .semibold)).foregroundColor(T.up)
                }
                Spacer()
                Spark(pts: g.worthHist.count > 1 ? g.worthHist : [1, 1], color: up ? T.up : T.down)
                    .frame(width: 130, height: 54)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [T.violet, T.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(1, g.cash / g.soulPrice)))
                }
            }
            .frame(height: 10)
        }
        .panel(T.gold.opacity(0.5))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📰 \(g.log)").font(T.f(14))
            if g.has(.insider) {
                Text("👁 Завтра: \(g.next.t)").font(T.f(13)).foregroundColor(T.gold)
            }
            if !g.relics.isEmpty {
                Text(g.relics.map { $0.icon + " " + $0.rawValue }.joined(separator: "   "))
                    .font(T.f(12, .semibold)).foregroundColor(T.violet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    func kindName(_ k: Kind) -> String {
        switch k {
        case .stock: return "АКЦИИ"
        case .crypto: return "КРИПТА"
        case .realty: return "НЕДВИЖИМОСТЬ"
        }
    }

    func row(_ i: Int) -> some View {
        let a = g.assets[i]
        let prev = a.hist.count > 1 ? a.hist[a.hist.count - 2] : a.price
        let chg = (a.price / prev - 1) * 100
        let col = chg >= 0 ? T.up : T.down
        let pct = (chg >= 0 ? "▲ " : "▼ ") + String(format: "%.1f", abs(chg)) + "%"
        let q = String(format: "%.2f", a.qty)
        let pnl = (a.price - a.cost) * a.qty
        let pnlText = (pnl >= 0 ? "+" : "-") + money(abs(pnl))
        return VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.id.uppercased()).font(T.f(20))
                    Text(kindName(a.kind)).font(T.f(11, .semibold)).foregroundColor(Color.white.opacity(0.5))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(money(a.price)).font(T.f(20))
                    Text(pct).font(T.f(12))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(col)).foregroundColor(.black)
                }
            }
            Spark(pts: a.hist, color: col).frame(height: 54)
            if a.qty > 0 {
                HStack {
                    Text("В портфеле \(q)").font(T.f(12, .semibold)).foregroundColor(Color.white.opacity(0.7))
                    Spacer()
                    Text("P&L \(pnlText)").font(T.f(12)).foregroundColor(pnl >= 0 ? T.up : T.down)
                }
            }
            HStack(spacing: 8) {
                Button("¼ КАССЫ") { g.buy(i, 0.25) }.buttonStyle(Chunky(color: T.up))
                Button("ВСЯ КАССА") { g.buy(i, 1) }.buttonStyle(Chunky(color: T.gold))
                Button("ПРОДАТЬ") { g.sell(i) }.buttonStyle(Chunky(color: T.down)).disabled(a.qty == 0)
            }
            .disabled(g.actions == 0)
        }
        .panel(a.qty > 0 ? T.violet.opacity(0.8) : Color.white.opacity(0.15))
    }

    var footer: some View {
        HStack(spacing: 10) {
            Button("🌙 КОНЕЦ ДНЯ · \(g.actions)⚡") { g.endDay() }
                .buttonStyle(Chunky(color: T.violet))
            Button("💀 ВЫКУПИТЬ ДУШУ") { g.buySoul() }
                .buttonStyle(Chunky(color: T.gold))
                .disabled(g.cash < g.soulPrice)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.35))
    }

    func end(_ t: String, _ s: String, _ c: Color) -> some View {
        VStack(spacing: 16) {
            Text(t.uppercased()).font(T.f(34)).multilineTextAlignment(.center)
                .foregroundColor(c).shadow(color: .black, radius: 0, x: 3, y: 4)
            Text(s).font(T.f(15, .semibold)).foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Text("День \(g.day) · капитал \(money(g.worth))").font(T.f(16)).panel(c.opacity(0.6))
            Button("НОВЫЙ ЗАБЕГ", action: restart)
                .buttonStyle(Chunky(color: c))
                .frame(width: 220)
        }
        .padding(24)
    }
}
