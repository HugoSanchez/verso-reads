//
//  SettingsView.swift
//  verso-reads
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: OpenAISettingsStore

    @State private var isShowingKey = false

    var body: some View {
        ScrollView {
            VStack {
                VStack(alignment: .leading, spacing: 22) {
                    Text("General")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.86))

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCard {
                            SettingsRow(
                                title: "OpenAI API key",
                                subtitle: "Stored locally in Keychain."
                            ) {
                                apiKeyField
                            }

                            Divider()
                                .overlay(Color.black.opacity(0.06))

                            SettingsRow(
                                title: "Model",
                                subtitle: "Default model for chat."
                            ) {
                                modelField
                            }
                        }

                        HStack(spacing: 12) {
                            Spacer()

                            if let statusMessage = settings.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.black.opacity(0.5))
                                    .lineLimit(1)
                                    .transition(.opacity)
                            }

                            Button(action: { settings.save() }) {
                                Text("Save")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.72))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .animation(.easeInOut(duration: 0.2), value: settings.statusMessage)
                    }
                }
                .padding(.top, 52)
                .padding(.horizontal, 72)
                .padding(.bottom, 60)
                .frame(maxWidth: 940, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var apiKeyField: some View {
        HStack(spacing: 6) {
            Group {
                if isShowingKey {
                    TextField("sk-...", text: $settings.apiKey)
                } else {
                    SecureField("sk-...", text: $settings.apiKey)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))

            Button(action: { isShowingKey.toggle() }) {
                Image(systemName: isShowingKey ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .frame(width: 320)
    }

    private var modelField: some View {
        TextField("gpt-5.2", text: $settings.model)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .frame(width: 320)
    }
}

private struct SettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.82))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

#Preview {
    SettingsView(settings: OpenAISettingsStore())
        .frame(width: 800, height: 600)
        .background(Color.white)
}
