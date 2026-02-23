//
//  RAGChunker.swift
//  verso-reads
//

import Foundation

struct RAGChunk {
    let text: String
    let chunkIndex: Int
    let pageStart: Int?
    let pageEnd: Int?
}

enum RAGChunker {
    nonisolated static func chunk(
        pages: [PDFPageText],
        maxCharacters: Int = 1200,
        overlap: Int = 200
    ) -> [RAGChunk] {
        guard pages.isEmpty == false else { return [] }

        var chunks: [RAGChunk] = []
        var buffer = ""
        var chunkIndex = 0
        var bufferPageStart: Int?
        var bufferPageEnd: Int?

        func flushChunk(text: String, pageStart: Int?, pageEnd: Int?) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return }
            chunks.append(
                RAGChunk(
                    text: trimmed,
                    chunkIndex: chunkIndex,
                    pageStart: pageStart,
                    pageEnd: pageEnd
                )
            )
            chunkIndex += 1
        }

        for page in pages {
            if bufferPageStart == nil {
                bufferPageStart = page.pageIndex
            }
            bufferPageEnd = page.pageIndex

            if buffer.isEmpty == false {
                buffer.append(" ")
            }
            buffer.append(page.text)

            while buffer.count >= maxCharacters {
                let splitIndex = buffer.index(buffer.startIndex, offsetBy: maxCharacters)
                let head = String(buffer[..<splitIndex])
                flushChunk(text: head, pageStart: bufferPageStart, pageEnd: bufferPageEnd)

                let overlapCount = min(overlap, head.count)
                let overlapStart = head.index(head.endIndex, offsetBy: -overlapCount)
                let overlapText = String(head[overlapStart...])
                buffer = overlapText + String(buffer[splitIndex...])
                bufferPageStart = bufferPageEnd
            }
        }

        if buffer.isEmpty == false {
            flushChunk(text: buffer, pageStart: bufferPageStart, pageEnd: bufferPageEnd)
        }

        return chunks
    }
}
