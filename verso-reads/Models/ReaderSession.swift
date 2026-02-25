//
//  ReaderSession.swift
//  verso-reads
//

import Foundation
import Combine

@MainActor
final class ReaderSession: ObservableObject {
    @Published var activeDocumentID: UUID?
    @Published var isRightPanelVisible: Bool = false
}
