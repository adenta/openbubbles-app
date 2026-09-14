import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:system_tray/system_tray.dart' as st;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final systemTray = st.SystemTray();

/// Owns desktop controls above the Navigator so replacing a route cannot
/// disable window closing or tray actions.
class DesktopLifecycle extends StatefulWidget {
  const DesktopLifecycle(
      {super.key, required this.windowListener, required this.child});

  final WindowListener windowListener;
  final Widget child;

  @override
  State<DesktopLifecycle> createState() => _DesktopLifecycleState();
}

class _DesktopLifecycleState extends State<DesktopLifecycle> with TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(widget.windowListener);
    if (!Platform.isWindows) trayManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await initSystemTray();
      if (!mounted) return;
      if (Platform.isWindows) {
        systemTray.registerSystemTrayEventHandler((eventName) {
          if (!mounted) return;
          if (eventName == st.kSystemTrayEventClick) {
            onTrayIconMouseDown();
          } else if (eventName == st.kSystemTrayEventRightClick) {
            onTrayIconRightMouseDown();
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(DesktopLifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowListener != widget.windowListener) {
      windowManager.removeListener(oldWidget.windowListener);
      windowManager.addListener(widget.windowListener);
    }
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() async {
    if (Platform.isWindows) {
      await systemTray.popUpContextMenu();
    } else {
      await trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_app':
        await windowManager.show();
        break;
      case 'hide_app':
        await windowManager.hide();
        break;
      case 'close_app':
        if (await windowManager.isPreventClose()) {
          await windowManager.setPreventClose(false);
        }
        await windowManager.close();
        break;
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(widget.windowListener);
    if (!Platform.isWindows) trayManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> initSystemTray() async {
  if (Platform.isWindows) {
    await systemTray.initSystemTray(
      iconPath: 'assets/icon/icon.ico',
      toolTip: "OpenBubbles",
    );
  } else {
    String path;
    if (Platform.isLinux && Platform.environment.containsKey('FLATPAK_ID')) {
      path = 'app.bluebubbles.BlueBubbles';
    } else if (Platform.isLinux) {
      path = p.joinAll([
        p.dirname(Platform.resolvedExecutable),
        'data/flutter_assets/assets/icon',
        'icon.png'
      ]);
    } else {
      path = 'assets/icon/icon.png';
    }

    if (Platform.isLinux) {
      // The pinned plugin otherwise generates a new short ID on every launch.
      // Supply a stable, D-Bus-safe ID and the absolute packaged icon path.
      await const MethodChannel('tray_manager').invokeMethod('setIcon', {
        'id': 'app_openbubbles_Dev',
        'iconPath': path,
      });
    } else {
      await trayManager.setIcon(path);
    }
  }

  await setSystemTrayContextMenu(
      windowHidden: !await windowManager.isVisible());
}

Future<void> setSystemTrayContextMenu({bool windowHidden = false}) async {
  if (Platform.isWindows) {
    st.Menu menu = st.Menu();
    menu.buildFrom([
      st.MenuItemLabel(
        label: windowHidden ? 'Show App' : 'Hide App',
        onClicked: (st.MenuItemBase menuItem) async {
          if (windowHidden) {
            await windowManager.show();
          } else {
            await windowManager.hide();
          }
        },
      ),
      st.MenuSeparator(),
      st.MenuItemLabel(
        label: 'Close App',
        onClicked: (_) async {
          if (await windowManager.isPreventClose()) {
            await windowManager.setPreventClose(false);
          }
          await windowManager.close();
        },
      ),
    ]);

    await systemTray.setContextMenu(menu);
  } else {
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(
            label: windowHidden ? 'Show App' : 'Hide App',
            key: windowHidden ? 'show_app' : 'hide_app'),
        MenuItem.separator(),
        MenuItem(label: 'Close App', key: 'close_app'),
      ],
    ));
  }
}
