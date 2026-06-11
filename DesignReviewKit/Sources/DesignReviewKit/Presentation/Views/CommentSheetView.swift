//
//  CommentSheetView.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import SwiftUI

/// Commentary editor presented immediately after a rectangle is drawn, and when editing.
///
/// Save stays disabled until the comment is non-empty — this enforces the invariant
/// that every annotation carries commentary. Cancelling a new annotation removes its rect.
struct CommentSheetView: View {

    let draft: InspectorViewModel.CommentDraft
    let onSeverityChange: (Severity) -> Void
    let onSave: (String, Severity) -> Void
    let onCancel: () -> Void

    @State
    private var text: String

    @State
    private var severity: Severity

    @FocusState
    private var isCommentFocused: Bool

    init(
        draft: InspectorViewModel.CommentDraft,
        onSeverityChange: @escaping (Severity) -> Void,
        onSave: @escaping (String, Severity) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSeverityChange = onSeverityChange
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: draft.text)
        _severity = State(initialValue: draft.severity)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                severityPicker
                commentEditor
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedText, severity)
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .onAppear {
            isCommentFocused = true
        }
    }

    private var severityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Severity")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(Severity.allCases, id: \.self) { option in
                    severityOption(option)
                }
            }
        }
    }

    private func severityOption(_ option: Severity) -> some View {
        let isSelected = option == severity
        return Button {
            severity = option
            onSeverityChange(option)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(option.color)
                    .frame(width: 8, height: 8)
                Text(option.displayName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? AnyShapeStyle(option.color.opacity(0.18)) : AnyShapeStyle(Color(.tertiarySystemFill)),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? option.color : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var commentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comment")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .focused($isCommentFocused)
                .frame(minHeight: 120)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Describe the issue…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                            .padding(.leading, 13)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}
