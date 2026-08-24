import SwiftUI
import AscendKit

/// Three questions, then a plan you can see the reasoning for.
///
/// Still no permission prompts anywhere in here. Notifications, Health and
/// nutrition are all opt-in later from Settings.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    @State private var step = 0
    @State private var daysPerWeek = 4
    @State private var experience: PlanRecommender.Experience = .returning
    @State private var equipment: PlanRecommender.Equipment = .fullGym

    private var recommendation: PlanRecommender.Recommendation {
        PlanRecommender.recommend(.init(
            daysPerWeek: daysPerWeek, experience: experience, equipment: equipment
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
            TabView(selection: $step) {
                daysStep.tag(0)
                experienceStep.tag(1)
                equipmentStep.tag(2)
                summaryStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { index in
                Capsule()
                    .fill(index <= step ? Color.orange : Color.secondary.opacity(0.22))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Steps

    private var daysStep: some View {
        step(
            title: "How many days a week\ncan you train?",
            subtitle: "Be honest — a plan you actually finish beats an ambitious one."
        ) {
            HStack(spacing: 10) {
                ForEach(2...6, id: \.self) { day in
                    choiceCircle(label: "\(day)", selected: daysPerWeek == day) {
                        daysPerWeek = day
                    }
                }
            }
        }
    }

    private var experienceStep: some View {
        step(
            title: "How long have you\nbeen lifting?",
            subtitle: "This changes how much we start you with, not how hard it is."
        ) {
            VStack(spacing: 10) {
                ForEach(PlanRecommender.Experience.allCases, id: \.self) { option in
                    choiceRow(label: option.displayName, selected: experience == option) {
                        experience = option
                    }
                }
            }
        }
    }

    private var equipmentStep: some View {
        step(
            title: "What can you\nget your hands on?",
            subtitle: "We will only plan exercises you can actually do."
        ) {
            VStack(spacing: 10) {
                ForEach(PlanRecommender.Equipment.allCases, id: \.self) { option in
                    choiceRow(label: option.displayName, selected: equipment == option) {
                        equipment = option
                    }
                }
            }
        }
    }

    /// Shows the recommendation *and* why, because a suggestion you cannot
    /// justify is just an assertion.
    private var summaryStep: some View {
        let plan = recommendation

        return VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 8) {
                Text(plan.splitName)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("\(plan.daysPerWeek) days a week")
                    .font(.headline)
                    .foregroundStyle(Color.orange)
            }

            Text(plan.rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if plan.daysPerWeek < daysPerWeek {
                Label(
                    "Starting at \(plan.daysPerWeek) rather than \(daysPerWeek). You can raise it once this feels easy.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 10) {
                primaryButton("Create my plan") {
                    store.createRecommendedPlan(
                        .init(daysPerWeek: daysPerWeek, experience: experience, equipment: equipment)
                    )
                }
                Button("Back") { step = 2 }
                    .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func step<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            content()
                .padding(.horizontal, 24)
            Spacer()
            primaryButton("Continue") { step += 1 }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private func choiceCircle(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title3.weight(.semibold))
                .frame(width: 50, height: 50)
                .background(Circle().fill(selected ? Color.primary : Color.secondary.opacity(0.12)))
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func choiceRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(selected ? 0.14 : 0.07))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Color(.systemBackground))
        }
    }
}
