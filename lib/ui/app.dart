import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'player_sheet.dart';
import 'theme.dart';
import 'discover_screen.dart';
import 'playlists_screen.dart';
import 'catalog_widgets.dart';

class ZvukApp extends StatefulWidget {
  const ZvukApp(this.app, {super.key});
  final AppController app;
  @override
  State<ZvukApp> createState() => _ZvukAppState();
}

class _ZvukAppState extends State<ZvukApp> with WidgetsBindingObserver {
  int tab = 0, libraryRequests = 0;
  final visited = <int>{0};
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(widget.app.music.savePosition());
    }
  }

  void settings(BuildContext context) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PlayerScaffold(
        widget.app,
        title: 'Настройки',
        body: SettingsScreen(widget.app),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Мой Звук',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: AnimatedBuilder(
      animation: widget.app,
      builder: (context, _) {
        final app = widget.app;
        if (libraryRequests != app.libraryRequests) {
          libraryRequests = app.libraryRequests;
          tab = 0;
        }
        if (app.account == null) return Scaffold(body: WelcomeScreen(app));
        return Scaffold(
          appBar: tab == 0
              ? null
              : AppBar(
                  title: Text(['Мой Звук', 'Обзор', 'Поиск', 'Плейлисты'][tab]),
                  actions: [
                    IconButton(
                      tooltip: 'Настройки',
                      onPressed: () => settings(context),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
          body: SafeArea(
            top: tab == 0,
            bottom: false,
            child: Column(
              children: [
                if (app.message != null)
                  Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.message!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Открыть подключение',
                          onPressed: () => settings(context),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: tab,
                    children: [
                      LibraryScreen(app, onSettings: () => settings(context)),
                      visited.contains(1)
                          ? DiscoverScreen(
                              app,
                              key: ValueKey(
                                'discover:${app.account!.id}:${app.api.hashCode}',
                              ),
                            )
                          : const SizedBox.shrink(),
                      SearchScreen(
                        app,
                        key: ValueKey('search:${app.account!.id}'),
                      ),
                      PlaylistsScreen(app),
                    ],
                  ),
                ),
                MiniPlayer(app),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() {
              tab = value;
              visited.add(value);
            }),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Библиотека',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore_rounded),
                label: 'Обзор',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Поиск',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_rounded),
                label: 'Плейлисты',
              ),
            ],
          ),
        );
      },
    ),
  );
}
