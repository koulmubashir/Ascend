import Foundation

/// Short lines shown on the launch screen.
///
/// Deliberately about effort, consistency and turning up rather than about
/// bodies or results. The app tracks what you did; it should not imply how you
/// ought to look, and a launch screen is exactly where that would land worst.
///
/// Kept blunt and unattributed. Half the quotes in circulation are misattributed
/// anyway, and a name on a launch screen invites arguing with it.
public struct Quote: Hashable, Sendable, Identifiable {
    public let text: String
    public var id: String { text }

    public init(_ text: String) { self.text = text }
}

public enum Quotes {

    public static let all: [Quote] = [
        Quote("The workout you did is worth more than the one you planned."),
        Quote("Turning up is most of it."),
        Quote("Small sets, stacked."),
        Quote("Nobody regrets the session they finished."),
        Quote("Progress is boring. Do it anyway."),
        Quote("The bar does not care how you feel."),
        Quote("Consistency beats intensity, over a year."),
        Quote("A light day still counts."),
        Quote("You are competing with last week."),
        Quote("Rest is part of the plan, not a break from it."),
        Quote("Add a rep. That is the whole strategy."),
        Quote("The hardest set is the one you start."),
        Quote("Slow is fine. Stopping is the problem."),
        Quote("Strength is just showing up, repeated."),
        Quote("Two good sets beat five rushed ones."),
        Quote("Today's session is tomorrow's baseline."),
        Quote("Form first. The weight will wait."),
        Quote("Missed a day? Start from where you are."),
        Quote("You do not need motivation. You need a plan."),
        Quote("Finish the set you are in.")
    ]

    /// A quote for a given day. Stable within a day so relaunching the app does
    /// not reshuffle it - a line that changes every few seconds reads as noise
    /// rather than something worth reading.
    public static func today(for date: Date = Date(), calendar: Calendar = .current) -> Quote {
        guard !all.isEmpty else { return Quote("") }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[abs(day) % all.count]
    }

    public static func random() -> Quote {
        all.randomElement() ?? Quote("")
    }
}
