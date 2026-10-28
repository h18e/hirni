import SwiftUI

#if os(iOS)
import UIKit

/// Einstieg der Teilen-Erweiterung auf dem iPhone: zeigt `ShareView`.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: ShareModel(context: extensionContext)))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
#else
import AppKit

/// Einstieg der Teilen-Erweiterung am Mac: zeigt `ShareView`.
final class ShareViewController: NSViewController {
    override func loadView() {
        let host = NSHostingView(rootView: ShareView(model: ShareModel(context: extensionContext)))
        host.frame = CGRect(x: 0, y: 0, width: 420, height: 380)
        view = host
        preferredContentSize = host.frame.size
    }
}
#endif
