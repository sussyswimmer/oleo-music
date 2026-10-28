import SwiftUI

/// The time in a large thin font with the date above it, like the iPhone lock
/// screen. No seconds, so it only redraws once a minute.
struct BigClockView: View {
    let fontSize: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: fontSize * 0.04) {
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: fontSize * 0.2, weight: .medium))
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: fontSize, weight: .thin))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 8)
        }
    }
}
