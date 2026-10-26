import Foundation

/// Both washing modes add dirt progressively, reaching the darkest color after ten uses.
struct BucketWaterState {
    static let maximumWashes = 10
    /// Completed uses in either washing mode.
    private(set) var completedWashes: Int
    private(set) var dirtAmount: Double
    var usesSoap: Bool
    private struct Wash {
        let startAmount: Double
    }
    private var wash: Wash?

    init(completedWashes: Int = 0, usesSoap: Bool = false, dirtAmount: Double? = nil) {
        self.completedWashes = min(Self.maximumWashes, max(0, completedWashes))
        let previous = Double(self.completedWashes)
        let saved = dirtAmount.flatMap { $0.isFinite ? $0 : nil } ?? previous
        self.dirtAmount = min(Double(Self.maximumWashes), max(previous, saved))
        self.usesSoap = usesSoap
    }

    mutating func beginWash() {
        guard wash == nil else { return }
        wash = Wash(startAmount: dirtAmount)
    }

    /// The caller supplies actual wet-time progress, not a synthesized sink phase.
    mutating func advanceWash(progress: Double) {
        guard let wash = wash, progress.isFinite else { return }
        let start = wash.startAmount
        let t = min(1, max(0, progress))
        let eased = t * t * (3 - 2 * t)
        let target = min(Double(Self.maximumWashes), start + 1)
        dirtAmount = max(dirtAmount, start + (target - start) * eased)
    }

    mutating func recordCompletedWash() {
        guard let wash = wash else { return }
        dirtAmount = min(Double(Self.maximumWashes), wash.startAmount + 1)
        completedWashes = min(Self.maximumWashes, completedWashes + 1)
        self.wash = nil
    }

    /// An interrupted wash keeps the color already visible, without counting a completion.
    mutating func finishWash(completed: Bool = false) {
        if completed { recordCompletedWash() }
        else { wash = nil }
    }

    mutating func changeWater() {
        completedWashes = 0
        dirtAmount = 0
        wash = nil
    }

    /// Each application launch starts with fresh water and soap switched off.
    static func loadForLaunch(from _: UserDefaults) -> Self {
        Self()
    }

    static func load(from defaults: UserDefaults) -> Self {
        // Preferences without a scale marker use the original five-use palette.
        // Doubling that amount retains its existing color in the ten-use palette.
        let sourceMaximum = defaults.integer(forKey: "waterDirtScale") == Self.maximumWashes
            ? Self.maximumWashes : 5
        let multiplier = Self.maximumWashes / sourceMaximum
        let completed = min(sourceMaximum, max(0, defaults.integer(forKey: "waterCompletedWashes")))
        let amount = (defaults.object(forKey: "waterDirtAmount") as? NSNumber)?.doubleValue
        let scaledAmount = amount.flatMap { value -> Double? in
            guard value.isFinite else { return nil }
            return min(Double(sourceMaximum), max(0, value)) * Double(multiplier)
        }
        return Self(completedWashes: completed * multiplier,
                    usesSoap: defaults.bool(forKey: "washWithSoap"),
                    dirtAmount: scaledAmount)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(completedWashes, forKey: "waterCompletedWashes")
        defaults.set(dirtAmount, forKey: "waterDirtAmount")
        defaults.set(Self.maximumWashes, forKey: "waterDirtScale")
        defaults.set(usesSoap, forKey: "washWithSoap")
    }

    var soapActionTitle: String { usesSoap ? "Wash without soap" : "Wash with soap" }
}
