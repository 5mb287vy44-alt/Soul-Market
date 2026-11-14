import SwiftUI

enum Kind { case stock, fund, crypto, realty, metal, energy }
enum Mode { case sim, real }
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
    var sym = ""
    var qty = 0.0
    var cost = 0.0
    var hold = 0
    var hist: [Double] = []
    var real = 0.0
    var lastReal = 0.0
}

func money(_ v: Double) -> String { "$\(Int(v))" }

struct YF: Decodable {
    struct Chart: Decodable { let result: [R]? }
    struct R: Decodable { let timestamp: [Int]?; let indicators: Ind }
    struct Ind: Decodable { let quote: [Q] }
    struct Q: Decodable { let close: [Double?] }
    let chart: Chart
}

func fetchCloses(_ sym: String) async -> [String: Double]? {
    guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(sym)?range=2y&interval=1d") else { return nil }
    var req = URLRequest(url: url)
    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 20
    guard let (data, _) = try? await URLSession.shared.data(for: req),
          let yf = try? JSONDecoder().decode(YF.self, from: data),
          let r = yf.chart.result?.first,
          let ts = r.timestamp,
          let q = r.indicators.quote.first else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    var m: [String: Double] = [:]
    for (t, c) in zip(ts, q.close) {
        if let c = c { m[f.string(from: Date(timeIntervalSince1970: Double(t)))] = c }
    }
    return m
}

func downloadReal() async -> ([String], [[Double]])? {
    let syms = Game.realSyms.map { $0.sym }
    var maps: [String: [String: Double]] = [:]
    await withTaskGroup(of: (String, [String: Double]?).self) { group in
        for s in syms { group.addTask { (s, await fetchCloses(s)) } }
        for await (s, m) in group { if let m = m { maps[s] = m } }
    }
    guard maps.count == syms.count, let base = maps["AAPL"] else { return nil }
    let dates = base.keys.sorted()
    var cols: [[Double]] = []
    for s in syms {
        guard let m = maps[s] else { return nil }
        var last = -1.0
        var col: [Double] = []
        for d in dates {
            if let v = m[d] { last = v }
            col.append(last)
        }
        cols.append(col)
    }
    guard let first = (0..<dates.count).first(where: { i in cols.allSatisfy { $0[i] > 0 } }),
          dates.count - first > 70 else { return nil }
    return (Array(dates[first...]), cols.map { Array($0[first...]) })
}

final class Game: ObservableObject {
    static let realSyms: [(sym: String, name: String, kind: Kind)] = [
        ("AAPL", "AAPL", .stock), ("NVDA", "NVDA", .stock),
        ("SPY", "SPY", .fund), ("QQQ", "QQQ", .fund),
        ("BTC-USD", "BTC", .crypto), ("ETH-USD", "ETH", .crypto),
        ("VNQ", "VNQ", .realty), ("O", "O", .realty)
    ]
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
    @Published var mode = UserDefaults.standard.bool(forKey: "realMode") ? Mode.real : Mode.sim
    @Published var loading = false
    @Published var note = ""
    @Published var nextInfo = ""
    var trend = 0.0
    var realDates: [String] = []
    var realCols: [[Double]] = []
    var idx = 0
    var startIdx = 0
    @Published var assets = [
        Asset(id: "AAPL", kind: .stock, vol: 0.03, price: 230, sym: "AAPL"),
        Asset(id: "NVDA", kind: .stock, vol: 0.04, price: 180, sym: "NVDA"),
        Asset(id: "BTC", kind: .crypto, vol: 0.12, price: 95000, sym: "BTC"),
        Asset(id: "ETH", kind: .crypto, vol: 0.10, price: 3200, sym: "ETH"),
        Asset(id: "VNQ", kind: .realty, vol: 0.01, price: 90, sym: "VNQ"),
        Asset(id: "O", kind: .realty, vol: 0.015, price: 58, sym: "O"),
        Asset(id: "XAU", kind: .metal, vol: 0.015, price: 3500, sym: "GC=F"),
        Asset(id: "XAG", kind: .metal, vol: 0.03, price: 40, sym: "SI=F"),
        Asset(id: "WTI", kind: .energy, vol: 0.03, price: 65, sym: "CL=F"),
        Asset(id: "NG", kind: .energy, vol: 0.05, price: 3.5, sym: "NG=F")
    ]
    @Published var worthHist: [Double] = [5000]
    @Published var live = false
    @Published var status = ""
    @Published var news: [String: [NewsItem]] = [:]
    @Published var newsBusy: Set<String> = []
    var usedParachute = false
    var timer: Timer?
    var tickN = 0
    static let boost = 20.0
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

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
        nextInfo = next.t
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    deinit { timer?.invalidate() }

    func loadNews(_ key: String, _ q: String) {
        guard !newsBusy.contains(key) else { return }
        newsBusy.insert(key)
        Task { @MainActor [self] in
            let r = await fetchNews(q)
            news[key] = r
            newsBusy.remove(key)
        }
    }

    func tick() {
        guard phase == .play, mode == .sim else { return }
        tickN += 1
        if live {
            if tickN % 10 == 0 { fetchReal(all: tickN % 20 == 0) }
            return
        }
        for i in assets.indices {
            let v = assets[i].vol * 0.05
            let tr = (assets[i].kind == .realty ? 0.3 : 1.0) * trend * 0.02
            assets[i].price = max(1, assets[i].price * (1 + tr + Double.random(in: -v...v)))
            assets[i].hist[assets[i].hist.count - 1] = assets[i].price
        }
    }

    func setLive(_ on: Bool) {
        guard on != live else { return }
        live = on
        for i in assets.indices { assets[i].lastReal = 0 }
        if on {
            status = "Подключаюсь…"
            fetchReal()
        } else {
            status = ""
        }
    }

    func fetchReal(all: Bool = true) {
        for i in assets.indices {
            let s = assets[i].sym
            guard !s.isEmpty else { continue }
            let crypto = assets[i].kind == .crypto
            if !all && !crypto { continue }
            let link = crypto
                ? "https://api.coinbase.com/v2/prices/\(s)-USD/spot"
                : "https://query1.finance.yahoo.com/v8/finance/chart/\(s)?interval=1m&range=1d"
            guard let url = URL(string: link) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                var q: Double?
                if let data = data,
                   let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if crypto {
                        if let d = j["data"] as? [String: Any], let a = d["amount"] as? String { q = Double(a) }
                    } else if let c = j["chart"] as? [String: Any],
                              let r = (c["result"] as? [[String: Any]])?.first,
                              let m = r["meta"] as? [String: Any] {
                        q = m["regularMarketPrice"] as? Double
                    }
                }
                DispatchQueue.main.async { self?.applyReal(i, q) }
            }.resume()
        }
    }

    func applyReal(_ i: Int, _ q: Double?) {
        guard live, mode == .sim, i < assets.count else { return }
        guard let q = q, q > 0 else {
            if !assets.contains(where: { $0.real > 0 }) { status = "Нет связи с рынком" }
            return
        }
        let a = assets[i]
        if a.lastReal > 0 {
            assets[i].price = max(1, a.price * (1 + (q / a.lastReal - 1) * Game.boost))
            assets[i].hist[assets[i].hist.count - 1] = assets[i].price
        } else if a.qty == 0 {
            let k = q / a.price
            assets[i].hist = a.hist.map { $0 * k }
            assets[i].price = q
        }
        assets[i].lastReal = q
        assets[i].real = q
        status = "LIVE · " + Game.clock.string(from: Date())
    }

    var soulPrice: Double {
        mode == .real ? 5800 * pow(1.005, Double(day - 1)) : 10000 * pow(1.02, Double(day - 1))
    }
    var maxActions: Int { build == .scalper ? 4 : 3 }
    var fee: Double { build == .scalper ? 0.005 : 0.02 }
    var worth: Double { cash + assets.reduce(0) { $0 + $1.price * $1.qty } }

    func has(_ r: Relic) -> Bool { relics.contains(r) }

    func setMode(_ m: Mode) {
        mode = m
        UserDefaults.standard.set(m == .real, forKey: "realMode")
    }

    func startRun(_ b: Build) {
        guard !loading else { return }
        build = b
        note = ""
        if mode == .sim {
            actions = maxActions
            phase = .play
            return
        }
        loading = true
        Task { @MainActor [self] in
            if let r = await downloadReal() {
                beginReal(r.0, r.1)
            } else {
                note = "Нет данных с бирж, запущена симуляция"
                mode = .sim
                actions = maxActions
                phase = .play
            }
            loading = false
        }
    }

    func beginReal(_ d: [String], _ c: [[Double]]) {
        realDates = d
        realCols = c
        startIdx = Int.random(in: 24...(d.count - 38))
        idx = startIdx
        var list: [Asset] = []
        for (k, s) in Game.realSyms.enumerated() {
            var a = Asset(id: s.name, kind: s.kind, vol: 0.02, price: c[k][idx])
            a.hist = Array(c[k][(idx - 23)...idx])
            list.append(a)
        }
        assets = list
        trend = 0
        log = "Реальный рынок. Период скрыт до конца забега."
        nextInfo = moveText(idx + 1)
        actions = maxActions
        phase = .play
    }

    func moveText(_ day: Int) -> String {
        var best = 0
        var bestChg = 0.0
        for k in realCols.indices {
            let chg = realCols[k][day] / realCols[k][day - 1] - 1
            if abs(chg) >= abs(bestChg) {
                best = k
                bestChg = chg
            }
        }
        let arrow = bestChg >= 0 ? " ▲ " : " ▼ "
        return Game.realSyms[best].name + arrow + String(format: "%.1f", abs(bestChg) * 100) + "%"
    }

    var period: String {
        guard mode == .real, !realDates.isEmpty else { return "" }
        return "Реальный период: \(realDates[startIdx]) — \(realDates[min(idx, realDates.count - 1)])"
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
        if mode == .sim && Double.random(in: 0...1) < 0.25 {
            trend = [-0.03, -0.01, 0, 0.01, 0.03].randomElement()!
        }
        for i in assets.indices {
            let k: Double
            switch assets[i].kind {
            case .stock: k = e.s
            case .fund: k = e.s * 0.6
            case .crypto: k = e.c
            case .realty: k = e.r
            case .metal: k = -e.s * 0.4
            case .energy: k = e.s * 0.8
            }
            let v = assets[i].vol
            if mode == .real {
                assets[i].price = realCols[i][idx + 1]
            } else {
                let tr = assets[i].kind == .realty ? trend * 0.3 : trend
                assets[i].price = max(1, assets[i].price * (1 + k + tr + Double.random(in: -v...v)))
            }
            if assets[i].qty > 0 { assets[i].hold += 1 }
            assets[i].hist.append(assets[i].price)
            if assets[i].hist.count > 40 { assets[i].hist.removeFirst() }
            if assets[i].kind == .realty {
                cash += assets[i].price * assets[i].qty * (build == .rentier ? 0.02 : 0.005)
            }
        }
        worthHist.append(worth)
        if mode == .real { idx += 1 }
        let mood = trend > 0.005 ? " 🐂" : (trend < -0.005 ? " 🐻" : "")
        log = mode == .real ? "День \(day): \(moveText(idx))" : "День \(day): \(e.t)\(mood)"
        day += 1
        actions = maxActions
        next = Game.events.randomElement()!
        nextInfo = mode == .real ? moveText(idx + 1) : next.t
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
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.black.opacity(0.14)))
                    y += 4
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct CRT: View {
    var body: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center,
                       startRadius: 260, endRadius: 600)
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
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.75)).offset(y: 5))
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
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(color))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.35), lineWidth: 2))
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.85)).offset(y: configuration.isPressed ? 1 : 4))
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
    @State private var sel = 0
    @State private var showDetail = false
    @State private var showNews = false
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
        .fullScreenCover(isPresented: $showDetail) { DetailView(g: g, i: sel) }
        .sheet(isPresented: $showNews) { NewsView(g: g) }
    }

    func modeBtn(_ t: String, _ m: Mode) -> some View {
        Button(t) { g.setMode(m) }
            .buttonStyle(Chunky(color: g.mode == m ? T.gold : Color(red: 0.45, green: 0.45, blue: 0.6)))
    }

    var pick: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("SOUL\nMARKET").font(T.f(44)).multilineTextAlignment(.center)
                .foregroundColor(T.gold).shadow(color: T.down, radius: 0, x: 3, y: 4)
            Text("Твою душу выставили на рынок как актив. Выбери режим и стиль.")
                .font(T.f(14, .semibold)).foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                modeBtn("🎲 СИМУЛЯЦИЯ", .sim)
                modeBtn("🌍 РЕАЛЬНАЯ ИСТОРИЯ", .real)
            }
            Text(g.mode == .real
                 ? "Реальные цены акций, ETF-фондов, крипты и REIT с бирж. Случайный период из последних 2 лет, даты скрыты до конца забега."
                 : "Динамический рынок: события, бычьи 🐂 и медвежьи 🐻 полосы.")
                .font(T.f(12, .semibold)).foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if g.loading { ProgressView("Загружаю котировки…").tint(T.gold) }
            if !g.note.isEmpty { Text(g.note).font(T.f(12)).foregroundColor(T.down) }
            ForEach(Array(Build.allCases.enumerated()), id: \.offset) { i, b in
                BigCard(icon: b.icon, title: b.rawValue, info: b.info, tilt: Double(i - 1) * 1.5) {
                    g.startRun(b)
                }
            }
            Spacer()
        }
        .padding(20)
        .disabled(g.loading)
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
                    if g.mode == .sim { liveSwitch }
                    newsBtn
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
                Text(g.mode == .real ? "🌍" : "🎲").font(T.f(14))
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

    var newsBtn: some View {
        Button("📰 РЕАЛЬНЫЕ НОВОСТИ РЫНКА") { showNews = true }
            .buttonStyle(Chunky(color: T.violet))
    }

    var liveSwitch: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button("🎲 ЖИВАЯ СИМУЛЯЦИЯ") { g.setLive(false) }
                    .buttonStyle(Chunky(color: g.live ? Color(red: 0.45, green: 0.45, blue: 0.6) : T.gold))
                Button("📡 РЕАЛЬНЫЕ ЦЕНЫ") { g.setLive(true) }
                    .buttonStyle(Chunky(color: g.live ? T.up : Color(red: 0.45, green: 0.45, blue: 0.6)))
            }
            if g.live {
                Text(g.status + " · реальные движения ×20")
                    .font(T.f(11, .semibold)).foregroundColor(T.up)
            }
        }
    }

    var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📰 \(g.log)").font(T.f(14))
            if g.has(.insider) {
                Text("👁 Завтра: \(g.nextInfo)").font(T.f(13)).foregroundColor(T.gold)
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
        case .fund: return "ФОНД (ETF)"
        case .crypto: return "КРИПТА"
        case .realty: return "НЕДВИЖИМОСТЬ"
        case .metal: return "МЕТАЛЛ"
        case .energy: return "СЫРЬЁ"
        }
    }

    func row(_ i: Int) -> some View {
        let a = g.assets[i]
        let prev = a.hist.count > 1 ? a.hist[a.hist.count - 2] : a.price
        let chg = (a.price / prev - 1) * 100
        let col = chg >= 0 ? T.up : T.down
        let pct = (chg >= 0 ? "▲ " : "▼ ") + String(format: "%.1f", abs(chg)) + "%"
        let q = String(format: a.qty < 1 ? "%.4f" : "%.2f", a.qty)
        let pnl = (a.price - a.cost) * a.qty
        let pnlText = (pnl >= 0 ? "+" : "-") + money(abs(pnl))
        let isLive = g.live && g.mode == .sim && a.real > 0
        let sub = isLive ? a.sym + " · $" + String(format: "%.2f", a.real) + " LIVE" : kindName(a.kind)
        return VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.id.uppercased()).font(T.f(20))
                    Text(sub).font(T.f(11, .semibold)).foregroundColor(isLive ? T.up : Color.white.opacity(0.5))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(px(a.price)).font(T.f(20))
                    Text(pct).font(T.f(12))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(col)).foregroundColor(.black)
                }
            }
            Spark(pts: a.hist, color: col).frame(height: 54)
            Text("📊 график · стакан · новости · описание ›")
                .font(T.f(11, .semibold)).foregroundColor(Color.white.opacity(0.4))
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
        .contentShape(Rectangle())
        .onTapGesture { sel = i; showDetail = true }
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
            if g.mode == .real {
                Text(g.period).font(T.f(13, .semibold)).foregroundColor(T.gold)
                    .multilineTextAlignment(.center)
            }
            Text("День \(g.day) · капитал \(money(g.worth))").font(T.f(16)).panel(c.opacity(0.6))
            Button("НОВЫЙ ЗАБЕГ", action: restart)
                .buttonStyle(Chunky(color: c))
                .frame(width: 220)
        }
        .padding(24)
    }
}

// MARK: - Asset library

struct AInfo {
    let name: String
    let type: String
    let about: String
    let drivers: [String]
    let query: String
}

enum Lib {
    static let table: [String: AInfo] = [
        "AAPL": AInfo(name: "Apple Inc.", type: "Акции · технологии",
            about: "Производитель iPhone, Mac, iPad и носимых устройств. Всё больше зарабатывает на сервисах: App Store, iCloud, Apple Music, платежи. Одна из крупнейших компаний мира.",
            drivers: ["Продажи iPhone и циклы новых моделей", "Рост выручки от сервисов", "Пошлины, регуляторы и иски вокруг App Store", "Цепочки поставок и Китай", "Ставки ФРС и настроение технологического сектора"],
            query: "Apple акции AAPL"),
        "NVDA": AInfo(name: "NVIDIA Corp.", type: "Акции · чипы и ИИ",
            about: "Разработчик графических процессоров и ускорителей для дата-центров и искусственного интеллекта. Платформа CUDA удерживает разработчиков в её экосистеме.",
            drivers: ["Инвестиции облачных гигантов в ИИ-инфраструктуру", "Квартальные отчёты и прогнозы компании", "Экспортные ограничения на чипы в Китай", "Конкуренция AMD и собственные чипы клиентов"],
            query: "Nvidia акции"),
        "SPY": AInfo(name: "SPDR S&P 500 ETF", type: "Фонд (ETF) · индекс США",
            about: "Крупнейший фонд на индекс S&P 500, в который входят 500 самых больших публичных компаний США. Показывает общее состояние американского рынка акций.",
            drivers: ["Ставки и заявления ФРС", "Инфляция и данные по рынку труда", "Сезон корпоративных отчётов", "Геополитика и торговые войны"],
            query: "S&P 500 индекс"),
        "QQQ": AInfo(name: "Invesco QQQ", type: "Фонд (ETF) · Nasdaq-100",
            about: "Фонд на 100 крупнейших нефинансовых компаний Nasdaq. Сильно зависит от технологических гигантов и темы искусственного интеллекта.",
            drivers: ["Отчёты Apple, Microsoft, Nvidia, Amazon, Google, Meta", "Доходности облигаций США", "Ажиотаж вокруг ИИ", "Регулирование Big Tech"],
            query: "Nasdaq 100 индекс"),
        "BTC": AInfo(name: "Bitcoin", type: "Криптовалюта",
            about: "Первая и самая крупная криптовалюта с жёстким лимитом эмиссии в 21 млн монет. Многие считают её цифровым золотом. Торгуется круглосуточно.",
            drivers: ["Потоки денег в биткоин-ETF", "Ставки ФРС и глобальная ликвидность", "Регуляторы и законы о крипте", "Крупные держатели и биржи", "Цикл халвинга"],
            query: "биткоин курс"),
        "ETH": AInfo(name: "Ethereum", type: "Криптовалюта",
            about: "Платформа смарт-контрактов, на которой работают DeFi, NFT и тысячи приложений. Держатели могут зарабатывать на стейкинге.",
            drivers: ["Активность в сети и комиссии", "Обновления протокола", "ETF и стейкинг", "Общее настроение крипторынка и курс биткоина"],
            query: "эфириум курс"),
        "VNQ": AInfo(name: "Vanguard Real Estate ETF", type: "Фонд (ETF) · недвижимость",
            about: "Фонд на американские REIT, компании, владеющие недвижимостью: офисами, складами, торговыми центрами, жильём и дата-центрами. Платит дивиденды.",
            drivers: ["Ставки: рост ставок давит на недвижимость", "Ипотечные ставки и спрос на жильё", "Заполняемость офисов", "Арендные ставки"],
            query: "рынок недвижимости REIT ставки"),
        "O": AInfo(name: "Realty Income", type: "Акции · REIT",
            about: "Владеет тысячами объектов торговой недвижимости, сдаваемых в долгую аренду. Известна ежемесячными дивидендами.",
            drivers: ["Ставки: дивидендные бумаги чувствительны к ним", "Заполняемость и арендаторы", "Покупки новых объектов", "Рост дивиденда"],
            query: "Realty Income REIT"),
        "XAU": AInfo(name: "Золото", type: "Металл · фьючерс GC",
            about: "Классический защитный актив. Растёт, когда инвесторы боятся инфляции и кризисов, и обычно слабо связано с акциями.",
            drivers: ["Реальные ставки и курс доллара", "Инфляция", "Покупки золота центробанками", "Геополитика и страх на рынках"],
            query: "золото цена"),
        "XAG": AInfo(name: "Серебро", type: "Металл · фьючерс SI",
            about: "Одновременно защитный и промышленный металл: нужен для солнечных панелей, электроники и медицины. Колеблется сильнее золота.",
            drivers: ["Цена золота", "Промышленный спрос, солнечная энергетика", "Курс доллара", "Запасы на складах"],
            query: "серебро цена"),
        "WTI": AInfo(name: "Нефть WTI", type: "Сырьё · фьючерс CL",
            about: "Эталонная американская нефть. От её цены зависят бензин, транспорт и инфляция, а также доходы нефтяных стран и компаний.",
            drivers: ["Решения ОПЕК+ по добыче", "Запасы нефти в США (отчёт EIA)", "Спрос Китая и мировая экономика", "Конфликты на Ближнем Востоке", "Курс доллара"],
            query: "нефть цена ОПЕК"),
        "NG": AInfo(name: "Природный газ", type: "Сырьё · фьючерс NG",
            about: "Топливо для электростанций и отопления, основа экспорта СПГ. Цена сильно зависит от погоды и запасов в хранилищах.",
            drivers: ["Погода: холодная зима или жаркое лето", "Запасы газа в хранилищах США", "Экспорт СПГ", "Объёмы добычи"],
            query: "природный газ цены")
    ]

    static func info(_ id: String) -> AInfo {
        table[id.uppercased()] ?? AInfo(name: id, type: "Актив", about: "Описание недоступно.", drivers: [], query: id)
    }
}

// MARK: - Real news (Google News RSS)

struct NewsItem: Identifiable {
    let id = UUID()
    let title: String
    let source: String
    let date: Date?
    let link: URL?
}

final class RSSParser: NSObject, XMLParserDelegate {
    var items: [NewsItem] = []
    private var inItem = false
    private var el = ""
    private var title = ""
    private var link = ""
    private var pub = ""
    private var src = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        el = elementName
        if elementName == "item" {
            inItem = true
            title = ""
            link = ""
            pub = ""
            src = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch el {
        case "title": title += string
        case "link": link += string
        case "pubDate": pub += string
        case "source": src += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "item" {
            inItem = false
            var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let s = src.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty, t.hasSuffix(" - " + s) { t = String(t.dropLast(s.count + 3)) }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let d = f.date(from: pub.trimmingCharacters(in: .whitespacesAndNewlines))
            let u = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))
            items.append(NewsItem(title: t, source: s, date: d, link: u))
        }
        el = ""
    }
}

func fetchNews(_ query: String) async -> [NewsItem] {
    guard var c = URLComponents(string: "https://news.google.com/rss/search") else { return [] }
    c.queryItems = [
        URLQueryItem(name: "q", value: query + " when:7d"),
        URLQueryItem(name: "hl", value: "ru"),
        URLQueryItem(name: "gl", value: "RU"),
        URLQueryItem(name: "ceid", value: "RU:ru")
    ]
    guard let url = c.url else { return [] }
    var req = URLRequest(url: url)
    req.timeoutInterval = 15
    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
    let p = RSSParser()
    let x = XMLParser(data: data)
    x.delegate = p
    x.parse()
    return Array(p.items.prefix(12))
}

struct NewsRow: View {
    let n: NewsItem
    static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        let when = n.date.map { NewsRow.rel.localizedString(for: $0, relativeTo: Date()) } ?? ""
        let card = VStack(alignment: .leading, spacing: 4) {
            Text(n.title).font(T.f(14, .semibold)).foregroundColor(.white)
                .multilineTextAlignment(.leading)
            Text(n.source + (when.isEmpty ? "" : " · " + when))
                .font(T.f(11, .semibold)).foregroundColor(T.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        return Group {
            if let u = n.link {
                Link(destination: u) { card }
            } else {
                card
            }
        }
    }
}

// MARK: - Exchange-style chart

func px(_ v: Double) -> String {
    v >= 100 ? "$\(Int(v))" : "$" + String(format: "%.2f", v)
}

func rnd(_ a: Double, _ b: Double, _ c: Double) -> Double {
    let s = sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return s - floor(s)
}

struct Candle { let o: Double; let h: Double; let l: Double; let c: Double; let v: Double }

func makeCandles(_ a: Asset, _ n: Int) -> [Candle] {
    let p = a.hist
    guard p.count > 1 else { return [] }
    var out: [Candle] = []
    for k in max(1, p.count - n)..<p.count {
        let o = p[k - 1]
        let c = p[k]
        let w = max(abs(c - o) * 0.6, c * a.vol * 0.3) * rnd(o, c, 1)
        out.append(Candle(o: o, h: max(o, c) + w * rnd(o, c, 2), l: min(o, c) - w * rnd(o, c, 3),
                          c: c, v: (0.4 + rnd(o, c, 4)) * (1 + abs(c / o - 1) * 25)))
    }
    return out
}

func sma(_ p: [Double], _ n: Int) -> [Double?] {
    p.indices.map { i -> Double? in
        i + 1 < n ? nil : p[(i + 1 - n)...i].reduce(0, +) / Double(n)
    }
}

struct CandleChart: View {
    let cs: [Candle]
    let m1: [Double?]
    let m2: [Double?]
    let last: Double
    let up: Bool

    var body: some View {
        Canvas { ctx, size in
            guard !cs.isEmpty else { return }
            let axis: CGFloat = 58
            let w = size.width - axis
            let volH = size.height * 0.2
            let ph = size.height - volH - 10
            let lo = cs.map { $0.l }.min() ?? 0
            let hi = cs.map { $0.h }.max() ?? 1
            let rng = max(hi - lo, 0.0001)
            func y(_ v: Double) -> CGFloat { ph * CGFloat(1 - (v - lo) / rng) }
            let step = w / CGFloat(cs.count)
            let small = Font.system(size: 10, weight: .semibold, design: .rounded)

            for k in 0...4 {
                let v = lo + rng * Double(k) / 4
                let yy = y(v)
                var gl = Path()
                gl.move(to: CGPoint(x: 0, y: yy))
                gl.addLine(to: CGPoint(x: w, y: yy))
                ctx.stroke(gl, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
                ctx.draw(Text(String(format: v >= 100 ? "%.0f" : "%.2f", v)).font(small).foregroundColor(.gray),
                         at: CGPoint(x: w + 6, y: yy), anchor: .leading)
            }

            let maxV = cs.map { $0.v }.max() ?? 1
            for (i, c) in cs.enumerated() {
                let x = CGFloat(i) * step + step / 2
                let col: Color = c.c >= c.o ? T.up : T.down
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(c.h)))
                wick.addLine(to: CGPoint(x: x, y: y(c.l)))
                ctx.stroke(wick, with: .color(col), lineWidth: 1.2)
                let top = min(y(c.o), y(c.c))
                let bh = max(1.5, abs(y(c.o) - y(c.c)))
                ctx.fill(Path(CGRect(x: x - step * 0.3, y: top, width: step * 0.6, height: bh)), with: .color(col))
                let vh = volH * CGFloat(c.v / maxV)
                ctx.fill(Path(CGRect(x: x - step * 0.3, y: size.height - vh, width: step * 0.6, height: vh)),
                         with: .color(col.opacity(0.45)))
            }

            let lines: [([Double?], Color)] = [(m1, Color(red: 0.3, green: 0.6, blue: 1.0)), (m2, Color.orange)]
            for (ma, col) in lines {
                var p = Path()
                var started = false
                for (i, v) in ma.enumerated() {
                    guard let v = v else { continue }
                    let pt = CGPoint(x: CGFloat(i) * step + step / 2, y: y(v))
                    if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                }
                ctx.stroke(p, with: .color(col), lineWidth: 1.6)
            }

            let tagCol: Color = up ? T.up : T.down
            let yl = y(last)
            var dash = Path()
            dash.move(to: CGPoint(x: 0, y: yl))
            dash.addLine(to: CGPoint(x: w, y: yl))
            ctx.stroke(dash, with: .color(tagCol), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            let tag = CGRect(x: w + 1, y: yl - 9, width: axis - 2, height: 18)
            ctx.fill(Path(roundedRect: tag, cornerRadius: 4), with: .color(tagCol))
            ctx.draw(Text(String(format: last >= 100 ? "%.2f" : "%.3f", last))
                        .font(Font.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white),
                     at: CGPoint(x: tag.midX, y: tag.midY))
        }
    }
}

// MARK: - Asset screen

struct DetailView: View {
    @ObservedObject var g: Game
    let i: Int
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var n = 20

    var a: Asset { g.assets[min(i, g.assets.count - 1)] }
    var info: AInfo { Lib.info(a.id) }
    var prev: Double { a.hist.count > 1 ? a.hist[a.hist.count - 2] : a.price }
    var chg: Double { (a.price / prev - 1) * 100 }
    var col: Color { chg >= 0 ? T.up : T.down }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                tabBar
                ScrollView {
                    VStack(spacing: 12) {
                        switch tab {
                        case 0: chartTab
                        case 1: bookTab
                        case 2: newsTab
                        default: infoTab
                        }
                    }
                    .padding(16)
                }
                bottomBar
            }
        }
        .onAppear { g.loadNews(a.id, info.query) }
    }

    var topBar: some View {
        let cs = makeCandles(a, 2)
        let hi = cs.last?.h ?? a.price
        let lo = cs.last?.l ?? a.price
        let pct = (chg >= 0 ? "▲ +" : "▼ -") + String(format: "%.2f", abs(chg)) + "%"
        return VStack(spacing: 6) {
            HStack(alignment: .top) {
                Button { dismiss() } label: {
                    Text("‹").font(T.f(34)).foregroundColor(.white).padding(.trailing, 8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name).font(T.f(18)).foregroundColor(.white)
                    Text(a.id + " · " + info.type).font(T.f(11, .semibold)).foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(px(a.price)).font(T.f(24)).foregroundColor(col)
                    Text(pct).font(T.f(12))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(col)).foregroundColor(.black)
                }
            }
            HStack {
                Text("Откр " + px(prev)).foregroundColor(.gray)
                Text("Макс " + px(hi)).foregroundColor(T.up)
                Text("Мин " + px(lo)).foregroundColor(T.down)
                Spacer()
                if g.live && g.mode == .sim && a.real > 0 {
                    Text("LIVE " + px(a.real)).foregroundColor(T.up)
                }
            }
            .font(T.f(11, .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(["График", "Стакан", "Новости", "Инфо"].enumerated()), id: \.offset) { k, t in
                Button { tab = k } label: {
                    Text(t).font(T.f(13)).foregroundColor(tab == k ? .black : .white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(tab == k ? T.gold : Color.white.opacity(0.1)))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    func tfButton(_ t: String, _ k: Int) -> some View {
        Button { n = k } label: {
            Text(t).font(T.f(12)).foregroundColor(n == k ? .black : .gray)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(n == k ? Color.white : Color.white.opacity(0.08)))
        }
    }

    var chartTab: some View {
        let cs = makeCandles(a, n)
        let start = max(1, a.hist.count - n)
        let all1 = sma(a.hist, 5)
        let all2 = sma(a.hist, 10)
        let m1: [Double?] = start < all1.count ? Array(all1[start...]) : []
        let m2: [Double?] = start < all2.count ? Array(all2[start...]) : []
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                tfButton("10Д", 10)
                tfButton("20Д", 20)
                tfButton("40Д", 40)
                Spacer()
                Text("MA5").font(T.f(11)).foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                Text("MA10").font(T.f(11)).foregroundColor(.orange)
            }
            CandleChart(cs: cs, m1: m1, m2: m2, last: a.price, up: chg >= 0)
                .frame(height: 340)
            Text("Свеча = один игровой день. Объёмы условные.")
                .font(T.f(10, .semibold)).foregroundColor(.gray)
            positionCard
        }
    }

    var positionCard: some View {
        let pnl = (a.price - a.cost) * a.qty
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ПОЗИЦИЯ").font(T.f(11)).foregroundColor(.gray)
                Text(a.qty > 0 ? String(format: "%.4f", a.qty) + " шт." : "нет").font(T.f(16)).foregroundColor(.white)
            }
            Spacer()
            if a.qty > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("P&L").font(T.f(11)).foregroundColor(.gray)
                    Text((pnl >= 0 ? "+" : "-") + money(abs(pnl))).font(T.f(16))
                        .foregroundColor(pnl >= 0 ? T.up : T.down)
                }
            }
        }
        .panel()
    }

    func bookRow(_ price: Double, _ k: Int, _ ask: Bool) -> some View {
        let size = (0.15 + rnd(Double(Int(price * 10)), Double(k), ask ? 1 : 2)) * 100
        let c: Color = ask ? T.down : T.up
        return HStack {
            Text(px(price)).font(T.f(13)).foregroundColor(c)
            Spacer()
            Text(String(format: "%.1f", size)).font(T.f(13, .semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            GeometryReader { geo in
                c.opacity(0.18).frame(width: geo.size.width * CGFloat(size / 120))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        )
    }

    var bookTab: some View {
        let step = max(a.price * 0.0006, 0.01)
        return VStack(spacing: 2) {
            ForEach(Array((1...7).reversed()), id: \.self) { k in bookRow(a.price + step * Double(k), k, true) }
            Text(px(a.price)).font(T.f(20)).foregroundColor(col).padding(.vertical, 6)
            ForEach(1...7, id: \.self) { k in bookRow(a.price - step * Double(k), k, false) }
            Text("Учебный стакан заявок: размеры условные.")
                .font(T.f(10, .semibold)).foregroundColor(.gray).padding(.top, 8)
        }
    }

    var newsTab: some View {
        let items = g.news[a.id] ?? []
        return VStack(spacing: 10) {
            if g.newsBusy.contains(a.id) && items.isEmpty {
                ProgressView("Загружаю новости…").tint(T.gold)
            } else if items.isEmpty {
                Text("Новости не загрузились.").font(T.f(13, .semibold)).foregroundColor(.gray)
            }
            ForEach(items) { item in NewsRow(n: item) }
            Button("🔄 ОБНОВИТЬ") { g.loadNews(a.id, info.query) }
                .buttonStyle(Chunky(color: T.violet))
            Text("Реальные заголовки из Google News за последние 7 дней.")
                .font(T.f(10, .semibold)).foregroundColor(.gray)
        }
    }

    var infoTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(info.name).font(T.f(22)).foregroundColor(T.gold)
            Text(info.type).font(T.f(12, .semibold)).foregroundColor(.gray)
            Text(info.about).font(T.f(14, .semibold)).foregroundColor(.white)
            Text("ЧТО ВЛИЯЕТ НА ЦЕНУ").font(T.f(12)).foregroundColor(T.violet).padding(.top, 6)
            ForEach(info.drivers, id: \.self) { d in
                Text("• " + d).font(T.f(13, .semibold)).foregroundColor(Color.white.opacity(0.85))
            }
            if g.live && g.mode == .sim && a.real > 0 {
                Text("Реальная котировка сейчас: " + px(a.real)).font(T.f(13)).foregroundColor(T.up).padding(.top, 6)
            }
            Text("Описание общее, без актуальных цифр. Свежие события смотри во вкладке «Новости».")
                .font(T.f(10, .semibold)).foregroundColor(.gray).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    var bottomBar: some View {
        HStack(spacing: 10) {
            Button("ПРОДАТЬ") { g.sell(i) }
                .buttonStyle(Chunky(color: T.down))
                .disabled(a.qty == 0 || g.actions == 0)
            Button("КУПИТЬ ¼ · \(g.actions)⚡") { g.buy(i, 0.25) }
                .buttonStyle(Chunky(color: T.up))
                .disabled(g.actions == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.4))
    }
}

// MARK: - Market news

struct NewsView: View {
    @ObservedObject var g: Game
    @Environment(\.dismiss) private var dismiss
    @State private var cat = 0
    static let cats: [(String, String)] = [
        ("Рынки", "фондовый рынок акции S&P 500"),
        ("Нефть", "нефть Brent WTI цена ОПЕК"),
        ("Золото", "золото цена ФРС"),
        ("Крипта", "биткоин эфириум криптовалюты")
    ]

    func load() { g.loadNews("cat\(cat)", NewsView.cats[cat].1) }

    var body: some View {
        let items = g.news["cat\(cat)"] ?? []
        return ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    Button { dismiss() } label: { Text("‹").font(T.f(34)).foregroundColor(.white) }
                    Text("РЕАЛЬНЫЕ НОВОСТИ").font(T.f(18)).foregroundColor(T.gold)
                    Spacer()
                }
                HStack(spacing: 8) {
                    ForEach(Array(NewsView.cats.enumerated()), id: \.offset) { k, c in
                        Button { cat = k } label: {
                            Text(c.0).font(T.f(13)).foregroundColor(cat == k ? .black : .white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(cat == k ? T.gold : Color.white.opacity(0.1)))
                        }
                    }
                    Spacer()
                }
                ScrollView {
                    VStack(spacing: 10) {
                        if g.newsBusy.contains("cat\(cat)") && items.isEmpty {
                            ProgressView("Загружаю…").tint(T.gold)
                        } else if items.isEmpty {
                            Text("Новости не загрузились.").font(T.f(13, .semibold)).foregroundColor(.gray)
                        }
                        ForEach(items) { item in NewsRow(n: item) }
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(16)
        }
        .onAppear { load() }
        .onChange(of: cat) { _ in load() }
    }
}
