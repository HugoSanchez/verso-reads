//
//  SelectionDismissController.swift
//  verso-reads
//

import Foundation
import Combine

@MainActor
final class SelectionDismissController: ObservableObject {
    @Published var isActive: Bool = false
    var clearSelection: (() -> Void)?

    func clearIfPossible() {
        clearSelection?()
    }
}
