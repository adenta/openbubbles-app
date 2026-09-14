# Desktop close and tray lifecycle

The startup `Home` route is removed when sign-in completes (`Get.offAll` in
`finalize.dart`, among other navigation paths). Previously its `dispose` method
removed the application window listener and Linux tray listener. Native
`preventClose` stayed enabled for Close to Tray, but no Dart listener remained
to hide the window. Both a compositor close request (Super+W on XPS) and the
custom X button could therefore leave the window visible. Tray actions were
also lost.

`DesktopLifecycle` now owns the window listener, tray initialization, and tray
callbacks above the application Navigator. Replacing a route leaves them
attached; disposing the app root removes them. Close to Tray still hides the
window and preserves background messaging, while the tray's Close App action
disables close prevention and requests an actual quit. The initial tray menu
uses `window_manager`'s visibility query because the pinned Bitsdojo Linux
visibility getter always returns true.

Run the focused regression tests with the managed toolchain:

```sh
mise exec flutter@3.24.0 -- flutter test --no-pub test/desktop_lifecycle_test.dart
```

The tests replace and dispose a startup route, deliver native window and tray
events through mocked platform channels, and exercise the production close
listener. They check hide-on-close, tray restore and quit, disabling Close to
Tray, and cleanup when the app root is disposed. They do not sign in or touch
user data. Physical Super+W and X-button interaction on XPS still requires
validation with the updated installed build.
