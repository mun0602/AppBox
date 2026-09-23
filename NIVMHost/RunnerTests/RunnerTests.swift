import XCTest
@testable import TempMail

final class RunnerTests: XCTestCase {
  func testFreshLaunchUsesMailboxSurface() {
    let suiteName = "TempMailSurfaceTests.fresh.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertEqual(TempMailSurfaceRoute.initialSurface(defaults: defaults), .privacy)
  }

  func testLaunchRestoresSurfaceSelectedByAnEarlierDeepLink() {
    let suiteName = "TempMailSurfaceTests.persisted.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: TempMailSurfaceRoute.activatedKey)

    XCTAssertEqual(TempMailSurfaceRoute.initialSurface(defaults: defaults), .box)
  }

  func testDeepLinksSelectSupportedSurfaces() {
    XCTAssertEqual(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://box")!), .box)
    XCTAssertEqual(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://open?id=tianya")!), .box)
    XCTAssertEqual(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://install")!), .box)
    XCTAssertEqual(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://native")!), .box)
    XCTAssertEqual(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://privacy")!), .privacy)
    XCTAssertEqual(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://focus")!), .privacy)
  }

  func testGuestRelaunchPreservesCurrentSurface() {
    XCTAssertNil(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://sandbox.relaunch")!))
    XCTAssertNil(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://playbox.guestapp.relaunch")!))
  }

  func testUnsupportedURLsAreIgnored() {
    XCTAssertFalse(TempMailSurfaceRoute.supports(scheme: "https"))
    XCTAssertNil(TempMailSurfaceRoute.surface(for: URL(string: "https://3601.help")!))
    XCTAssertNil(TempMailSurfaceRoute.surface(for: URL(string: "tempmail://unknown")!))
  }
}
