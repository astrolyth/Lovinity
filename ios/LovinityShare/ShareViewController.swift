import UIKit
import UniformTypeIdentifiers

// Hands a shared URL/text to the Runner app via the App Group, then opens lovinity://share.
// Keys must match ios/Runner/SceneDelegate.swift. No network access here.
final class ShareViewController: UIViewController {
    private static let appGroup = "group.com.lovinity.lovinity"
    private var handled = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !handled else { return }
        handled = true
        loadShared { [weak self] text, subject in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let text = text else {
                    self.extensionContext?.completeRequest(returningItems: nil)
                    return
                }
                var payload: [String: Any] = ["text": text]
                if let subject = subject { payload["subject"] = subject }
                UserDefaults(suiteName: Self.appGroup)?.set(payload, forKey: "pending_share")
                self.openHostApp()
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    private func loadShared(_ done: @escaping (String?, String?) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let subject = items.compactMap { $0.attributedContentText?.string ?? $0.attributedTitle?.string }
            .first(where: { !$0.isEmpty })
        let providers = items.flatMap { $0.attachments ?? [] }
        let urlId = UTType.url.identifier
        let textId = UTType.plainText.identifier
        let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textId) })
        let loadText = {
            guard let p = textProvider else { return done(nil, nil) }
            p.loadItem(forTypeIdentifier: textId, options: nil) { item, _ in
                let text: String?
                switch item {
                case let s as String: text = s
                case let s as NSAttributedString: text = s.string
                case let d as Data: text = String(data: d, encoding: .utf8)
                default: text = nil
                }
                done(text, subject)
            }
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlId) }) {
            p.loadItem(forTypeIdentifier: urlId, options: nil) { item, _ in
                if let url = (item as? URL)?.absoluteString {
                    done(url, subject)
                } else {
                    loadText()
                }
            }
        } else {
            loadText()
        }
    }

    // Share extensions can't use UIApplication.shared; walk the responder chain instead.
    private func openHostApp() {
        guard let url = URL(string: "lovinity://share") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }
}
