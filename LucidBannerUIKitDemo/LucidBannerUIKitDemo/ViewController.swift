import UIKit
import SwiftUI

final class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .lightGray

        let button = UIButton(type: .system)
        button.setTitle("Show Banner", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(showBanner), for: .touchUpInside)

        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func showBanner() {
        guard let scene = SceneStore.shared.scene else { return }
        let banner = LucidBannerRegistry.shared.banner(for: scene)

        let payload = LucidBannerPayload(
            title: "Uploading…",
            subtitle: "name.rtf",
            footnote: "(tap to minimize)",
            systemImage: "arrowshape.up.circle",
            imageAnimation: .breathe,
            progress: 0,
            stage: .button,
            vPosition: .top
        )

        let coordinator = LucidBannerVariantCoordinator(banner: banner)
        let token = banner.show(payload: payload) { state in
            UploadBanner(
                state: state,
                coordinator: coordinator,
                allowMinimizeOnTap: true,
                onButtonTap: {
                    banner.dismiss()
                }
            )
        }

        coordinator.register(token: token, resolveVariant: { context in
            let bounds = context.bounds
            let over: CGFloat = 30
            let regularLayout = context.window.rootViewController?.traitCollection.horizontalSizeClass == .regular
            let iPad = UIDevice.current.userInterfaceIdiom == .pad
            let height: CGFloat = iPad && regularLayout ? over : context.safeAreaInsets.bottom + over

            return LucidBannerVariantCoordinator.VariantResolution(
                targetPoint: CGPoint(x: bounds.midX, y: bounds.maxY - height)
            )
        })

        simulateUploadProgress(token: token, banner: banner)
    }

    private func simulateUploadProgress(token: Int, banner: LucidBanner) {
        var progress = 0.0

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            progress += 0.04

            Task { @MainActor in
                guard banner.isAlive(token) else {
                    timer.invalidate()
                    return
                }

                if progress >= 1.0 {
                    timer.invalidate()
                    banner.update(
                        payload: LucidBannerPayload.Update(
                            title: "",
                            subtitle: "",
                            progress: 1.0,
                            stage: .success,
                            autoDismissAfter: 1.5
                        ),
                        for: token
                    )
                } else {
                    banner.update(
                        payload: LucidBannerPayload.Update(
                            title: "Uploading…",
                            subtitle: "name.rtf",
                            footnote: "(tap to minimize)",
                            progress: progress,
                            stage: .button
                        ),
                        for: token
                    )
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
    }
}
