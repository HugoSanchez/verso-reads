//
//  PDFHighlightAnchor.swift
//  verso-reads
//

import Foundation

struct PDFHighlightAnchor: Codable {
    var type: String = "pdfHighlight"
    var fragments: [PDFHighlightFragment]
}

struct PDFHighlightFragment: Codable {
    var pageIndex: Int
    var rects: [NormalizedRect]
}

struct NormalizedRect: Codable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

