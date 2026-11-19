import 'package:flutter/material.dart';

import '../models/app_lock_models.dart';
import '../theme/app_lock_theme.dart';

class TopControls extends StatelessWidget {
  const TopControls({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.unlockAllProtectedApps,
    required this.onUnlockAllProtectedAppsChanged,
    required this.showUnprotected,
    required this.onToggleUnprotected,
    required this.onSettings,
    required this.onPin,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool unlockAllProtectedApps;
  final ValueChanged<bool> onUnlockAllProtectedAppsChanged;
  final bool showUnprotected;
  final VoidCallback onToggleUnprotected;
  final VoidCallback onSettings;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Semantics(
            button: true,
            label: enabled ? 'App Lock on' : 'App Lock off',
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => onEnabledChanged(!enabled),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: enabled ? appLockPaleBlue : appLockTileColor,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield,
                      color: enabled ? const Color(0xFF304B80) : Colors.grey,
                      size: 21,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      enabled ? 'ON' : 'OFF',
                      style: const TextStyle(
                        color: Color(0xFF304B80),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: unlockAllProtectedApps
                ? 'Unlock all protected apps together'
                : 'Unlock protected apps individually',
            onPressed: () =>
                onUnlockAllProtectedAppsChanged(!unlockAllProtectedApps),
            icon: Icon(
              unlockAllProtectedApps ? Icons.link : Icons.link_off,
              color: unlockAllProtectedApps
                  ? const Color(0xFF304B80)
                  : Colors.black,
              size: 25,
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            icon: const Icon(Icons.settings, color: Colors.black, size: 26),
          ),
          IconButton(
            tooltip: showUnprotected ? 'Show protected apps' : 'Excluded apps',
            onPressed: onToggleUnprotected,
            icon: Icon(
              showUnprotected ? Icons.lock_outline : Icons.block,
              color: Colors.black,
              size: 25,
            ),
          ),
          IconButton(
            tooltip: 'Unlock with PIN',
            onPressed: onPin,
            icon: const Icon(Icons.lock_outline, color: Colors.black, size: 25),
          ),
        ],
      ),
    );
  }
}

class ActionBanner extends StatelessWidget {
  const ActionBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.buttonText,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: appLockPaleBlue,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF304B80), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 12, color: appLockInk),
              ),
            ),
            TextButton(onPressed: onPressed, child: Text(buttonText)),
          ],
        ),
      ),
    );
  }
}

class AppListTile extends StatelessWidget {
  const AppListTile({super.key, required this.app, required this.onToggle});

  final LockedApp app;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${app.name}, ${app.protected ? 'Protected' : 'Not protected'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggle,
        child: SizedBox(
          height: 78,
          child: Row(
            children: [
              AppIcon(app: app, size: 50),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.protected ? 'Protected' : 'Not protected',
                      style: TextStyle(
                        color: app.protected ? appLockBlue : Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: app.protected ? 'Remove protection' : 'Protect app',
                onPressed: onToggle,
                icon: Icon(
                  app.protected ? Icons.lock_outline : Icons.lock_open,
                  color: Colors.black,
                  size: 27,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.app, this.size = 42});

  final LockedApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFD0D0D3),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.72,
        height: size * 0.72,
        decoration: BoxDecoration(
          color: app.color,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        child: Icon(app.icon, color: Colors.white, size: size * 0.43),
      ),
    );
  }
}
