import UIKit
import SwiftUI

final class DemoViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

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
        //LucidBanner.shared.show(title: "Export completed", subtitle: "Senza nome.rtf")
    }
}
