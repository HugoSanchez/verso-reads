//
//  HighlightColor.swift
//  verso-reads
//

import AppKit
import SwiftUI

enum HighlightColor: String, CaseIterable, Codable, Identifiable {
    case yellow
    case orange
    case green
    case blue

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var swatch: Color {
        switch self {
        case .yellow: return Color(red: 0.98, green: 0.84, blue: 0.32)
        case .orange: return Color(red: 0.98, green: 0.62, blue: 0.28)
        case .green: return Color(red: 0.47, green: 0.86, blue: 0.56)
        case .blue: return Color(red: 0.40, green: 0.72, blue: 0.98)
        }
    }

    var annotationNSColor: NSColor {
        let base: NSColor
        switch self {
        case .yellow: base = NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.32, alpha: 1)
        case .orange: base = NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.28, alpha: 1)
        case .green: base = NSColor(calibratedRed: 0.47, green: 0.86, blue: 0.56, alpha: 1)
        case .blue: base = NSColor(calibratedRed: 0.40, green: 0.72, blue: 0.98, alpha: 1)
        }
        return base.withAlphaComponent(0.35)
    }
}

