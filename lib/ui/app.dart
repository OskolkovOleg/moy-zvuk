import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'player_sheet.dart';
import 'theme.dart';

class ZvukApp extends StatefulWidget {
  const ZvukApp(this.app, {super.key});
  final AppController app;
  @override
  State<ZvukApp> createState() => _ZvukAppState();
}

class _ZvukAppState extends State<ZvukApp> with WidgetsBindingObserver {
  int tab = 0;
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

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Мой Звук',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: AnimatedBuilder(
      animation: widget.app,
      builder: (context, _) {
        final app = widget.app;
        if (app.account == null) return Scaffold(body: WelcomeScreen(app));
        return Scaffold(
          appBar: tab == 0
              ? null
              : AppBar(
                  title: Text(['Мой Звук', 'Поиск', 'Настройки'][tab]),
                  actions: [
                    if (tab == 0)
                      IconButton(
                        tooltip: 'Обновить библиотеку',
                        onPressed: app.busy ? null : app.refresh,
                        icon: const Icon(Icons.refresh_rounded),
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
                          onPressed: () => setState(() => tab = 2),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: tab,
                    children: [
                      LibraryScreen(app),
                      SearchScreen(
                        app,
                        key: ValueKey('search:${app.account!.id}'),
                      ),
                      SettingsScreen(app),
                    ],
                  ),
                ),
                MiniPlayer(app),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Библиотека',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded),
                label: 'Поиск',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                label: 'Настройки',
              ),
            ],
          ),
        );
      },
    ),
  );
}
