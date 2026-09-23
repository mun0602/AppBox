import UIKit
import PBPlayerKit

@objc(TempMailHostDelegate)
final class TempMailHostDelegate: UIResponder, UIApplicationDelegate, UIKitCompatible {
  var window: UIWindow?
  private var surfaceCoordinator: TempMailSurfaceCoordinatorViewController?

  var keyWindow: UIWindow {
    if let window { return window }
    if let activeWindow = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap(\.windows)
      .first(where: \.isKeyWindow) {
      return activeWindow
    }
    fatalError("TempMail window has not been created")
  }

  var rootVC: UIViewController {
    guard let root = keyWindow.rootViewController else {
      fatalError("TempMail root controller has not been created")
    }
    return root
  }

  var currentVC: UIViewController {
    var controller = rootVC
    while let presented = controller.presentedViewController {
      controller = presented
    }
    if let navigation = controller as? UINavigationController,
       let visible = navigation.visibleViewController {
      return visible
    }
    if let tabs = controller as? UITabBarController,
       let selected = tabs.selectedViewController {
      return selected
    }
    return controller
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    self.window = window
    if ProcessInfo.processInfo.arguments.contains("--tempmail-playbox-developer") {
      PBPlayerKitBox.setupApp()
      guard let controllerClass = NSClassFromString("PBPlayerKit.DeveloperController") as? NSObject.Type,
            let controller = controllerClass.init() as? UIViewController else {
        print("TEMPMAIL_PLAYBOX_DEVELOPER boot_failed reason=controller_missing")
        return false
      }
      let navigation = UINavigationController(rootViewController: controller)
      window.rootViewController = navigation
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        self.inspectDeveloperController(controller, navigation: navigation)
      }
    } else {
      let coordinator = TempMailSurfaceCoordinatorViewController()
      surfaceCoordinator = coordinator
      window.rootViewController = coordinator
    }
    window.makeKeyAndVisible()
    if let url = launchOptions?[.url] as? URL {
      _ = surfaceCoordinator?.handle(url: url)
    }
    print("TEMPMAIL_RUNTIME host_ready runtime=\(ProcessInfo.processInfo.arguments.contains("--tempmail-playbox-developer") ? "playbox_developer" : "launcher")")
    return true
  }

  func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    surfaceCoordinator?.handle(url: url) ?? false
  }

  private func inspectDeveloperController(
    _ controller: UIViewController,
    navigation: UINavigationController
  ) {
    controller.loadViewIfNeeded()
    guard let table = findTableView(in: controller.view),
          let dataSource = table.dataSource else {
      print("TEMPMAIL_PLAYBOX_DEVELOPER table_missing")
      return
    }
    let sectionCount = dataSource.numberOfSections?(in: table) ?? 1
    print("TEMPMAIL_PLAYBOX_DEVELOPER table sections=\(sectionCount)")
    for section in 0..<sectionCount {
      let rows = dataSource.tableView(table, numberOfRowsInSection: section)
      for row in 0..<rows {
        let indexPath = IndexPath(row: row, section: section)
        let cell = dataSource.tableView(table, cellForRowAt: indexPath)
        print("TEMPMAIL_PLAYBOX_DEVELOPER row section=\(section) row=\(row) text=\(viewText(in: cell).joined(separator: " | "))")
      }
    }
  }

  private func findTableView(in view: UIView) -> UITableView? {
    if let table = view as? UITableView { return table }
    for subview in view.subviews {
      if let table = findTableView(in: subview) { return table }
    }
    return nil
  }

  private func viewText(in view: UIView) -> [String] {
    var result: [String] = []
    if let label = view as? UILabel, let text = label.text, !text.isEmpty {
      result.append(text)
    }
    for subview in view.subviews {
      result.append(contentsOf: viewText(in: subview))
    }
    return result
  }
}
