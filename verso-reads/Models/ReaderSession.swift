//
//  ReaderSession.swift
//  verso-reads
//

import Foundation
import Combine

struct NoteQuoteInsertion: Equatable {
    let annotationID: UUID
    let documentID: UUID
    let quote: String
}

@MainActor
final class ReaderSession: ObservableObject {
    @Published var activeDocumentID: UUID?
    @Published var isRightPanelVisible: Bool = false
    @Published var pendingNoteQuote: NoteQuoteInsertion?
    @Published var activeNoteQuoteAnchor: Data?
    @Published var currentPageNumber: Int?
    @Published var pendingPageNavigation: Int?
    @Published var pendingNoteAppend: String?

    let noteQuoteNavigation = PassthroughSubject<UUID, Never>()
}
