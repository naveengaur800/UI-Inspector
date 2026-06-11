//
//  InspectorTrigger.swift
//  View Drawing
//
//  Created by Naveen Gaur on 11/06/2026.
//

import DesignReviewKit
import SwiftUI
import UIKit

extension View {
    /// Present the design inspector on device shake (Ctrl+Cmd+Z in the simulator).
    func onShakePresentInspector() -> some View {
        modifier(ShakeInspectorModifier())
    }
}

/// Toolbar button alternative to shaking, for quick access while developing.
struct InspectorToolbarButton: View {

    @Environment(\.designInspector)
    private var inspector

    var body: some View {
        Button {
            inspector?.presentFromForegroundScene()
        } label: {
            Label("Inspect", systemImage: "rectangle.dashed.badge.record")
        }
    }
}

private struct ShakeInspectorModifier: ViewModifier {

    @Environment(\.designInspector)
    private var inspector

    func body(content: Content) -> some View {
        content.background(
            ShakeDetectorView {
                inspector?.presentFromForegroundScene()
            }
            .frame(width: 0, height: 0)
        )
    }
}

private extension DesignInspector {
    /// Begin capture in the active foreground scene.
    func presentFromForegroundScene() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let scene else { return }
        beginCapture(in: scene)
    }
}

/// Invisible responder that listens for the shake motion event.
private struct ShakeDetectorView: UIViewControllerRepresentable {

    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectingViewController {
        let controller = ShakeDetectingViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ uiViewController: ShakeDetectingViewController, context: Context) {
        uiViewController.onShake = onShake
    }
}

final class ShakeDetectingViewController: UIViewController {

    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Reclaim first responder when the host window becomes key again
        // after the inspector's overlay window is dismissed. Registered once
        // here — viewDidAppear fires repeatedly and would stack observers.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: UIWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? UIWindow, window == view.window else { return }
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onShake?()
        } else {
            super.motionEnded(motion, with: event)
        }
    }
}
