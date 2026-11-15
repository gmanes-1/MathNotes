import SwiftUI

/// A clean, compact library heading matching the quieter notebook shelf style.
struct LibraryHeader: View {
    let title: String
    let summary: String
    let showsRhythm: Bool
    let onOpenPage: (NotebookRecord, UUID) -> Void

    @Environment(WritingActivity.self) private var activity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    var body: some View {
        let wide = width >= 600 && !dynamicTypeSize.isAccessibilitySize
        let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: Space.x6))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x3))
        layout {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(Color.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)

            if showsRhythm, activity.isEnabled, activity.hasHistory {
                WeekStrip(week: activity.week, onOpenPage: onOpenPage)
                    .padding(.vertical, Space.x2)
                    .padding(.horizontal, Space.x3)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                    }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Space.x2)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Seven small sheets for this week, inked on the days you wrote, with today underlined. Opens the writing calendar.
struct WeekStrip: View {
    let week: WeekSummary
    let onOpenPage: (NotebookRecord, UUID) -> Void
    @State private var showingCalendar = false

    var body: some View {
        Button { showingCalendar = true } label: {
            HStack(alignment: .bottom, spacing: Space.x3) {
                HStack(spacing: Space.x1) {
                    ForEach(Array(week.days.enumerated()), id: \.element.date) { index, day in
                        VStack(spacing: 3) {
                            DaySheet(pages: day.pages, seed: index)
                            letter(for: day)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(week.pagesLine)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.primary)
                    if week.pageCount > 0 {
                        Text(week.daysLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
                .padding(.bottom, 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.accessibilityLabel)
        .accessibilityHint(Text("Opens your writing calendar"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("writing.week")
        .writingCalendar(isPresented: $showingCalendar, onOpenPage: onOpenPage)
    }

    private func letter(for day: WeekSummary.Day) -> some View {
        let calendar = Calendar.current
        let isToday = day.date == week.today
        return Text(calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day.date) - 1])
            .font(.caption2.weight(isToday ? .heavy : .medium))
            .underline(isToday)
            .foregroundStyle(isToday ? Color.primary : Color.secondary)
            .frame(width: DaySheet.size.width)
    }
}

/// A tiny page: plain paper with a hairline edge, or two or three short lines of ink on a day you wrote.
private struct DaySheet: View {
    static let size = CGSize(width: 22, height: 29)
    let pages: Int
    let seed: Int
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(uiColor: .systemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
            }
            .overlay {
                if pages > 0 {
                    InkLines(count: pages > 1 ? 3 : 2, seed: seed)
                        .stroke(Color.primary.opacity(contrast == .increased ? 1 : 0.72),
                                style: StrokeStyle(lineWidth: 1.15, lineCap: .round))
                        .padding(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .shadow(color: .black.opacity(pages > 0 ? 0.08 : 0.03), radius: 1, y: 1)
    }
}

/// Short, slightly wavering lines of handwriting, the last one shorter.
struct InkLines: Shape {
    let count: Int
    let seed: Int

    func path(in rect: CGRect) -> Path {
        let lengths: [CGFloat] = [1, 0.74, 0.9, 0.82, 0.66, 0.96, 0.78]
        let spacing = rect.height / 3
        var path = Path()
        for line in 0..<count {
            let y = rect.minY + spacing * (CGFloat(line) + 0.5)
            let length = rect.width * lengths[(seed * 3 + line) % lengths.count] * (line == count - 1 ? 0.6 : 1)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.minX + length, y: y))
        }
        return path
    }
}
