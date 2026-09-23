import SwiftUI
import UIKit

enum TempMailSurface: Equatable {
  case privacy
  case box
}

enum TempMailSurfaceRoute {
  static let activatedKey = "tempmail.appCenterActivatedFromExternalIntent"
  private static let supportedSchemes: Set<String> = ["tempmail"]

  static func supports(scheme: String) -> Bool {
    supportedSchemes.contains(scheme.lowercased())
  }

  static func initialSurface(
    defaults: UserDefaults = .standard
  ) -> TempMailSurface {
    return defaults.bool(forKey: activatedKey) ? .box : .privacy
  }

  static func surface(for url: URL) -> TempMailSurface? {
    guard let scheme = url.scheme?.lowercased(), supports(scheme: scheme) else {
      return nil
    }
    let host = (url.host ?? "").lowercased()
    let path = url.path
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .lowercased()
    let command = host.isEmpty ? path : host

    switch command {
    case "box", "open", "install", "native":
      return .box
    case "privacy", "focus":
      return .privacy
    case "sandbox.relaunch", "playbox.guestapp.relaunch":
      return nil
    default:
      return nil
    }
  }
}

final class TempMailSurfaceCoordinatorViewController: UIViewController {
  private let defaults: UserDefaults
  private var currentSurface: TempMailSurface?
  private var currentController: UIViewController?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let initialSurface = TempMailSurfaceRoute.initialSurface(defaults: defaults)
    show(
      initialSurface,
      animated: false,
      persist: false
    )
    print("TEMPMAIL_SURFACE initial=\(initialSurface == .privacy ? "privacy" : "box")")
  }

  @discardableResult
  func handle(url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(),
          TempMailSurfaceRoute.supports(scheme: scheme) else {
      return false
    }
    guard let surface = TempMailSurfaceRoute.surface(for: url) else {
      // The relaunch URL intentionally preserves the currently activated face.
      let host = url.host?.lowercased()
      return host == "sandbox.relaunch" || host == "playbox.guestapp.relaunch"
    }
    show(surface, animated: view.window != nil, persist: true)
    print("TEMPMAIL_SURFACE url=\(url.absoluteString) selected=\(surface == .privacy ? "privacy" : "box")")
    return true
  }

  private func show(
    _ surface: TempMailSurface,
    animated: Bool,
    persist: Bool
  ) {
    guard surface != currentSurface else {
      return
    }

    if persist {
      defaults.set(surface == .box, forKey: TempMailSurfaceRoute.activatedKey)
      defaults.synchronize()
    }

    let nextController: UIViewController
    switch surface {
    case .privacy:
      nextController = UIHostingController(rootView: TempMailMailboxSurfaceView())
    case .box:
      nextController = TempMailLauncherViewController()
    }

    addChild(nextController)
    nextController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(nextController.view)
    NSLayoutConstraint.activate([
      nextController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      nextController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      nextController.view.topAnchor.constraint(equalTo: view.topAnchor),
      nextController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    nextController.didMove(toParent: self)

    let previousController = currentController
    currentController = nextController
    currentSurface = surface

    let finishTransition = {
      previousController?.willMove(toParent: nil)
      previousController?.view.removeFromSuperview()
      previousController?.removeFromParent()
    }

    guard animated, let previousController else {
      finishTransition()
      return
    }

    nextController.view.alpha = 0
    UIView.animate(
      withDuration: 0.22,
      animations: {
        nextController.view.alpha = 1
        previousController.view.alpha = 0
      },
      completion: { _ in
        previousController.view.alpha = 1
        finishTransition()
      }
    )
  }
}
