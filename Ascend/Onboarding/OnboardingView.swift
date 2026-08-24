import SwiftUI
import AscendKit

/// One question, no permission prompts. Notifications, Health and nutrition
/// tracking are all opt-in later from Settings.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var daysPerWeek = 4

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.orange)
                Text("How many days a week\ndo you want to train?")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("You can change this later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(2...6, id: \.self) { day in
                    Button {
                        daysPerWeek = day
                    } label: {
                        Text("\(day)")
                            .font(.title3.weight(.semibold))
                            .frame(width: 50, height: 50)
                            .background(
                                Circle().fill(daysPerWeek == day
                                              ? Color.primary
                                              : Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(daysPerWeek == day ? Color(.systemBackground) : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day) days per week")
                    .accessibilityAddTraits(daysPerWeek == day ? [.isSelected] : [])
                }
            }

            Text(splitDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                store.createPlan(daysPerWeek: daysPerWeek)
            } label: {
                Text("Create my plan")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color(.systemBackground))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var splitDescription: String {
        switch daysPerWeek {
        case 2:  return "Two full-body sessions with plenty of recovery between them."
        case 3:  return "A push, pull and legs split."
        case 4:  return "Upper and lower body, twice each."
        case 5:  return "A dedicated day per muscle group."
        default: return "Push, pull and legs, run twice over."
        }
    }
}
