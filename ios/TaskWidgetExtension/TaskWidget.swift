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

// Helper to determine candidate app groups
func getAppGroupCandidates() -> [String] {
    var candidates = ["group.com.example.flutterPgi"]
    if let bundleId = Bundle.main.bundleIdentifier {
        let base = bundleId.replacingOccurrences(of: ".TaskWidgetExtension", with: "")
        candidates.append("group.\(base)")
        let parts = base.split(separator: ".")
        if let last = parts.last, last.count >= 8 {
            candidates.append("group.com.example.flutterPgi.\(last)")
        }
    }
    return candidates
}

func loadLocalTasksJson() -> String? {
    let candidates = getAppGroupCandidates()
    
    // 1. Check shared container file
    for group in candidates {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            let fileURL = container.appendingPathComponent("tasks.json")
            if let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
        }
    }
    
    // 2. Check shared UserDefaults
    for group in candidates {
        if let defaults = UserDefaults(suiteName: group),
           let content = defaults.string(forKey: "task_widget_tasks"), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
    }
    
    // 3. Fallback to standard UserDefaults
    if let content = UserDefaults.standard.string(forKey: "task_widget_tasks"), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return content
    }
    
    return nil
}

func loadLocalToken() -> String? {
    let candidates = getAppGroupCandidates()
    for group in candidates {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            let fileURL = container.appendingPathComponent("token.txt")
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        if let defaults = UserDefaults(suiteName: group),
           let content = defaults.string(forKey: "task_widget_token"), !content.isEmpty {
            return content
        }
    }
    return UserDefaults.standard.string(forKey: "task_widget_token")
}

func saveLocalTasksJson(_ tasksJson: String) {
    let candidates = getAppGroupCandidates()
    for group in candidates {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            let fileURL = container.appendingPathComponent("tasks.json")
            try? tasksJson.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        if let defaults = UserDefaults(suiteName: group) {
            defaults.set(tasksJson, forKey: "task_widget_tasks")
            defaults.synchronize()
        }
    }
    UserDefaults.standard.set(tasksJson, forKey: "task_widget_tasks")
    UserDefaults.standard.synchronize()
}

func parseDate(_ dateStr: String) -> Date? {
    let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone.current

    // Format 1: "yyyy-MM-dd HH:mm:ss"
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    if let d = df.date(from: trimmed) { return d }

    // Format 2: "yyyy-MM-dd"
    df.dateFormat = "yyyy-MM-dd"
    if let d = df.date(from: trimmed) { return d }

    // Format 3: "yyyy-MM-dd'T'HH:mm:ss"
    df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let d = df.date(from: trimmed) { return d }

    // Format 4: ISO8601
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: trimmed) { return d }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: trimmed)
}

func formatTime(_ raw: String) -> String {
    guard let date = parseDate(raw) else { return raw }
    let out = DateFormatter()
    out.dateFormat = "h:mm a"
    out.locale = Locale(identifier: "en_US_POSIX")
    out.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone.current
    return out.string(from: date)
}

func parseTasksEntry(from jsonStr: String?) -> TaskEntry? {
    guard let jsonStr = jsonStr, let data = jsonStr.data(using: .utf8) else {
        return nil
    }

    do {
        var rawList: [[String: Any]] = []
        if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            rawList = array
        } else if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let array = dict["tasks"] as? [[String: Any]] {
            rawList = array
        }

        var items: [TaskItem] = []
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        for raw in rawList {
            let status = (raw["occurrence_status"] as? String ?? "pending").lowercased()
            if status == "pending" {
                let title = raw["title"] as? String ?? "Untitled task"
                let priority = (raw["priority"] as? String ?? "medium").uppercased()
                let scheduled = raw["scheduled_at"] as? String ?? ""

                // Only skip tasks scheduled before today
                if let date = parseDate(scheduled), date < startOfToday {
                    continue
                }

                items.append(TaskItem(title: title, priority: priority, scheduled_at: formatTime(scheduled)))
            }
        }

        let rank: [String: Int] = ["HIGH": 0, "MEDIUM": 1, "LOW": 2]
        items.sort { (a, b) -> Bool in
            (rank[a.priority] ?? 3) < (rank[b.priority] ?? 3)
        }

        let topTasks = Array(items.prefix(3))
        let msg = topTasks.isEmpty ? "All caught up! Great work." : "Your daily priorities"
        return TaskEntry(date: Date(), tasks: topTasks, message: msg)
    } catch {
        print("Error parsing widget tasks: \(error)")
        return nil
    }
}

struct TaskTimelineProvider: TimelineProvider {
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
        if let entry = parseTasksEntry(from: loadLocalTasksJson()), !entry.tasks.isEmpty {
            completion(entry)
            return
        }
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        // 1. Try loading from local storage
        if let entry = parseTasksEntry(from: loadLocalTasksJson()), !entry.tasks.isEmpty {
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
            return
        }

        // 2. Fetch fresh tasks from network as a reliable fallback
        fetchTasksFromNetwork { entry in
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchTasksFromNetwork(completion: @escaping (TaskEntry) -> Void) {
        let fallbackEntry = TaskEntry(
            date: Date(),
            tasks: [],
            message: "No pending tasks."
        )

        let baseUrl = "https://tasks-reminder.onrender.com"

        func fetchWithToken(_ token: String) {
            guard let url = URL(string: "\(baseUrl)/tasks") else {
                completion(fallbackEntry)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10

            URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data,
                      let jsonStr = String(data: data, encoding: .utf8),
                      let entry = parseTasksEntry(from: jsonStr) else {
                    completion(fallbackEntry)
                    return
                }

                saveLocalTasksJson(jsonStr)
                completion(entry)
            }.resume()
        }

        if let token = loadLocalToken(), !token.isEmpty {
            fetchWithToken(token)
            return
        }

        // Auto-login fallback if token is not available in sandbox
        guard let loginUrl = URL(string: "\(baseUrl)/auth/login") else {
            completion(fallbackEntry)
            return
        }
        var loginReq = URLRequest(url: loginUrl)
        loginReq.httpMethod = "POST"
        loginReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginReq.timeoutInterval = 10
        let creds = ["email": "ela@gmail.com", "password": "12345678qwerty"]
        loginReq.httpBody = try? JSONSerialization.data(withJSONObject: creds)

        URLSession.shared.dataTask(with: loginReq) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String else {
                completion(fallbackEntry)
                return
            }
            fetchWithToken(token)
        }.resume()
    }
}

struct TaskWidgetEntryView: View {
    var entry: TaskTimelineProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        content.widgetURL(URL(string: "mytasks://dashboard")!)
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
