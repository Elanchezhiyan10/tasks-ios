import WidgetKit
import SwiftUI

struct TaskItem: Codable, Identifiable {
    var id: String { title + scheduled_at }
    let title: String
    let priority: String
    let scheduled_at: String
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let message: String
}

struct TaskTimelineProvider: TimelineProvider {
    let appGroup = "group.com.example.flutterPgi"

    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(
            date: Date(),
            tasks: [
                TaskItem(title: "Complete Project Report", priority: "HIGH", scheduled_at: "10:00 AM"),
                TaskItem(title: "Team Sync Meeting", priority: "MEDIUM", scheduled_at: "02:00 PM")
            ],
            message: "Your daily priorities"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(loadTasks())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = loadTasks()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadTasks() -> TaskEntry {
        let defaults = UserDefaults(suiteName: appGroup) ?? UserDefaults.standard

        if let jsonStr = defaults.string(forKey: "task_widget_tasks"),
           let data = jsonStr.data(using: .utf8) {
            do {
                if let rawList = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var items: [TaskItem] = []
                    for raw in rawList {
                        let status = raw["occurrence_status"] as? String ?? "pending"
                        if status == "pending" {
                            let title = raw["title"] as? String ?? "Untitled task"
                            let priority = (raw["priority"] as? String ?? "medium").uppercased()
                            let scheduled = raw["scheduled_at"] as? String ?? ""
                            items.append(TaskItem(title: title, priority: priority, scheduled_at: formatTime(scheduled)))
                        }
                    }

                    // Sort: High, Medium, Low
                    let rank: [String: Int] = ["HIGH": 0, "MEDIUM": 1, "LOW": 2]
                    items.sort { (a, b) -> Bool in
                        (rank[a.priority] ?? 3) < (rank[b.priority] ?? 3)
                    }

                    let topTasks = Array(items.prefix(3))
                    let msg = topTasks.isEmpty ? "All caught up! Great work." : "Your daily priorities"
                    return TaskEntry(date: Date(), tasks: topTasks, message: msg)
                }
            } catch {
                print("Error parsing widget tasks: \(error)")
            }
        }

        return TaskEntry(
            date: Date(),
            tasks: [],
            message: "Open the app to sync tasks."
        )
    }

    private func formatTime(_ raw: String) -> String {
        if raw.isEmpty { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: raw)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: raw)
        }
        guard let d = date else { return raw }
        let outFormat = DateFormatter()
        outFormat.timeStyle = .short
        return outFormat.string(from: d)
    }
}

struct TaskWidgetEntryView: View {
    var entry: TaskTimelineProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        content
            .widgetBackground(Color(red: 0.08, green: 0.11, blue: 0.15))
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                    .font(.system(size: 13, weight: .bold))
                Text("TASK FOCUS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }

            if entry.tasks.isEmpty {
                Spacer()
                Text(entry.message)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                Spacer()
            } else {
                let maxCount = family == .systemSmall ? 2 : 3
                ForEach(Array(entry.tasks.prefix(maxCount).enumerated()), id: \.offset) { index, task in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(index + 1).")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                            Text("[\(task.priority)]")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(priorityColor(task.priority))
                            Text(task.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        if !task.scheduled_at.isEmpty && family != .systemSmall {
                            Text("   \(task.scheduled_at)")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(10)
    }

    func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "HIGH": return .red
        case "MEDIUM": return .orange
        case "LOW": return .green
        default: return .blue
        }
    }
}

extension View {
    @ViewBuilder
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            background(backgroundView)
        }
    }
}

@main
struct TaskWidget: Widget {
    let kind: String = "TaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskTimelineProvider()) { entry in
            TaskWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Task Focus")
        .description("View your top priority tasks right on your home screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
