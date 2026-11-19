import 'package:flutter/material.dart';

class LockedApp {
  LockedApp(
    this.name,
    this.packageName,
    this.icon,
    this.color, {
    this.protected = false,
  });

  final String name;
  final String packageName;
  final IconData icon;
  final Color color;
  bool protected;
}

class AppSettings {
  final Map<String, bool> switches = {
    'Maximum Brightness': false,
    'Biometric Authentication': false,
    'Haptic Feedback': false,
    'Auto Unlock': true,
    'Anti-Uninstall Protection': false,
    'Logging': false,
  };

  String unlockDuration = 'Until screen off';
  String backend = 'Usage Statistics';
}
