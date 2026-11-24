import SwiftUI

@MainActor
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Acquire resources only when the activity controller is ready to be presented.
    var beginActivity: @MainActor () -> (@MainActor () -> Void) = { {} }
    var onDismiss: @MainActor () -> Void = {}

    @MainActor
    final class Coordinator {
        var completion: (@MainActor () -> Void)?

        func complete() {
            let callback = completion
            completion = nil
            callback?()
        }
    }

    /// Presents the activity controller itself rather than embedding it in a SwiftUI sheet.
    /// UIKit therefore owns its Close, popover cancellation and activity completion paths.
    @MainActor
    final class Presenter: UIViewController {
        private let makeActivity: @MainActor () -> UIActivityViewController
        private(set) var hasPresented = false
        private var waitingForTransition = false

        init(makeActivity: @escaping @MainActor () -> UIActivityViewController) {
            self.makeActivity = makeActivity
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfReady()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            // Recheck window attachment after layout as well as appearance.
            // Defer until this layout/update has finished before presenting UIKit content.
            Task { @MainActor [weak self] in self?.presentIfReady() }
        }

        func presentIfReady() {
            guard !hasPresented, !waitingForTransition,
                  let host = viewIfLoaded?.window?.rootViewController else { return }
            if let presented = host.presentedViewController {
                // Export closes its instruction sheet first. Wait for that transition rather
                // than presenting over a controller which is about to be dismissed.
                if let transition = presented.transitionCoordinator ?? host.transitionCoordinator {
                    waitingForTransition = true
                    transition.animate(alongsideTransition: nil) { [weak self] _ in
                        self?.waitingForTransition = false
                        self?.presentIfReady()
                    }
                }
                return
            }
            hasPresented = true
            let activity = makeActivity()
            if let popover = activity.popoverPresentationController {
                popover.sourceView = host.view
                popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            host.present(activity, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> Presenter {
        let coordinator = context.coordinator
        return Presenter { activityController(coordinator: coordinator) }
    }

    func activityController(coordinator: Coordinator) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let release = beginActivity()
        coordinator.completion = {
            release()
            onDismiss()
        }
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Neither representable teardown nor presentation disappearance releases a consumer.
            Task { @MainActor in coordinator.complete() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: Presenter, context: Context) {
        Task { @MainActor [weak uiViewController] in uiViewController?.presentIfReady() }
    }
}
