//
//  PDFHighlightAnchor.swift
//  verso-reads
//

import Foundation

struct PDFHighlightAnchor: Codable, Equatable {
    var type: String = "pdfHighlight"
    var fragments: [PDFHighlightFragment]
}

struct PDFHighlightFragment: Codable, Equatable {
    var pageIndex: Int
    var rects: [NormalizedRect]
}

struct NormalizedRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}
