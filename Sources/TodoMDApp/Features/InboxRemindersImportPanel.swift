import SwiftUI

struct InboxRemindersImportPanel: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if shouldShowPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("From Reminders")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(panelPrimaryTextColor)

                    Spacer(minLength: 12)

                    if !container.pendingReminderImports.isEmpty {
                        Button {
                            Task {
                                await container.importAllFromReminders()
                            }
                        } label: {
                            Label(container.isRemindersImporting ? "Importing..." : "Import All", systemImage: "arrow.down")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(theme.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(container.isRemindersImporting)
                        .accessibilityIdentifier("inbox.remindersImport.importAllButton")
                    }
                }

                ForEach(container.pendingReminderImports) { reminder in
                    reminderCard(reminder)
                }

                if let statusMessage = displayableStatusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondaryColor)
                        .accessibilityIdentifier("inbox.remindersImport.status")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var shouldShowPanel: Bool {
        !container.pendingReminderImports.isEmpty || displayableStatusMessage != nil
    }

    private var displayableStatusMessage: String? {
        guard let message = container.remindersImportStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        if message.hasPrefix("No new reminders found") {
            return nil
        }

        return message
    }

    private var panelPrimaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.94) : theme.textPrimaryColor
    }

    private var cardGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.17, blue: 0.21),
                    Color(red: 0.11, green: 0.12, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                theme.surfaceColor.opacity(0.98),
                theme.backgroundColor.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : theme.textSecondaryColor.opacity(0.14)
    }

    private var iconBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : theme.textSecondaryColor.opacity(0.12)
    }

    private var iconForegroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.78) : theme.textSecondaryColor
    }

    private func reminderCard(_ reminder: ReminderImportItem) -> some View {
        Button {
            Task {
                await container.importReminderFromReminders(id: reminder.id)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)

                    Image(systemName: "arrow.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(iconForegroundColor)
                }
                .frame(width: 42, height: 42)

                Text(reminder.title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(panelPrimaryTextColor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(cardGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 16, y: 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inbox.remindersImport.row.\(reminder.id)")
        }
        .buttonStyle(.plain)
        .disabled(container.isRemindersImporting)
    }
}
