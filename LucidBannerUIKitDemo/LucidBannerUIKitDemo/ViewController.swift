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
        let token = showUploadBanner(scene: SceneStore.shared.scene,
                                     stage: .button,
                                     onButtonTap: {
            Task { @MainActor in
                LucidBanner.shared.dismiss()
            }
        })

        simulateUploadProgress(token: token)
    }

    private func simulateUploadProgress(token: Int?) {
        var progress: Double = 0.0

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            progress += 0.04

            if progress >= 1.0 {
                timer.invalidate()
                Task { @MainActor in
                    LucidBanner.shared.update(title: "",
                                              subtitle: "",
                                              progress: 1.0,
                                              stage: .success,
                                              autoDismissAfter: 1.5,
                                              for: token
                    )
                }

            } else {
                // Upload in corso
                Task { @MainActor in
                    LucidBanner.shared.update(title: "Uploading…",
                                              subtitle: "name.rtf",
                                              footnote: "(tap to minimize)",
                                              progress: progress,
                                              stage: .button,
                                              for: token
                    )
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
    }
}
