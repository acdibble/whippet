import SwiftUI
import Translation

extension PermissionGate {
    /// A view that downloads the languages for a translation once it's in a window, for `ref`, calling `onFinish`
    /// when it's done or cancelled at the system's prompt. Nil when `ref` may not ask macOS to download anything.
    func languageDownload(
        _ configuration: TranslationSession.Configuration, for ref: ModuleRef,
        onFinish: @escaping @MainActor @Sendable () -> Void
    ) -> AnyView? {
        guard allows(.systemDownloads, for: ref) else { return nil }
        return AnyView(LanguageDownloadView(configuration: configuration, onFinish: onFinish))
    }
}

/// Downloads the languages for a translation from an invisible window. The system asks first, in a window of its own
/// that takes focus, which would close the launcher and end a session it started, so the session lives here instead.
private struct LanguageDownloadView: View {
    let configuration: TranslationSession.Configuration
    let onFinish: @MainActor @Sendable () -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { @Sendable session in
                // Finished, or cancelled at the prompt: either way the launcher comes back.
                try? await session.prepareTranslation()
                await onFinish()
            }
    }
}
