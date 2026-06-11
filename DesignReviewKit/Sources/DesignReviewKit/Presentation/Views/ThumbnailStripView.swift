//
//  ThumbnailStripView.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI

/// Horizontal strip of previously captured screens; tap to switch the canvas.
struct ThumbnailStripView: View {

    let thumbnails: [InspectorViewModel.ThumbnailItem]
    let onTap: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(thumbnails) { item in
                    Button {
                        onTap(item.id)
                    } label: {
                        thumbnailImage(item.image)
                            .frame(height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        item.isActive ? Color.accentColor : Color(.systemGray4),
                                        lineWidth: item.isActive ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func thumbnailImage(_ image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .aspectRatio(0.5, contentMode: .fit)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
