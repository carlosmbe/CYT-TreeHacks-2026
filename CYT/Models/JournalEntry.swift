import Foundation

enum MoodLevel: String, CaseIterable, Codable, Sendable {
    case calm = "Calm"
    case happy = "Happy"
    case neutral = "Neutral"
    case anxious = "Anxious"
    case stressed = "Stressed"
    case sad = "Sad"

    var emoji: String {
        switch self {
        case .calm: "😌"
        case .happy: "😊"
        case .neutral: "😐"
        case .anxious: "😰"
        case .stressed: "😤"
        case .sad: "😢"
        }
    }

    var color: String {
        switch self {
        case .calm: "teal"
        case .happy: "green"
        case .neutral: "gray"
        case .anxious: "orange"
        case .stressed: "red"
        case .sad: "blue"
        }
    }
}

enum EntryAttachmentType: String, Codable, Sendable {
    case image
    case audio
    case healthData
}

struct EntryAttachment: Identifiable, Codable, Sendable {
    let id: UUID
    let type: EntryAttachmentType
    let data: Data?
    let label: String

    init(id: UUID = UUID(), type: EntryAttachmentType, data: Data? = nil, label: String = "") {
        self.id = id
        self.type = type
        self.data = data
        self.label = label
    }
}

struct JournalEntry: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var date: Date
    var mood: MoodLevel
    var attachments: [EntryAttachment]
    var audioTranscript: String?
    var healthSnapshot: [HealthMetric]
    var tags: [String]

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        date: Date = .now,
        mood: MoodLevel = .neutral,
        attachments: [EntryAttachment] = [],
        audioTranscript: String? = nil,
        healthSnapshot: [HealthMetric] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
        self.mood = mood
        self.attachments = attachments
        self.audioTranscript = audioTranscript
        self.healthSnapshot = healthSnapshot
        self.tags = tags
    }
}
