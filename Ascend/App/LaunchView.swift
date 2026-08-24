import SwiftUI
import AscendKit

/// Launch screen: the mark, a quote, then out of the way.
///
/// Held just long enough to read one short line. Anything longer is a tax on
/// every single launch, so it dissolves rather than waiting for a tap, and the
/// app underneath is already built and ready behind it.
struct LaunchView: View {
    var onFinished: () -> Void

    @State private var markShown = false
    @State private var quoteShown = false

    private let quote = Quotes.today()

    /// Long enough to read six or seven words, short enough not to be in the
    /// way. Reduced-motion users skip the animation and get the same duration.
    private let hold: TimeInterval = 1.4

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.97, blue: 0.94),
                         Color(red: 1.0, green: 0.84, blue: 0.71)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                chevrons
                    .frame(width: 96, height: 76)
                    .opacity(markShown ? 1 : 0)
                    .scaleEffect(markShown ? 1 : 0.86)

                Text(quote.text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(red: 0.35, green: 0.22, blue: 0.14))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                    .opacity(quoteShown ? 1 : 0)
            }
        }
        .onAppear(perform: run)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ascend. \(quote.text)")
    }

    /// The app mark, drawn rather than loaded, so it scales cleanly and stays in
    /// step with the icon without a second asset to keep aligned.
    private var chevrons: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                chevron(width: w, height: h, yOffset: h * 0.42)
                    .stroke(Color(red: 1.0, green: 0.77, blue: 0.60),
                            style: .init(lineWidth: w * 0.17, lineCap: .round, lineJoin: .round))
                chevron(width: w, height: h, yOffset: 0)
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 0.94, green: 0.26, blue: 0.04),
                                     Color(red: 1.0, green: 0.54, blue: 0.24)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        style: .init(lineWidth: w * 0.17, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }

    private func chevron(width: CGFloat, height: CGFloat, yOffset: CGFloat) -> Path {
        var path = Path()
        let inset = width * 0.09
        path.move(to: CGPoint(x: inset, y: height * 0.5 + yOffset))
        path.addLine(to: CGPoint(x: width / 2, y: height * 0.12 + yOffset))
        path.addLine(to: CGPoint(x: width - inset, y: height * 0.5 + yOffset))
        return path
    }

    private func run() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            markShown = true
            quoteShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) { onFinished() }
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { markShown = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.22)) { quoteShown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { onFinished() }
    }
}
