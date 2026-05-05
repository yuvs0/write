import Foundation
import Combine

@Observable
final class AutosaveController {
    private var timer: Timer?
    private var lastSavedText: String = ""
    private let interval: TimeInterval = 1.0
    private var fileURL: URL?

    var isDirty: Bool {
        currentText != lastSavedText
    }

    var currentText: String = "" {
        didSet {
            if timer == nil {
                startTimer()
            }
        }
    }

    func configure(fileURL: URL, initialText: String) {
        self.fileURL = fileURL
        self.lastSavedText = initialText
        self.currentText = initialText
        startTimer()
    }

    func markExplicitSave() {
        lastSavedText = currentText
        removeAutosaveFile()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.writeAutosaveIfNeeded()
        }
    }

    private func writeAutosaveIfNeeded() {
        guard isDirty, let fileURL else { return }

        let autosaveURL = fileURL.appendingPathComponent("autosave.md")
        let data = currentText.data(using: .utf8) ?? Data()

        try? data.write(to: autosaveURL, options: .atomic)
    }

    private func removeAutosaveFile() {
        guard let fileURL else { return }
        let autosaveURL = fileURL.appendingPathComponent("autosave.md")
        try? FileManager.default.removeItem(at: autosaveURL)
    }
}
