//
//  ScreenAnalyzer.swift
//  TotalControl
//
//  Screenshot OCR using Tesseract (open source) - no Apple Vision dependency
//  Add SwiftyTesseract pod: pod 'SwiftyTesseract'
//

import Foundation
import UIKit
// import SwiftyTesseract  // Uncomment after adding pod

// MARK: - Screen Types

enum ScreenType: String, Codable, CaseIterable {
    case dm = "dm"
    case feed = "feed"
    case reels = "reels"
    case notifications = "notifications"
    case profile = "profile"
    case search = "search"
    case settings = "settings"
    case unknown = "unknown"

    var isAllowed: Bool {
        switch self {
        case .dm, .notifications, .settings:
            return true
        case .feed, .reels, .profile, .search, .unknown:
            return false
        }
    }
}

// MARK: - Analysis Result

struct ScreenAnalysis: Codable {
    let timestamp: Date
    let appHint: String
    let screenType: ScreenType
    let confidence: Double
    let rawText: String
    let textHash: String
    let matchedPatterns: [String]
    let shouldBlock: Bool
}

// MARK: - Pattern Database (same as Python version)

struct PatternDatabase {

    // DM indicators (ALLOW)
    static let dmStrong: [String] = [
        "direct messages?",
        "new message",
        "send a? ?message",
        "message requests?",
        "start a? ?(new )?conversation",
        "type a message",
        "write a message",
        "chat with",
        "inbox",
    ]

    static let dmMedium: [String] = [
        "chats?",
        "conversations?",
        "reply",
        "delivered",
        "seen \\d",
        "typing",
    ]

    // Feed indicators (BLOCK)
    static let feedStrong: [String] = [
        "for you",
        "following tab",
        "suggested",
        "sponsored",
        "promoted",
        "trending",
        "what.?s happening",
        "discover",
        "explore",
        "popular",
        "\\d+ likes?",
        "\\d+ comments?",
        "liked by",
        "view all.*comments?",
    ]

    static let feedMedium: [String] = [
        "home",
        "feed",
        "timeline",
        "stories",
        "follow",
        "share",
    ]

    // Reels indicators (BLOCK)
    static let reelsStrong: [String] = [
        "reels?",
        "shorts?",
        "tiktok",
        "watch now",
        "swipe up",
        "original audio",
        "trending audio",
    ]

    // Notifications (ALLOW)
    static let notificationsStrong: [String] = [
        "notifications?",
        "activity",
        "mentions?",
        "replied to you",
        "mentioned you",
        "tagged you",
    ]

    // Settings (ALLOW)
    static let settingsStrong: [String] = [
        "settings",
        "privacy",
        "account",
        "security",
        "log out",
        "sign out",
    ]

    // App-specific
    static let discordDM: [String] = ["friends", "@me", "direct messages"]
    static let discordFeed: [String] = ["#[a-z-]+", "text channels?", "voice channels?", "server"]

    static let twitterDM: [String] = ["messages?", "new message"]
    static let twitterFeed: [String] = ["for you", "following", "what.?s happening", "trending"]

    static let instagramDM: [String] = ["messages?", "send message", "primary", "general"]
    static let instagramFeed: [String] = ["liked by", "suggested for you", "reels?", "explore"]
}

// MARK: - Screen Analyzer (Tesseract-based)

class ScreenAnalyzer {

    static let shared = ScreenAnalyzer()

    private let analysisQueue = DispatchQueue(label: "com.totalcontrol.analysis")
    private var history: [ScreenAnalysis] = []

    // Tesseract instance - initialize once
    // private var tesseract: SwiftyTesseract?

    init() {
        // Initialize Tesseract with English language
        // tesseract = try? SwiftyTesseract(language: .english)
    }

    // MARK: - OCR using Tesseract

    func extractText(from image: UIImage, completion: @escaping (String) -> Void) {
        analysisQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion("") }
                return
            }

            // === TESSERACT OCR ===
            // Uncomment after adding SwiftyTesseract pod:
            /*
            guard let tesseract = self.tesseract else {
                DispatchQueue.main.async { completion("") }
                return
            }

            let result = tesseract.performOCR(on: image)
            switch result {
            case .success(let text):
                DispatchQueue.main.async { completion(text) }
            case .failure(let error):
                print("Tesseract error: \(error)")
                DispatchQueue.main.async { completion("") }
            }
            */

            // === FALLBACK: Simple pixel analysis for testing ===
            // This is a placeholder - replace with Tesseract in production
            DispatchQueue.main.async { completion("[Tesseract not configured]") }
        }
    }

    // MARK: - Alternative: Server-side OCR

    func extractTextViaServer(from image: UIImage, serverURL: String, completion: @escaping (String) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion("")
            return
        }

        var request = URLRequest(url: URL(string: serverURL)!)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion("") }
                return
            }
            DispatchQueue.main.async { completion(text) }
        }.resume()
    }

    // MARK: - Classification (same logic as Python)

    func classify(text: String, appHint: String = "") -> (ScreenType, Double, [String]) {
        let textLower = text.lowercased()
        let appLower = appHint.lowercased()

        var scores: [ScreenType: Double] = [:]
        var matched: [ScreenType: [String]] = [:]

        for screenType in ScreenType.allCases {
            scores[screenType] = 0
            matched[screenType] = []
        }

        // Helper to check patterns
        func checkPatterns(_ patterns: [String], type: ScreenType, weight: Double, prefix: String) {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(textLower.startIndex..., in: textLower)
                    if regex.firstMatch(in: textLower, options: [], range: range) != nil {
                        scores[type, default: 0] += weight
                        matched[type, default: []].append("\(prefix):\(pattern)")
                    }
                }
            }
        }

        // Check general patterns
        checkPatterns(PatternDatabase.dmStrong, type: .dm, weight: 2.0, prefix: "strong")
        checkPatterns(PatternDatabase.dmMedium, type: .dm, weight: 0.5, prefix: "medium")
        checkPatterns(PatternDatabase.feedStrong, type: .feed, weight: 2.0, prefix: "strong")
        checkPatterns(PatternDatabase.feedMedium, type: .feed, weight: 0.5, prefix: "medium")
        checkPatterns(PatternDatabase.reelsStrong, type: .reels, weight: 2.0, prefix: "strong")
        checkPatterns(PatternDatabase.notificationsStrong, type: .notifications, weight: 2.0, prefix: "strong")
        checkPatterns(PatternDatabase.settingsStrong, type: .settings, weight: 2.0, prefix: "strong")

        // App-specific boost
        if appLower.contains("discord") {
            checkPatterns(PatternDatabase.discordDM, type: .dm, weight: 1.5, prefix: "discord")
            checkPatterns(PatternDatabase.discordFeed, type: .feed, weight: 1.5, prefix: "discord")
        }
        if appLower.contains("twitter") || appLower.contains("x") {
            checkPatterns(PatternDatabase.twitterDM, type: .dm, weight: 1.5, prefix: "twitter")
            checkPatterns(PatternDatabase.twitterFeed, type: .feed, weight: 1.5, prefix: "twitter")
        }
        if appLower.contains("instagram") {
            checkPatterns(PatternDatabase.instagramDM, type: .dm, weight: 1.5, prefix: "instagram")
            checkPatterns(PatternDatabase.instagramFeed, type: .feed, weight: 1.5, prefix: "instagram")
        }

        // Find best match
        let bestType = scores.max(by: { $0.value < $1.value })?.key ?? .unknown
        let bestScore = scores[bestType] ?? 0
        let totalScore = scores.values.reduce(0, +)

        let confidence = totalScore > 0 ? min(bestScore / totalScore, 1.0) : 0

        if bestScore < 1.0 {
            return (.unknown, 0, [])
        }

        return (bestType, confidence, matched[bestType] ?? [])
    }

    // MARK: - Full Analysis Pipeline

    func analyze(image: UIImage, appHint: String = "", completion: @escaping (ScreenAnalysis) -> Void) {
        extractText(from: image) { [weak self] text in
            guard let self = self else { return }

            let (screenType, confidence, patterns) = self.classify(text: text, appHint: appHint)
            let textHash = String(text.hashValue.magnitude % 1_000_000_000_000)

            let analysis = ScreenAnalysis(
                timestamp: Date(),
                appHint: appHint,
                screenType: screenType,
                confidence: confidence,
                rawText: String(text.prefix(2000)),
                textHash: textHash,
                matchedPatterns: patterns,
                shouldBlock: !screenType.isAllowed
            )

            // Store for learning
            self.history.append(analysis)
            if self.history.count > 1000 {
                self.history.removeFirst(100)
            }

            DispatchQueue.main.async {
                completion(analysis)
            }
        }
    }
}

// MARK: - Podfile Setup
/*

 Add to your Podfile:

 platform :ios, '13.0'

 target 'TotalControl' do
   use_frameworks!
   pod 'SwiftyTesseract', '~> 4.0'
 end

 Then run: pod install

 Also need to add tessdata files to your bundle:
 - Download from: https://github.com/tesseract-ocr/tessdata
 - Add eng.traineddata to project
 - In Build Phases, add to "Copy Bundle Resources"

*/

// MARK: - Alternative: Use GPT-4 Vision API for classification
/*

 If OCR accuracy is insufficient, can send screenshot to GPT-4 Vision:

 func classifyWithGPT4(image: UIImage, completion: @escaping (ScreenType) -> Void) {
     guard let imageData = image.jpegData(compressionQuality: 0.5) else {
         completion(.unknown)
         return
     }

     let base64 = imageData.base64EncodedString()

     // Call GPT-4 Vision API with prompt:
     // "Is this a DM/messaging screen or a feed/browse screen? Reply only: DM or FEED"

     // Parse response and return ScreenType
 }

*/
