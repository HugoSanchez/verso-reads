//
//  NotepadView.swift
//  verso-reads
//

import SwiftUI

struct NotepadView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("No notes yet")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NotepadView()
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
