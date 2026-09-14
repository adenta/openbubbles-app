import 'package:bluebubbles/app/wrappers/desktop_lifecycle.dart';
import 'package:bluebubbles/main.dart' show DesktopWindowListener;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const trayChannel = MethodChannel('tray_manager');
  final calls = <MethodCall>[];
  var preventClose = true;
  var visible = true;
  var menuItems = <dynamic>[];

  Future<void> nativeEvent(MethodChannel channel, MethodCall call) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(call),
      (_) {},
    );
  }

  Future<void> trayAction(String key) => nativeEvent(
        trayChannel,
        MethodCall('onTrayMenuItemClick', {
          'id': menuItems.singleWhere((item) => item['key'] == key)['id'],
        }),
      );

  setUp(() {
    preventClose = true;
    visible = true;
    calls.clear();
    menuItems = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel,
        (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isPreventClose':
          return preventClose;
        case 'setPreventClose':
          preventClose = call.arguments['isPreventClose'] as bool;
          return null;
        case 'isVisible':
          return visible;
        case 'isMinimized':
          return false;
        case 'hide':
          visible = false;
          return null;
        case 'show':
          visible = true;
          return null;
      }
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(trayChannel,
        (call) async {
      if (call.method == 'setContextMenu') {
        menuItems = call.arguments['menu']['items'] as List<dynamic>;
      }
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(trayChannel, null);
  });

  testWidgets('close and tray actions survive replacing the startup route',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var startupDisposed = false;
    await tester.pumpWidget(DesktopLifecycle(
      windowListener: DesktopWindowListener.instance,
      child: MaterialApp(
        navigatorKey: navigator,
        home: _StartupRoute(onDispose: () => startupDisposed = true),
      ),
    ));
    await tester.pumpAndSettle();

    // Finishing sign-in removes Home with Get.offAll. Exercise the same
    // disposal through Navigator without signing in or accessing user data.
    navigator.currentState!.pushAndRemoveUntil(
      MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Conversations'))),
      (_) => false,
    );
    await tester.pumpAndSettle();
    expect(startupDisposed, isTrue);

    calls.clear();
    // Both the custom X button and the compositor produce this native event.
    await nativeEvent(
        windowChannel, const MethodCall('onEvent', {'eventName': 'close'}));
    await tester.pumpAndSettle();
    expect(visible, isFalse);
    expect(calls.where((call) => call.method == 'hide'), hasLength(1));
    expect(preventClose, isTrue);

    await nativeEvent(
        windowChannel, const MethodCall('onEvent', {'eventName': 'hide'}));
    await tester.pumpAndSettle();
    expect(menuItems.first['label'], 'Show App');
    await trayAction('show_app');
    await tester.pumpAndSettle();
    expect(visible, isTrue);

    calls.clear();
    await trayAction('close_app');
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method),
        ['isPreventClose', 'setPreventClose', 'close']);
    expect(preventClose, isFalse);
  });

  testWidgets('native close is not hidden when close to tray is disabled',
      (tester) async {
    preventClose = false;
    await tester.pumpWidget(DesktopLifecycle(
      windowListener: DesktopWindowListener.instance,
      child: const SizedBox(),
    ));
    await tester.pumpAndSettle();
    calls.clear();
    await nativeEvent(
        windowChannel, const MethodCall('onEvent', {'eventName': 'close'}));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['isPreventClose']);
  });

  testWidgets('listeners are removed when the app root is disposed',
      (tester) async {
    await tester.pumpWidget(DesktopLifecycle(
      windowListener: DesktopWindowListener.instance,
      child: const SizedBox(),
    ));
    await tester.pumpAndSettle();
    expect(windowManager.hasListeners, isTrue);
    expect(trayManager.hasListeners, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(windowManager.hasListeners, isFalse);
    expect(trayManager.hasListeners, isFalse);
  });
}

class _StartupRoute extends StatefulWidget {
  const _StartupRoute({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_StartupRoute> createState() => _StartupRouteState();
}

class _StartupRouteState extends State<_StartupRoute> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Setup'));
}
