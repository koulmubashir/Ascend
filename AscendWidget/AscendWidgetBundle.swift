import SwiftUI
import WidgetKit

@main
struct AscendWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextWorkoutWidget()
        // Live Activities need iOS 16.1; the home screen widget does not.
        if #available(iOS 16.1, *) {
            WorkoutLiveActivity()
        }
    }
}
