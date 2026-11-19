import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_lock_models.dart';
import 'settings/settings_screen.dart';
import 'theme/app_lock_theme.dart';
import 'widgets/app_lock_widgets.dart';

const _appLockChannel = MethodChannel('com.example.app_lock/app_lock');

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with WidgetsBindingObserver {
  List<LockedApp> _apps = [];
  bool _enabled = true;
  bool _unlockAllProtectedApps = false;
  bool _serviceEnabled = false;
  bool _hasPin = false;
  bool _loading = true;
  bool _initialLoadComplete = false;
  bool _isAppUnlocked = false;
  bool _isCheckingAppPin = false;
  String _enteredAppPin = '';
  String? _loadError;
  bool _showUnprotected = false;
  String? _appPinError;
  final _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _hasPin) {
      setState(() {
        _isAppUnlocked = false;
        _appPinError = null;
        _enteredAppPin = '';
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_hasPin) {
        setState(() {
          _isAppUnlocked = false;
          _appPinError = null;
          _enteredAppPin = '';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        });
      }
      _loadAppData();
    }
  }

  Future<void> _loadAppData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final installed =
          await _appLockChannel.invokeListMethod<Map<Object?, Object?>>(
            'getInstalledApps',
          ) ??
          [];
      final protected =
          await _appLockChannel.invokeListMethod<String>('getProtectedApps') ??
          [];
      final enabled =
          await _appLockChannel.invokeMethod<bool>('isAppLockEnabled') ?? true;
      final savedSettings =
          await _appLockChannel.invokeMapMethod<String, Object?>(
            'getSettings',
          ) ??
          const <String, Object?>{};
      await _appLockChannel.invokeMethod<bool>('syncBackend');
      final serviceEnabled =
          await _appLockChannel.invokeMethod<bool>('isBackendReady') ?? false;
      final hasPin =
          await _appLockChannel.invokeMethod<bool>('hasPin') ?? false;
      final protectedSet = protected.toSet();
      final apps = installed
          .map(
            (entry) => LockedApp(
              entry['name']! as String,
              entry['packageName']! as String,
              _iconForPackage(entry['packageName']! as String),
              _colorForPackage(entry['packageName']! as String),
              protected: protectedSet.contains(entry['packageName']),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _enabled = enabled;
        _unlockAllProtectedApps =
            savedSettings['unlockAllProtectedApps'] as bool? ?? false;
        _serviceEnabled = serviceEnabled;
        _hasPin = hasPin;
        _settings.backend =
            savedSettings['backend'] as String? ?? 'Usage Statistics';
        _settings.switches['Biometric Authentication'] =
            savedSettings['biometricEnabled'] as bool? ?? false;
        _settings.switches['Haptic Feedback'] =
            savedSettings['hapticEnabled'] as bool? ?? false;
        _settings.switches['Anti-Uninstall Protection'] =
            savedSettings['antiUninstallEnabled'] as bool? ?? false;
        _settings.unlockDuration =
            savedSettings['unlockDuration'] as String? ?? 'Until screen off';
        _loading = false;
        _initialLoadComplete = true;
        _loadError = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadComplete = true;
        _loadError = error.message ?? 'Could not load installed apps.';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadComplete = true;
        _loadError = 'App locking is available on Android only.';
      });
    }
  }

  IconData _iconForPackage(String packageName) {
    if (packageName.contains('whatsapp')) return Icons.chat;
    if (packageName.contains('paytm')) return Icons.account_balance_wallet;
    return Icons.android;
  }

  Color _colorForPackage(String packageName) {
    if (packageName.contains('whatsapp')) return const Color(0xFF25D366);
    if (packageName.contains('paytm')) return const Color(0xFF00B9F1);
    return const Color(0xFF4F7FD0);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          settings: _settings,
          onPinChanged: _savePin,
          onUnlockDurationChanged: (duration) =>
              _appLockChannel.invokeMethod<void>('setUnlockDuration', duration),
          onBooleanSettingChanged: (key, value) =>
              _appLockChannel.invokeMethod<void>('setBooleanSetting', {
                'key': key,
                'value': value,
              }),
          onBackendChanged: _selectBackend,
          onAntiUninstallProtectionChanged: (enabled) async =>
              await _appLockChannel.invokeMethod<bool>(
                'setAntiUninstallProtection',
                enabled,
              ) ??
              false,
          onRefreshAntiUninstallProtection: () async {
            final settings = await _appLockChannel
                .invokeMapMethod<String, Object?>('getSettings');
            return settings?['antiUninstallEnabled'] as bool? ?? false;
          },
        ),
      ),
    );
    await _loadAppData();
  }

  Future<void> _selectBackend(String backend) async {
    try {
      await _appLockChannel.invokeMethod<void>('setBackend', backend);
      if (mounted) setState(() => _settings.backend = backend);
      if (backend == 'Usage Statistics') {
        await _requestUsageStatsPermission();
      }
      await _appLockChannel.invokeMethod<bool>('syncBackend');
      await _loadAppData();
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not change the app-lock backend.');
    }
  }

  Future<void> _requestUsageStatsPermission() async {
    final usageAccessGranted =
        await _appLockChannel.invokeMethod<bool>('isUsageAccessGranted') ??
        false;
    if (!usageAccessGranted) {
      await _appLockChannel.invokeMethod<void>('openUsageAccessSettings');
      return;
    }

    final overlayPermissionGranted =
        await _appLockChannel.invokeMethod<bool>(
          'isOverlayPermissionGranted',
        ) ??
        false;
    if (!overlayPermissionGranted) {
      await _appLockChannel.invokeMethod<void>('openOverlaySettings');
    }
  }

  Future<void> _savePin(String pin) async {
    await _appLockChannel.invokeMethod<void>('setPin', pin);
    if (mounted) {
      setState(() {
        _hasPin = true;
        _isAppUnlocked = true;
      });
    }
  }

  Future<void> _submitAppPin() async {
    if (_isCheckingAppPin || _enteredAppPin.length != 4) return;
    setState(() {
      _isCheckingAppPin = true;
      _appPinError = null;
    });
    try {
      final valid =
          await _appLockChannel.invokeMethod<bool>(
            'validatePin',
            _enteredAppPin,
          ) ??
          false;
      if (!mounted) return;
      if (valid) {
        setState(() {
          _isAppUnlocked = true;
          _enteredAppPin = '';
        });
        return;
      }

      final remaining =
          await _appLockChannel.invokeMethod<int>('getPinLockoutRemaining') ??
          0;
      final seconds = (remaining + 999) ~/ 1000;
      setState(() {
        _enteredAppPin = '';
        _appPinError = remaining > 0
            ? 'Too many incorrect attempts. Try again in $seconds seconds.'
            : 'Incorrect PIN. Try again.';
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _appPinError = error.message ?? 'Could not verify PIN.');
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _appPinError = 'PIN verification is unavailable.');
      }
    } finally {
      if (mounted) setState(() => _isCheckingAppPin = false);
    }
  }

  Future<void> _setAppLockEnabled(bool enabled) async {
    try {
      await _appLockChannel.invokeMethod<void>('setAppLockEnabled', enabled);
      if (mounted) setState(() => _enabled = enabled);
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not change App Lock status.');
    }
  }

  Future<void> _setUnlockAllProtectedApps(bool enabled) async {
    final oldValue = _unlockAllProtectedApps;
    setState(() => _unlockAllProtectedApps = enabled);
    try {
      await _appLockChannel.invokeMethod<void>('setBooleanSetting', {
        'key': 'unlockAllProtectedApps',
        'value': enabled,
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _unlockAllProtectedApps = oldValue);
        _showMessage(
          error.message ?? 'Could not change grouped app unlocking.',
        );
      }
    }
  }

  Future<void> _setProtectedApps(Iterable<LockedApp> apps) async {
    final packages = apps
        .where((app) => app.protected)
        .map((app) => app.packageName)
        .toList();
    await _appLockChannel.invokeMethod<void>('setProtectedApps', packages);
  }

  Future<void> _setProtection(LockedApp app, bool protected) async {
    final oldValue = app.protected;
    setState(() => app.protected = protected);
    try {
      await _setProtectedApps(_apps);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => app.protected = oldValue);
        _showMessage(error.message ?? 'Could not update app protection.');
      }
    }
  }

  Future<void> _enableSelectedBackend() async {
    try {
      switch (_settings.backend) {
        case 'Usage Statistics':
          await _requestUsageStatsPermission();
          return;
        case 'Accessibility Service':
          await _appLockChannel.invokeMethod<void>('openAccessibilitySettings');
          return;
        default:
          _showMessage('This backend is not available yet.');
          return;
      }
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not open the required settings.');
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _appLockChannel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not open Accessibility settings.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSetPin() async {
    final formKey = GlobalKey<FormState>();
    var pin = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set App Lock PIN'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: const InputDecoration(labelText: 'New 4-digit PIN'),
                onChanged: (value) => pin = value,
                validator: (value) => RegExp(r'^\d{4}$').hasMatch(value ?? '')
                    ? null
                    : 'Enter exactly 4 digits',
              ),
              TextFormField(
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
                validator: (value) => value == pin ? null : 'PINs do not match',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                await _savePin(pin);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on PlatformException catch (error) {
                _showMessage(error.message ?? 'Could not save your PIN.');
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddApps() async {
    final available = _apps.where((app) => !app.protected).toList();
    final selected = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          final query = _addSearchQuery;
          final filteredApps = available
              .where((app) => app.name.toLowerCase().contains(query))
              .toList();

          return AlertDialog(
            title: const Text('Add apps'),
            content: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 64).clamp(
                240.0,
                360.0,
              ),
              height: 390,
              child: Column(
                children: [
                  TextField(
                    autofocus: false,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search apps',
                    ),
                    onChanged: (value) => updateDialog(
                      () => _addSearchQuery = value.trim().toLowerCase(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredApps.isEmpty
                        ? const Center(child: Text('No apps found'))
                        : ListView.builder(
                            itemCount: filteredApps.length,
                            itemBuilder: (context, index) {
                              final app = filteredApps[index];
                              return CheckboxListTile(
                                value: selected.contains(app.packageName),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                secondary: AppIcon(app: app),
                                title: Text(app.name),
                                onChanged: (checked) => updateDialog(() {
                                  if (checked ?? false) {
                                    selected.add(app.packageName);
                                  } else {
                                    selected.remove(app.packageName);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  _addSearchQuery = '';
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        final previous = {
                          for (final app in available)
                            app.packageName: app.protected,
                        };
                        setState(() {
                          for (final app in available) {
                            if (selected.contains(app.packageName)) {
                              app.protected = true;
                            }
                          }
                        });
                        try {
                          await _setProtectedApps(_apps);
                          _addSearchQuery = '';
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } on PlatformException catch (error) {
                          if (mounted) {
                            setState(() {
                              for (final app in available) {
                                app.protected = previous[app.packageName]!;
                              }
                            });
                            _showMessage(
                              error.message ?? 'Could not save app selection.',
                            );
                          }
                        }
                      },
                child: Text('Add (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );
    _addSearchQuery = '';
  }

  String _addSearchQuery = '';

  Future<void> _showPinPrompt() async {
    var succeeded = false;
    var enteredPin = '';
    var isSubmitting = false;
    var fieldVersion = 0;
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          Future<void> submitPin() async {
            if (isSubmitting) return;
            isSubmitting = true;
            try {
              final valid =
                  await _appLockChannel.invokeMethod<bool>(
                    'validatePin',
                    enteredPin,
                  ) ??
                  false;
              if (!dialogContext.mounted) return;
              if (valid) {
                succeeded = true;
                Navigator.pop(dialogContext);
                return;
              }

              final remaining =
                  await _appLockChannel.invokeMethod<int>(
                    'getPinLockoutRemaining',
                  ) ??
                  0;
              final seconds = (remaining + 999) ~/ 1000;
              updateDialog(() {
                errorText = remaining > 0
                    ? 'Too many incorrect attempts. Try again in $seconds seconds.'
                    : 'Incorrect PIN. Try again.';
                enteredPin = '';
                fieldVersion++;
              });
            } on PlatformException catch (error) {
              if (dialogContext.mounted) {
                updateDialog(
                  () => errorText = error.message ?? 'Could not verify PIN.',
                );
              }
            } finally {
              isSubmitting = false;
            }
          }

          return AlertDialog(
            title: const Text('Enter password to continue'),
            content: TextField(
              key: ValueKey(fieldVersion),
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'Enter your 4-digit PIN',
                counterText: '',
                errorText: errorText,
              ),
              onChanged: (value) {
                enteredPin = value;
                if (errorText != null) {
                  updateDialog(() => errorText = null);
                }
                if (value.length == 4) submitPin();
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (succeeded && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('App Lock unlocked')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialLoadComplete) {
      return const Scaffold(
        backgroundColor: appLockPageColor,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_hasPin && !_isAppUnlocked) {
      final keySize =
          (MediaQuery.sizeOf(context).width - 64)
              .clamp(0.0, 3 * 76.0)
              .toDouble() /
          3;

      Widget pinKey(String label, String semanticLabel, VoidCallback onTap) {
        final highlighted = label == '⌫' || label == '›';
        return Semantics(
          key: ValueKey('appPinKey_$semanticLabel'),
          button: true,
          label: semanticLabel,
          child: Material(
            color: highlighted
                ? const Color(0xFFDCE4FA)
                : const Color(0xFFFAF8FF),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isCheckingAppPin ? null : onTap,
              child: SizedBox(
                width: keySize,
                height: keySize,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: highlighted
                          ? const Color(0xFF304B80)
                          : const Color(0xFF3B3E4A),
                      fontSize: label.length == 1 ? 32 : 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      void addPinDigit(String digit) {
        if (_isCheckingAppPin || _enteredAppPin.length >= 4) return;
        setState(() {
          _appPinError = null;
          _enteredAppPin += digit;
        });
        if (_enteredAppPin.length == 4) _submitAppPin();
      }

      Widget keypadRow(List<Widget> keys) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final key in keys) ...[
            Padding(padding: const EdgeInsets.all(4), child: key),
          ],
        ],
      );

      return Scaffold(
        backgroundColor: appLockPageColor,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 52,
                left: 24,
                right: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Enter password to continue',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _appPinError ?? '',
                      style: const TextStyle(
                        color: Color(0xFF5E626D),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 145,
                left: 24,
                right: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (index) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        index < _enteredAppPin.length ? '●' : '○',
                        style: const TextStyle(
                          color: Color(0xFF304B80),
                          fontSize: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    keypadRow([
                      for (final digit in ['1', '2', '3'])
                        pinKey(digit, 'Digit $digit', () => addPinDigit(digit)),
                    ]),
                    keypadRow([
                      for (final digit in ['4', '5', '6'])
                        pinKey(digit, 'Digit $digit', () => addPinDigit(digit)),
                    ]),
                    keypadRow([
                      for (final digit in ['7', '8', '9'])
                        pinKey(digit, 'Digit $digit', () => addPinDigit(digit)),
                    ]),
                    keypadRow([
                      pinKey('⌫', 'Delete last digit', () {
                        if (_enteredAppPin.isNotEmpty) {
                          setState(() {
                            _enteredAppPin = _enteredAppPin.substring(
                              0,
                              _enteredAppPin.length - 1,
                            );
                            _appPinError = null;
                          });
                        }
                      }),
                      pinKey('0', 'Digit 0', () => addPinDigit('0')),
                      pinKey('›', 'Submit PIN', _submitAppPin),
                    ]),
                  ],
                ),
              ),
              if (_isCheckingAppPin)
                const Positioned(
                  top: 210,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final visibleApps = _apps
        .where((app) => app.protected != _showUnprotected)
        .toList();
    return Scaffold(
      backgroundColor: appLockPageColor,
      floatingActionButton: _showUnprotected
          ? null
          : FloatingActionButton(
              onPressed: _showAddApps,
              backgroundColor: appLockPaleBlue,
              foregroundColor: const Color(0xFF304B80),
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              tooltip: 'Add apps',
              child: const Icon(Icons.add, size: 32),
            ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TopControls(
                  enabled: _enabled,
                  onEnabledChanged: _setAppLockEnabled,
                  unlockAllProtectedApps: _unlockAllProtectedApps,
                  onUnlockAllProtectedAppsChanged: _setUnlockAllProtectedApps,
                  showUnprotected: _showUnprotected,
                  onToggleUnprotected: () =>
                      setState(() => _showUnprotected = !_showUnprotected),
                  onSettings: _openSettings,
                  onPin: _hasPin ? _showPinPrompt : _showSetPin,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 16, 24, 8),
                  child: Text(
                    _showUnprotected ? 'Excluded Apps' : 'App Lock',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (!_hasPin)
                  ActionBanner(
                    icon: Icons.pin,
                    title: 'Set a PIN before enabling app protection',
                    buttonText: 'Set PIN',
                    onPressed: _showSetPin,
                  )
                else if (!_serviceEnabled)
                  ActionBanner(
                    icon: _settings.backend == 'Usage Statistics'
                        ? Icons.query_stats
                        : Icons.accessibility_new,
                    title: 'Enable App Lock to protect selected apps',
                    buttonText: _settings.backend == 'Usage Statistics'
                        ? 'Grant access'
                        : 'Enable service',
                    onPressed: _enableSelectedBackend,
                  )
                else if (_enabled)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(28, 0, 24, 4),
                    child: Text(
                      'Notification shade and home screen are not locked.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                if (_settings.backend == 'Usage Statistics')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 24, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'To avoid Paytm’s accessibility warning, turn off App Lock under Android Accessibility settings. Usage Stats will keep working.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                        TextButton(
                          onPressed: _openAccessibilitySettings,
                          child: const Text('Open Accessibility settings'),
                        ),
                      ],
                    ),
                  ),
                if (!_enabled)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(28, 0, 24, 4),
                    child: Text(
                      'App Lock is turned off',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _loadError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _loadAppData,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : visibleApps.isEmpty
                      ? Center(
                          child: Text(
                            _showUnprotected
                                ? 'All installed apps are protected'
                                : 'No protected apps yet. Tap + to choose apps.',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            12,
                            24,
                            _showUnprotected ? 24 : 96,
                          ),
                          itemCount: visibleApps.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final app = visibleApps[index];
                            return AppListTile(
                              app: app,
                              onToggle: () =>
                                  _setProtection(app, !app.protected),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
