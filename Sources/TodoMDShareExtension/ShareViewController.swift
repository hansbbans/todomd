import Foundation
import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool {
        let typedText = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !typedText.isEmpty || hasSupportedAttachment
    }

    override func didSelectPost() {
        Task {
            do {
                let payload = try await buildPayload()
                try createTask(from: payload)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                extensionContext?.cancelRequest(withError: error)
            }
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private var hasSupportedAttachment: Bool {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return false
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    return true
                }
            }
        }

        return false
    }

    private func buildPayload() async throws -> (title: String, body: String) {
        var fragments: [String] = []

        let typedText = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedText.isEmpty {
            fragments.append(typedText)
        }

        if let items = extensionContext?.inputItems as? [NSExtensionItem] {
            for item in items {
                for provider in item.attachments ?? [] {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                       let url = try await loadURL(from: provider) {
                        fragments.append(url.absoluteString)
                        continue
                    }

                    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                        || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
                       let text = try await loadText(from: provider),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        fragments.append(text)
                    }
                }
            }
        }

        let joined = fragments.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = joined.split(whereSeparator: \ .isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Shared Item"

        return (title: String(title.prefix(500)), body: String(joined.prefix(TaskValidation.maxBodyLength)))
    }

    private func createTask(from payload: (title: String, body: String)) throws {
        let folderLocator = TaskFolderLocator()
        let rootURL = try folderLocator.ensureFolderExists()
        let repository = FileTaskRepository(rootURL: rootURL)

        let now = Date()
        let frontmatter = TaskFrontmatterV1(
            title: payload.title,
            status: .todo,
            created: now,
            modified: now,
            source: "share-extension"
        )

        _ = try repository.create(document: TaskDocument(frontmatter: frontmatter, body: payload.body), preferredFilename: nil)
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let nsurl = item as? NSURL {
                    continuation.resume(returning: nsurl as URL)
                    return
                }

                if let text = item as? String, let parsed = URL(string: text) {
                    continuation.resume(returning: parsed)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async throws -> String? {
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            typeIdentifier = UTType.plainText.identifier
        } else {
            typeIdentifier = UTType.text.identifier
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let text = item as? String {
                    continuation.resume(returning: text)
                    return
                }

                if let attributed = item as? NSAttributedString {
                    continuation.resume(returning: attributed.string)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
