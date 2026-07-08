import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    // App Group identifier — must match the main app
    private let appGroupId = "group.com.reeltune.app"
    private let sharedKey = "SharedData"

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let extensionContext = self.extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Handle URLs
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] data, error in
                        guard let self = self else { return }

                        var urlString: String?
                        if let url = data as? URL {
                            urlString = url.absoluteString
                        } else if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urlString = url.absoluteString
                        }

                        if let urlString = urlString {
                            self.saveSharedData(urlString, type: "url")
                            self.openMainApp()
                        }
                        self.completeRequest()
                    }
                    return
                }

                // Handle plain text (some apps share URLs as text)
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, error in
                        guard let self = self else { return }

                        if let text = data as? String {
                            // Check if the text is a URL
                            if text.contains("http://") || text.contains("https://") {
                                self.saveSharedData(text, type: "url")
                            } else {
                                self.saveSharedData(text, type: "text")
                            }
                            self.openMainApp()
                        }
                        self.completeRequest()
                    }
                    return
                }

                // Handle video files
                if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] data, error in
                        guard let self = self else { return }

                        if let url = data as? URL {
                            // Copy video to shared container
                            let sharedContainer = FileManager.default.containerURL(
                                forSecurityApplicationGroupIdentifier: self.appGroupId
                            )
                            if let sharedContainer = sharedContainer {
                                let destURL = sharedContainer.appendingPathComponent("shared_video.mp4")
                                try? FileManager.default.removeItem(at: destURL)
                                try? FileManager.default.copyItem(at: url, to: destURL)
                                self.saveSharedData(destURL.path, type: "video")
                                self.openMainApp()
                            }
                        }
                        self.completeRequest()
                    }
                    return
                }
            }
        }

        // If no matching attachments found, just complete
        completeRequest()
    }

    private func saveSharedData(_ data: String, type: String) {
        let userDefaults = UserDefaults(suiteName: appGroupId)
        let sharedData: [String: Any] = [
            "data": data,
            "type": type,
            "timestamp": Date().timeIntervalSince1970
        ]
        userDefaults?.set(sharedData, forKey: sharedKey)
        userDefaults?.synchronize()
    }

    private func openMainApp() {
        guard let url = URL(string: "reeltune://share") else { return }

        // Use responder chain to open URL
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = responder?.next
        }
    }

    private func completeRequest() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
