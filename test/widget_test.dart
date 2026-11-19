import 'package:app_lock/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _appLockChannel = MethodChannel('com.example.app_lock/app_lock');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final protectedPackages = <String>['com.whatsapp', 'net.one97.paytm'];
  final savedSettings = <String, Object?>{
    'backend': 'Usage Statistics',
    'biometricEnabled': false,
    'hapticEnabled': false,
    'antiUninstallEnabled': false,
    'unlockAllProtectedApps': false,
    'unlockDuration': 'Until screen off',
  };
  var pinIsSet = false;

  setUp(() {
    pinIsSet = false;
    savedSettings
      ..['backend'] = 'Usage Statistics'
      ..['biometricEnabled'] = false
      ..['hapticEnabled'] = false
      ..['antiUninstallEnabled'] = false
      ..['unlockAllProtectedApps'] = false
      ..['unlockDuration'] = 'Until screen off';
    protectedPackages
      ..clear()
      ..addAll(['com.whatsapp', 'net.one97.paytm']);
    binaryMessenger.setMockMethodCallHandler(_appLockChannel, (call) async {
      switch (call.method) {
        case 'getInstalledApps':
          return [
            {'name': 'WhatsApp', 'packageName': 'com.whatsapp'},
            {'name': 'Paytm', 'packageName': 'net.one97.paytm'},
            {'name': 'Chrome', 'packageName': 'com.android.chrome'},
          ];
        case 'getProtectedApps':
          return protectedPackages;
        case 'isAppLockEnabled':
          return true;
        case 'isAccessibilityServiceEnabled':
          return false;
        case 'getSettings':
          return savedSettings;
        case 'isBackendReady':
          return false;
        case 'syncBackend':
          return false;
        case 'hasPin':
          return pinIsSet;
        case 'setBooleanSetting':
          final args = call.arguments! as Map<Object?, Object?>;
          savedSettings[args['key']! as String] = args['value']! as bool;
          return null;
        case 'setBackend':
          savedSettings['backend'] = call.arguments! as String;
          return null;
        case 'setAntiUninstallProtection':
          savedSettings['antiUninstallEnabled'] = call.arguments! as bool;
          return call.arguments;
        case 'isUsageAccessGranted':
        case 'isOverlayPermissionGranted':
          return false;
        case 'setProtectedApps':
          protectedPackages
            ..clear()
            ..addAll((call.arguments! as List<Object?>).cast<String>());
          return null;
        case 'validatePin':
          return call.arguments == '1234';
        case 'getPinLockoutRemaining':
          return 0;
        case 'setPin':
          pinIsSet = true;
          return null;
        case 'setAppLockEnabled':
        case 'openAccessibilitySettings':
        case 'openUsageAccessSettings':
        case 'openOverlaySettings':
          return null;
        case 'setUnlockDuration':
          savedSettings['unlockDuration'] = call.arguments! as String;
          return null;
        default:
          throw MissingPluginException('Unimplemented method ${call.method}');
      }
    });
  });

  tearDown(() {
    binaryMessenger.setMockMethodCallHandler(_appLockChannel, null);
  });

  testWidgets('shows the selected installed apps', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('App Lock'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Paytm'), findsOneWidget);
    expect(find.text('Protected'), findsNWidgets(2));
  });

  testWidgets('requires the saved PIN before managing protected apps', (
    tester,
  ) async {
    pinIsSet = true;
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Enter password to continue'), findsOneWidget);
    expect(find.byKey(const ValueKey('appPinKey_Digit 1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appPinKey_Delete last digit')),
      findsOneWidget,
    );
    expect(find.text('WhatsApp'), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);

    for (final digit in ['0', '0', '0', '0']) {
      await tester.tap(find.byKey(ValueKey('appPinKey_Digit $digit')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
    expect(find.text('WhatsApp'), findsNothing);

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.byKey(ValueKey('appPinKey_Digit $digit')));
      await tester.pumpAndSettle();
    }
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('requires the PIN again after returning from the background', (
    tester,
  ) async {
    pinIsSet = true;
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.byKey(ValueKey('appPinKey_Digit $digit')));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Change PIN'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Enter password to continue'), findsOneWidget);
    expect(find.text('Change PIN'), findsNothing);
  });

  testWidgets('can toggle unlocking all protected apps together', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Unlock protected apps individually'));
    await tester.pumpAndSettle();

    expect(savedSettings['unlockAllProtectedApps'], isTrue);
    expect(
      find.byTooltip('Unlock all protected apps together'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Unlock all protected apps together'));
    await tester.pumpAndSettle();

    expect(savedSettings['unlockAllProtectedApps'], isFalse);
    expect(
      find.byTooltip('Unlock protected apps individually'),
      findsOneWidget,
    );
  });

  testWidgets('can set a PIN before enabling protection', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '2468');
    await tester.enterText(find.byType(TextFormField).at(1), '2468');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    expect(find.text('Grant access'), findsOneWidget);
  });

  testWidgets('checks the PIN automatically after the fourth digit', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '1234');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Unlock with PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pumpAndSettle();

    expect(find.text('Enter password to continue'), findsNothing);
    expect(find.text('App Lock unlocked'), findsOneWidget);
  });

  testWidgets('removing protection persists the selected package list', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove protection').first);
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp'), findsNothing);
    expect(protectedPackages, ['net.one97.paytm']);
  });

  testWidgets('settings switches can be changed', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Lock Screen Customization'), findsOneWidget);
    expect(find.byType(Switch).first, findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('biometric and haptic settings persist', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final biometricSwitch = find.byType(Switch).at(1);
    await tester.ensureVisible(biometricSwitch);
    await tester.tap(biometricSwitch);
    await tester.pumpAndSettle();
    expect(savedSettings['biometricEnabled'], isTrue);

    final hapticSwitch = find.byType(Switch).at(2);
    await tester.ensureVisible(hapticSwitch);
    await tester.tap(hapticSwitch);
    await tester.pumpAndSettle();
    expect(savedSettings['hapticEnabled'], isTrue);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, isTrue);
  });

  testWidgets('removes Advanced and Links settings sections', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Advanced'), findsNothing);
    expect(find.text('Links'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Backend Implementation'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Backend Implementation'), findsOneWidget);
  });

  testWidgets('unlock duration options persist', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock Time Duration'));
    await tester.pumpAndSettle();
    expect(find.text('After 10 minutes'), findsOneWidget);
    expect(find.text('After 15 minutes'), findsOneWidget);
    expect(find.text('After 30 minutes'), findsOneWidget);
    expect(find.text('After 1 hour'), findsOneWidget);

    await tester.tap(find.text('After 15 minutes'));
    await tester.pumpAndSettle();
    expect(savedSettings['unlockDuration'], 'After 15 minutes');
  });

  testWidgets('anti-uninstall switch requests Android admin activation', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final antiUninstallSwitch = find.byType(Switch).at(4);
    await tester.scrollUntilVisible(
      antiUninstallSwitch,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(antiUninstallSwitch);
    await tester.pumpAndSettle();

    expect(savedSettings['antiUninstallEnabled'], isTrue);
    expect(tester.widget<Switch>(antiUninstallSwitch).value, isTrue);
  });

  testWidgets('can add an installed app to the protected list', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chrome'));
    await tester.pump();
    expect(find.text('Add (1)'), findsOneWidget);

    await tester.tap(find.text('Add (1)'));
    await tester.pumpAndSettle();

    expect(protectedPackages, [
      'com.whatsapp',
      'net.one97.paytm',
      'com.android.chrome',
    ]);
    expect(find.text('Chrome'), findsOneWidget);
  });
}
