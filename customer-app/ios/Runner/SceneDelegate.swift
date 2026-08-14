import Flutter
import UIKit

/// Under the UIScene lifecycle the app's window belongs to this delegate, and
/// `UIApplication.shared.delegate.window` — where it used to live — stays nil.
///
/// Plugins written before scenes were adopted still look the window up there to
/// find something to present from. flutter_stripe 11.x is one of them: every
/// presenting call in `stripe_ios` reads
/// `UIApplication.shared.delegate?.window??.rootViewController` and falls back
/// to a bare `UIViewController()` when that is nil. Presenting the payment
/// sheet from a controller that belongs to no window puts nothing on screen and
/// never calls the completion handler, so the future returned by
/// `presentPaymentSheet()` never completes — which is exactly the "spinner runs
/// forever, no card sheet" that checkout and continue-payment showed on iOS.
/// Nothing throws, so there is no error to report to the customer either.
///
/// Lending this scene's window to the app delegate keeps that older lookup
/// working, and is what Flutter itself does when it migrates a pre-scene app
/// delegate (`FlutterSceneDelegate.moveRootViewControllerFrom`). stripe_ios 13
/// searches `UIApplication.shared.connectedScenes` instead, so this can go once
/// the app moves to flutter_stripe 13.
class SceneDelegate: FlutterSceneDelegate {
  /// The window currently lent to the app delegate. Held statically because the
  /// scene that lends it out and the one that takes it back are not necessarily
  /// the same instance, and weakly because the app delegate's own reference is
  /// what keeps it alive.
  private static weak var lentWindow: UIWindow?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // A window still parked on the app delegate reads to Flutter as an app that
    // sets its root view controller up the pre-scene way, which makes it log a
    // deprecation warning and re-home that controller into a window of its own.
    // Take back anything a previous scene left behind before super looks.
    reclaimWindowFromAppDelegate()

    super.scene(scene, willConnectTo: session, options: connectionOptions)

    lendWindowToAppDelegate()
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)

    // UIKit attaches the storyboard's window before the scene connects, so the
    // call above is normally the one that counts. This covers a window that
    // arrives any later, and keeps the lent window pointing at the scene a
    // payment sheet would actually be presented over.
    lendWindowToAppDelegate()
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    // Presenting into a window that is no longer on screen is as invisible as
    // presenting into none, so don't leave a disconnected one behind.
    reclaimWindowFromAppDelegate()

    super.sceneDidDisconnect(scene)
  }

  private func lendWindowToAppDelegate() {
    guard let window, let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate
    else { return }

    appDelegate.window = window
    SceneDelegate.lentWindow = window
  }

  private func reclaimWindowFromAppDelegate() {
    guard let lentWindow = SceneDelegate.lentWindow,
      let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate,
      appDelegate.window === lentWindow
    else { return }

    appDelegate.window = nil
    SceneDelegate.lentWindow = nil
  }
}
