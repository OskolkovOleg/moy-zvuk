import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/discovery_models.dart';
import '../data/models.dart';
import 'discovery_screen.dart';

Future<void> openDiscoveries(
  BuildContext context,
  AppController app,
  DiscoveryMode mode, {
  Track? seed,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => DiscoveryScreen(app, mode, seed: seed)),
);

IconData discoveryIcon(DiscoveryMode mode) => switch (mode) {
  DiscoveryMode.best => Icons.auto_awesome_rounded,
  DiscoveryMode.song => Icons.sensors_rounded,
  DiscoveryMode.releases => Icons.fiber_new_outlined,
  DiscoveryMode.explore => Icons.explore_outlined,
};

class DiscoveryEntries extends StatelessWidget {
  const DiscoveryEntries(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Открытия', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Найти музыку, которую захочется оставить',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final mode in DiscoveryMode.values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Icon(discoveryIcon(mode)),
                  title: Text(
                    mode.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(mode.description),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () => openDiscoveries(context, app, mode),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
