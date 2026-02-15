//
//  ConversationActivityAttributes.swift
//  CYT
//
//  ActivityKit attributes for the conversation Live Activity.
//  Shared between the main app and the widget extension.
//

import ActivityKit
import Foundation

struct ConversationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isRecording: Bool
        var latestCardTitle: String?
        var latestCardIcon: String?
        var moodColor: String  // "neutral", "sad", "angry", "happy"
        var audioLevel: Int    // 0=silent, 1=low, 2=mid, 3=high
    }

    var sessionStart: Date
}
