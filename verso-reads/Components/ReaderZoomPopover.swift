//
//  ReaderZoomPopover.swift
//  verso-reads
//

import SwiftUI

struct ReaderZoomPopover: View {
    @Binding var zoomPercent: Double
    let isEnabled: Bool
    let zoomRange: ClosedRange<Double>
    let zoomStep: Double
    let onApplyZoomPercent: (Double) -> Void
    let onSyncZoomPercent: () -> Double

    @State private var isSyncingZoom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    zoomPercent = max(zoomRange.lowerBound, zoomPercent - zoomStep)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 18, height: 18)
                }

                Slider(value: $zoomPercent, in: zoomRange)

                Button {
                    zoomPercent = min(zoomRange.upperBound, zoomPercent + zoomStep)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }

                Text("\(Int(zoomPercent.rounded()))%")
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(minWidth: 260)
        .disabled(isEnabled == false)
        .onChange(of: zoomPercent) { _, newValue in
            guard isSyncingZoom == false else { return }
            let clamped = min(max(newValue, zoomRange.lowerBound), zoomRange.upperBound)
            if abs(clamped - newValue) > 0.0001 {
                zoomPercent = clamped
                return
            }
            onApplyZoomPercent(clamped)
        }
        .onAppear {
            syncZoomPercent()
        }
    }

    private func syncZoomPercent() {
        isSyncingZoom = true
        zoomPercent = min(max(onSyncZoomPercent(), zoomRange.lowerBound), zoomRange.upperBound)
        DispatchQueue.main.async {
            isSyncingZoom = false
        }
    }
}

#Preview {
    ReaderZoomPopover(
        zoomPercent: .constant(100),
        isEnabled: true,
        zoomRange: 25...400,
        zoomStep: 10,
        onApplyZoomPercent: { _ in },
        onSyncZoomPercent: { 100 }
    )
}
