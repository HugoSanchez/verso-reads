//
//  NotepadView.swift
//  verso-reads
//

import SwiftUI

struct NotepadView: View {
    var body: some View {
        NotesWebView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NotepadView()
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
