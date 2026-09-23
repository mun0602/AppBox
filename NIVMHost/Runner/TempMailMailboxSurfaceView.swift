import SwiftUI

/// Hosts the complete temporary-mail product surface inside TempMail's existing
/// UIKit A/B coordinator. The coordinator remains the sole owner of surface
/// transitions; this view owns only the first-party mailbox experience.
struct TempMailMailboxSurfaceView: View {
  @StateObject private var store = TempMailStore()

  var body: some View {
    TempMailRootView()
      .environmentObject(store)
  }
}
