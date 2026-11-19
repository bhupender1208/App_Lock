import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_lock_models.dart';
import '../theme/app_lock_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onPinChanged,
    required this.onUnlockDurationChanged,
    required this.onBooleanSettingChanged,
    required this.onBackendChanged,
    required this.onAntiUninstallProtectionChanged,
    required this.onRefreshAntiUninstallProtection,
  });

  final AppSettings settings;
  final Future<void> Function(String) onPinChanged;
  final Future<void> Function(String) onUnlockDurationChanged;
  final Future<void> Function(String, bool) onBooleanSettingChanged;
  final Future<void> Function(String) onBackendChanged;
  final Future<bool> Function(bool) onAntiUninstallProtectionChanged;
  final Future<bool> Function() onRefreshAntiUninstallProtection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAntiUninstallProtection();
    }
  }

  Future<void> _refreshAntiUninstallProtection() async {
    try {
      final enabled = await widget.onRefreshAntiUninstallProtection();
      if (mounted) {
        setState(
          () => widget.settings.switches['Anti-Uninstall Protection'] = enabled,
        );
      }
    } on PlatformException catch (error) {
      _message(error.message ?? 'Could not check uninstall protection.');
    }
  }

  Future<void> _setAntiUninstallProtection(bool enabled) async {
    try {
      final isActive = await widget.onAntiUninstallProtectionChanged(enabled);
      if (mounted) {
        setState(
          () =>
              widget.settings.switches['Anti-Uninstall Protection'] = isActive,
        );
      }
    } on PlatformException catch (error) {
      _message(error.message ?? 'Could not change uninstall protection.');
    }
  }

  Future<void> _setPersistentSwitch(
    String title,
    String settingKey,
    bool value,
  ) async {
    final oldValue = widget.settings.switches[title]!;
    setState(() => widget.settings.switches[title] = value);
    try {
      await widget.onBooleanSettingChanged(settingKey, value);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => widget.settings.switches[title] = oldValue);
        _message(error.message ?? 'Could not save $title.');
      }
    }
  }

  Future<void> _changePin() async {
    final formKey = GlobalKey<FormState>();
    var pin = '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change PIN'),
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                try {
                  await widget.onPinChanged(pin);
                  if (context.mounted) Navigator.pop(context);
                  _message('PIN updated');
                } on PlatformException catch (error) {
                  _message(error.message ?? 'Could not save your PIN.');
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseUnlockDuration() async {
    const options = [
      'Until screen off',
      'Immediately',
      'After 1 minute',
      'After 5 minutes',
      'After 10 minutes',
      'After 15 minutes',
      'After 30 minutes',
      'After 1 hour',
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Unlock Time Duration'),
        children: [
          RadioGroup<String>(
            groupValue: widget.settings.unlockDuration,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options
                  .map(
                    (option) => RadioListTile<String>(
                      value: option,
                      title: Text(option),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      setState(() => widget.settings.unlockDuration = selected);
      try {
        await widget.onUnlockDurationChanged(selected);
      } on PlatformException catch (error) {
        _message(error.message ?? 'Could not save unlock duration.');
      }
    }
  }

  Future<void> _chooseBackend() async {
    const options = [
      'Accessibility Service',
      'Usage Statistics',
      'Shizuku Service',
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Backend Implementation'),
        children: [
          RadioGroup<String>(
            groupValue: widget.settings.backend,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options
                  .map(
                    (option) => RadioListTile<String>(
                      value: option,
                      title: Text(option),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      try {
        await widget.onBackendChanged(selected);
        if (mounted) setState(() => widget.settings.backend = selected);
      } on PlatformException catch (error) {
        _message(error.message ?? 'Could not change the app-lock backend.');
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F9FB),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: appLockInk,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 10),
                child: Text(
                  'Version 2.5.1',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ),
              DonateTile(
                onTap: () => _message('Thank you for supporting App Lock'),
              ),
              const SizedBox(height: 12),
              SettingsSection(
                title: 'Lock Screen Customization',
                children: [
                  SettingsSwitch(
                    title: 'Maximum Brightness',
                    subtitle: 'Display lock screen at maximum brightness',
                    icon: Icons.brightness_6,
                    value: widget.settings.switches['Maximum Brightness']!,
                    onChanged: (value) => setState(
                      () => widget.settings.switches['Maximum Brightness'] =
                          value,
                    ),
                  ),
                  SettingsSwitch(
                    title: 'Biometric Authentication',
                    subtitle: 'Use fingerprint or face unlock to unlock apps',
                    icon: Icons.fingerprint,
                    value:
                        widget.settings.switches['Biometric Authentication']!,
                    onChanged: (value) => _setPersistentSwitch(
                      'Biometric Authentication',
                      'biometricEnabled',
                      value,
                    ),
                  ),
                  SettingsSwitch(
                    title: 'Haptic Feedback',
                    subtitle: 'Vibrate when keypad buttons are pressed',
                    icon: Icons.vibration,
                    value: widget.settings.switches['Haptic Feedback']!,
                    onChanged: (value) => _setPersistentSwitch(
                      'Haptic Feedback',
                      'hapticEnabled',
                      value,
                    ),
                  ),
                  SettingsSwitch(
                    title: 'Auto Unlock',
                    subtitle: 'Unlock app as soon as correct PIN is entered',
                    icon: Icons.shield,
                    value: widget.settings.switches['Auto Unlock']!,
                    onChanged: (value) => setState(
                      () => widget.settings.switches['Auto Unlock'] = value,
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: 'Security',
                children: [
                  SettingsNavigationTile(
                    title: 'Change PIN',
                    subtitle: 'Update your current PIN',
                    icon: Icons.lock,
                    onTap: _changePin,
                  ),
                  SettingsNavigationTile(
                    title: 'Unlock Time Duration',
                    subtitle: widget.settings.unlockDuration,
                    icon: Icons.timer_outlined,
                    onTap: _chooseUnlockDuration,
                  ),
                  SettingsSwitch(
                    title: 'Anti-Uninstall Protection',
                    subtitle:
                        'Requires Android device-admin approval; can be turned off in settings',
                    icon: Icons.lock,
                    value:
                        widget.settings.switches['Anti-Uninstall Protection']!,
                    onChanged: _setAntiUninstallProtection,
                  ),
                ],
              ),
              SettingsSection(
                title: 'Backend Implementation',
                children: [
                  SettingsChoiceTile(
                    title: 'Accessibility Service',
                    subtitle: 'Standard method that works on most devices',
                    icon: Icons.accessibility_new,
                    selected:
                        widget.settings.backend == 'Accessibility Service',
                    onTap: _chooseBackend,
                  ),
                  SettingsChoiceTile(
                    title: 'Usage Statistics',
                    subtitle:
                        'Requires Usage Access and Display over other apps',
                    icon: Icons.query_stats,
                    selected: widget.settings.backend == 'Usage Statistics',
                    onTap: _chooseBackend,
                  ),
                  SettingsChoiceTile(
                    title: 'Shizuku Service',
                    subtitle: 'Advanced method using Shizuku and internal APIs',
                    icon: Icons.auto_awesome,
                    selected: widget.settings.backend == 'Shizuku Service',
                    badge: 'Advanced',
                    onTap: _chooseBackend,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DonateTile extends StatelessWidget {
  const DonateTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: appLockPaleBlue,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFB7CCFF),
                child: Icon(Icons.favorite, color: appLockBlue, size: 18),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Donate',
                      style: TextStyle(
                        color: Color(0xFF304B80),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Keep AppLock free and ad-free forever',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Color(0xFF304B80)),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              title,
              style: const TextStyle(
                color: appLockBlue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: appLockPageColor,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: appLockTileColor,
      child: SizedBox(
        height: 57,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(icon, size: 17, color: const Color(0xFF626672)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: appLockInk,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: appLockInk),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: appLockBlue,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class SettingsNavigationTile extends StatelessWidget {
  const SettingsNavigationTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: appLockTileColor,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: subtitle == null ? 48 : 57,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(icon, size: 17, color: const Color(0xFF626672)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: appLockInk,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: appLockInk),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: appLockInk, size: 20),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsChoiceTile extends StatelessWidget {
  const SettingsChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: appLockTileColor,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(icon, size: 17, color: const Color(0xFF626672)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: appLockInk,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A76B7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: appLockInk),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? appLockBlue : const Color(0xFF626672),
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
