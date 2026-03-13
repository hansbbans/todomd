import SwiftUI

struct AppIconOption: Identifiable, Hashable {
    let value: String
    let label: String

    var id: String { value }
}

struct AppIconSection: Identifiable, Hashable {
    let title: String
    let options: [AppIconOption]

    var id: String { title }
}

struct AppIconToken: Hashable {
    let storageValue: String
    let fallbackSymbol: String

    init(_ rawValue: String?, fallbackSymbol: String) {
        self.fallbackSymbol = fallbackSymbol

        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let emoji = Self.normalizedEmoji(from: trimmed) {
            storageValue = emoji
        } else if trimmed.isEmpty {
            storageValue = fallbackSymbol
        } else {
            storageValue = trimmed
        }
    }

    var isEmoji: Bool {
        Self.isEmojiValue(storageValue)
    }

    var symbolName: String {
        isEmoji ? fallbackSymbol : storageValue
    }

    static func normalizedSelection(_ rawValue: String?, fallbackSymbol: String) -> String {
        AppIconToken(rawValue, fallbackSymbol: fallbackSymbol).storageValue
    }

    static func normalizedEmoji(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCharacter = trimmed.first else { return nil }
        let candidate = String(firstCharacter)
        return isEmojiValue(candidate) ? candidate : nil
    }

    static func isEmojiValue(_ rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.unicodeScalars.contains(where: { !$0.isASCII }) else { return false }

        return trimmed.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }
}

private struct AppIconNeverAutocapitalization: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.textInputAutocapitalization(.never)
#else
        content
#endif
    }
}

private struct AppIconInlineTitleDisplayMode: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.navigationBarTitleDisplayMode(.inline)
#else
        content
#endif
    }
}

enum AppIconCatalog {
    static let symbolSections: [AppIconSection] = [
        AppIconSection(title: "Work & Organization", options: [
            .init(value: "folder", label: "Folder"),
            .init(value: "briefcase", label: "Briefcase"),
            .init(value: "building.2", label: "Office"),
            .init(value: "building.columns", label: "Institution"),
            .init(value: "person.2", label: "People"),
            .init(value: "list.bullet", label: "List"),
            .init(value: "checklist", label: "Checklist"),
            .init(value: "tray", label: "Tray"),
            .init(value: "archivebox", label: "Archive"),
            .init(value: "tag", label: "Tag")
        ]),
        AppIconSection(title: "Planning & Status", options: [
            .init(value: "flag", label: "Flag"),
            .init(value: "star", label: "Star"),
            .init(value: "heart", label: "Heart"),
            .init(value: "calendar", label: "Calendar"),
            .init(value: "clock", label: "Clock"),
            .init(value: "bell", label: "Bell"),
            .init(value: "alarm", label: "Alarm"),
            .init(value: "bookmark", label: "Bookmark"),
            .init(value: "sparkles", label: "Sparkles"),
            .init(value: "bolt", label: "Bolt")
        ]),
        AppIconSection(title: "Documents & Tools", options: [
            .init(value: "newspaper", label: "News"),
            .init(value: "document", label: "Document"),
            .init(value: "clipboard", label: "Clipboard"),
            .init(value: "pencil", label: "Pencil"),
            .init(value: "paintbrush", label: "Paintbrush"),
            .init(value: "hammer", label: "Hammer"),
            .init(value: "wrench.and.screwdriver", label: "Tools"),
            .init(value: "gearshape", label: "Gear"),
            .init(value: "magnifyingglass", label: "Search"),
            .init(value: "link", label: "Link")
        ]),
        AppIconSection(title: "Communication", options: [
            .init(value: "paperclip", label: "Attachment"),
            .init(value: "bubble.left", label: "Conversation"),
            .init(value: "phone", label: "Phone"),
            .init(value: "envelope", label: "Mail"),
            .init(value: "message", label: "Message"),
            .init(value: "video", label: "Video"),
            .init(value: "camera", label: "Camera")
        ]),
        AppIconSection(title: "Media & Entertainment", options: [
            .init(value: "photo", label: "Photo"),
            .init(value: "music.note", label: "Music"),
            .init(value: "headphones", label: "Headphones"),
            .init(value: "play.rectangle", label: "Play"),
            .init(value: "tv", label: "TV"),
            .init(value: "gamecontroller", label: "Games"),
            .init(value: "wand.and.sparkles", label: "Creative"),
            .init(value: "gift", label: "Gift")
        ]),
        AppIconSection(title: "Tech & Security", options: [
            .init(value: "externaldrive", label: "Drive"),
            .init(value: "laptopcomputer", label: "Laptop"),
            .init(value: "wifi", label: "Wi-Fi"),
            .init(value: "shield", label: "Shield"),
            .init(value: "lock", label: "Lock"),
            .init(value: "key", label: "Key"),
            .init(value: "creditcard", label: "Card")
        ]),
        AppIconSection(title: "Home & Daily Life", options: [
            .init(value: "house", label: "Home"),
            .init(value: "car", label: "Car"),
            .init(value: "cart", label: "Cart"),
            .init(value: "bag", label: "Bag"),
            .init(value: "shippingbox", label: "Shipping"),
            .init(value: "bed.double", label: "Bed"),
            .init(value: "fork.knife", label: "Meals"),
            .init(value: "cup.and.saucer", label: "Coffee"),
            .init(value: "takeoutbag.and.cup.and.straw", label: "Takeout")
        ]),
        AppIconSection(title: "Travel & Places", options: [
            .init(value: "airplane", label: "Airplane"),
            .init(value: "tram", label: "Transit"),
            .init(value: "ferry", label: "Ferry"),
            .init(value: "fuelpump", label: "Fuel"),
            .init(value: "location", label: "Location"),
            .init(value: "map", label: "Map"),
            .init(value: "globe", label: "Globe"),
            .init(value: "suitcase", label: "Suitcase")
        ]),
        AppIconSection(title: "Health & Movement", options: [
            .init(value: "graduationcap", label: "Learning"),
            .init(value: "stethoscope", label: "Checkup"),
            .init(value: "cross.case", label: "Medical"),
            .init(value: "pills", label: "Medicine"),
            .init(value: "bandage", label: "Bandage"),
            .init(value: "cross", label: "Care"),
            .init(value: "dumbbell", label: "Workout"),
            .init(value: "figure.walk", label: "Walk"),
            .init(value: "figure.run", label: "Run"),
            .init(value: "bicycle", label: "Bike")
        ]),
        AppIconSection(title: "Sports & Leisure", options: [
            .init(value: "soccerball", label: "Soccer"),
            .init(value: "basketball", label: "Basketball"),
            .init(value: "tennis.racket", label: "Tennis"),
            .init(value: "book", label: "Reading"),
            .init(value: "birthday.cake", label: "Cake"),
            .init(value: "party.popper", label: "Celebration"),
            .init(value: "flame", label: "Focus")
        ]),
        AppIconSection(title: "Weather & Nature", options: [
            .init(value: "moon", label: "Moon"),
            .init(value: "sun.max", label: "Sun"),
            .init(value: "cloud", label: "Cloud"),
            .init(value: "cloud.rain", label: "Rain"),
            .init(value: "snowflake", label: "Snow"),
            .init(value: "leaf", label: "Leaf"),
            .init(value: "tree", label: "Tree"),
            .init(value: "pawprint", label: "Paw"),
            .init(value: "fish", label: "Fish"),
            .init(value: "bird", label: "Bird"),
            .init(value: "ladybug", label: "Ladybug"),
            .init(value: "ant", label: "Ant"),
            .init(value: "hare", label: "Rabbit"),
            .init(value: "tortoise", label: "Tortoise")
        ])
    ]

    static let emojiSections: [AppIconSection] = [
        AppIconSection(title: "Work & Organization", options: [
            .init(value: "📁", label: "Folder"),
            .init(value: "💼", label: "Briefcase"),
            .init(value: "🏢", label: "Office"),
            .init(value: "👥", label: "People"),
            .init(value: "📋", label: "Clipboard"),
            .init(value: "🏷️", label: "Tag"),
            .init(value: "🗂️", label: "Organizer"),
            .init(value: "📌", label: "Pin")
        ]),
        AppIconSection(title: "Planning & Status", options: [
            .init(value: "📅", label: "Calendar"),
            .init(value: "⏰", label: "Alarm"),
            .init(value: "🔔", label: "Bell"),
            .init(value: "🚩", label: "Flag"),
            .init(value: "⭐️", label: "Star"),
            .init(value: "❤️", label: "Heart"),
            .init(value: "⚡️", label: "Bolt"),
            .init(value: "✨", label: "Sparkles")
        ]),
        AppIconSection(title: "Communication & Media", options: [
            .init(value: "💬", label: "Chat"),
            .init(value: "✉️", label: "Mail"),
            .init(value: "📞", label: "Phone"),
            .init(value: "🎥", label: "Video"),
            .init(value: "📷", label: "Camera"),
            .init(value: "🖼️", label: "Photo"),
            .init(value: "🎵", label: "Music"),
            .init(value: "🎧", label: "Headphones")
        ]),
        AppIconSection(title: "Home & Travel", options: [
            .init(value: "🏠", label: "Home"),
            .init(value: "🚗", label: "Car"),
            .init(value: "🛒", label: "Cart"),
            .init(value: "🛏️", label: "Bed"),
            .init(value: "🍽️", label: "Meals"),
            .init(value: "☕️", label: "Coffee"),
            .init(value: "✈️", label: "Airplane"),
            .init(value: "🗺️", label: "Map"),
            .init(value: "🧳", label: "Suitcase"),
            .init(value: "🎁", label: "Gift")
        ]),
        AppIconSection(title: "Health & Nature", options: [
            .init(value: "🎓", label: "Learning"),
            .init(value: "🩺", label: "Checkup"),
            .init(value: "💊", label: "Medicine"),
            .init(value: "🩹", label: "Bandage"),
            .init(value: "🏃", label: "Run"),
            .init(value: "🚲", label: "Bike"),
            .init(value: "🌿", label: "Leaf"),
            .init(value: "🌳", label: "Tree"),
            .init(value: "🐾", label: "Paw"),
            .init(value: "🐟", label: "Fish"),
            .init(value: "🐦", label: "Bird"),
            .init(value: "🐇", label: "Rabbit")
        ])
    ]

    private static let labelsByValue: [String: String] = Dictionary(
        uniqueKeysWithValues: (symbolSections + emojiSections)
            .flatMap(\.options)
            .map { ($0.value, $0.label) }
    )

    static func label(for value: String, fallbackSymbol: String) -> String {
        let normalized = AppIconToken(value, fallbackSymbol: fallbackSymbol).storageValue
        if let label = labelsByValue[normalized] {
            return label
        }
        if AppIconToken.isEmojiValue(normalized) {
            return "Custom Emoji"
        }
        return normalized
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

struct AppIconGlyph: View {
    private let token: AppIconToken
    private let pointSize: CGFloat
    private let weight: Font.Weight
    private let tint: Color?

    init(
        icon: String,
        fallbackSymbol: String,
        pointSize: CGFloat = 18,
        weight: Font.Weight = .regular,
        tint: Color? = nil
    ) {
        token = AppIconToken(icon, fallbackSymbol: fallbackSymbol)
        self.pointSize = pointSize
        self.weight = weight
        self.tint = tint
    }

    var body: some View {
        Group {
            if token.isEmoji {
                Text(token.storageValue)
            } else {
                Image(systemName: token.symbolName)
                    .foregroundStyle(tint ?? .primary)
            }
        }
        .font(.system(size: pointSize, weight: weight))
    }
}

struct AppIconPickerLink: View {
    let label: String
    let title: String
    let fallbackSymbol: String
    let tint: Color

    @Binding var selection: String

    var body: some View {
        NavigationLink {
            AppIconPickerView(
                title: title,
                fallbackSymbol: fallbackSymbol,
                selection: normalizedSelection
            )
        } label: {
            HStack(spacing: 12) {
                Text(label)
                Spacer()
                Text(AppIconCatalog.label(for: normalizedSelection.wrappedValue, fallbackSymbol: fallbackSymbol))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                AppIconGlyph(
                    icon: normalizedSelection.wrappedValue,
                    fallbackSymbol: fallbackSymbol,
                    pointSize: 18,
                    weight: .semibold,
                    tint: tint
                )
                .frame(width: 24, height: 24)
            }
        }
    }

    private var normalizedSelection: Binding<String> {
        Binding(
            get: {
                AppIconToken.normalizedSelection(selection, fallbackSymbol: fallbackSymbol)
            },
            set: { newValue in
                selection = AppIconToken.normalizedSelection(newValue, fallbackSymbol: fallbackSymbol)
            }
        )
    }
}

struct AppIconPickerView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case symbols
        case emoji

        var id: String { rawValue }
    }

    let title: String
    let fallbackSymbol: String

    @Binding var selection: String
    @State private var mode: Mode
    @State private var customEmoji: String

    init(title: String, fallbackSymbol: String, selection: Binding<String>) {
        self.title = title
        self.fallbackSymbol = fallbackSymbol
        _selection = selection

        let current = AppIconToken(selection.wrappedValue, fallbackSymbol: fallbackSymbol)
        _mode = State(initialValue: current.isEmoji ? .emoji : .symbols)
        _customEmoji = State(initialValue: current.isEmoji ? current.storageValue : "")
    }

    var body: some View {
        Form {
            Section("Selected") {
                HStack(spacing: 12) {
                    AppIconGlyph(
                        icon: selection,
                        fallbackSymbol: fallbackSymbol,
                        pointSize: 28,
                        weight: .semibold,
                        tint: Color.accentColor
                    )
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppIconCatalog.label(for: selection, fallbackSymbol: fallbackSymbol))
                        Text(AppIconToken(selection, fallbackSymbol: fallbackSymbol).isEmoji ? "Emoji" : "SF Symbol")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    selection = fallbackSymbol
                    mode = .symbols
                } label: {
                    HStack {
                        Text("Use Default")
                        Spacer()
                        if AppIconToken.normalizedSelection(selection, fallbackSymbol: fallbackSymbol) == fallbackSymbol {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            Section {
                Picker("Source", selection: $mode) {
                    Text("Symbols").tag(Mode.symbols)
                    Text("Emoji").tag(Mode.emoji)
                }
                .pickerStyle(.segmented)
            }

            if mode == .emoji {
                Section("Custom Emoji") {
                    TextField("Paste one emoji", text: $customEmoji)
                        .modifier(AppIconNeverAutocapitalization())
                        .autocorrectionDisabled()
                        .font(.system(size: 28))
                        .onChange(of: customEmoji) { _, newValue in
                            let normalized = AppIconToken.normalizedEmoji(from: newValue) ?? ""
                            if normalized != newValue {
                                customEmoji = normalized
                            }
                            if !normalized.isEmpty {
                                selection = normalized
                            }
                        }

                    Text("Curated emoji below are optional. You can paste your own single emoji here instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(mode == .symbols ? AppIconCatalog.symbolSections : AppIconCatalog.emojiSections) { section in
                Section(section.title) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(section.options) { option in
                            AppIconGridButton(
                                option: option,
                                fallbackSymbol: fallbackSymbol,
                                isSelected: AppIconToken.normalizedSelection(selection, fallbackSymbol: fallbackSymbol) == option.value
                            ) {
                                selection = option.value
                                if AppIconToken.isEmojiValue(option.value) {
                                    customEmoji = option.value
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(title)
        .modifier(AppIconInlineTitleDisplayMode())
        .onChange(of: selection) { _, newValue in
            let normalized = AppIconToken(newValue, fallbackSymbol: fallbackSymbol)
            if normalized.isEmoji {
                customEmoji = normalized.storageValue
            }
        }
    }
}

private struct AppIconGridButton: View {
    let option: AppIconOption
    let fallbackSymbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10))
                    .frame(height: 52)

                AppIconGlyph(
                    icon: option.value,
                    fallbackSymbol: fallbackSymbol,
                    pointSize: 22,
                    weight: .semibold,
                    tint: isSelected ? Color.accentColor : Color.primary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
