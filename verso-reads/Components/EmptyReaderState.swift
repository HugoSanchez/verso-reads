//
//  EmptyReaderState.swift
//  verso-reads
//

import SwiftUI
import UniformTypeIdentifiers

struct EmptyReaderState: View {
    let onOpen: () -> Void
    let onDrop: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(Color.black.opacity(0.3))
            Text("Drop a document to start reading")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.85))
            Text("We will keep your place, highlights, and notes in sync.")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .onDrop(of: [UTType.pdf.identifier], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        onDrop(url)
                    }
                }
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 2)
                .padding(24)
        )
    }
}

#Preview {
    EmptyReaderState(onOpen: {}, onDrop: { _ in })
        .frame(width: 600, height: 400)
        .background(Color.white)
}
