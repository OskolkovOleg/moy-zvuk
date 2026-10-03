import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';

class SavedCatalogScreen extends StatefulWidget {
  const SavedCatalogScreen(this.app, this.kind, {super.key});
  final AppController app;
  final CatalogKind kind;
  @override
  State<SavedCatalogScreen> createState() => _SavedCatalogScreenState();
}

class _SavedCatalogScreenState extends State<SavedCatalogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.app.refreshSavedCatalog();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final app = widget.app;
      final items = app.savedCatalogItems
          .where((i) => i.kind == widget.kind)
          .toList();
      return PlayerScaffold(
        app,
        title: widget.kind.label,
        body: RefreshIndicator(
          onRefresh: app.refreshSavedCatalog,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  'Сохранено в Звуке',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (app.savedCatalogLoading)
                const LinearProgressIndicator(minHeight: 2),
              if (app.savedCatalogError != null)
                CatalogFailure(app.savedCatalogError!, app.refreshSavedCatalog),
              if (items.isEmpty &&
                  !app.savedCatalogLoading &&
                  app.savedCatalogError == null)
                const EmptyState(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Пока пусто',
                  message: 'Находи музыку в поиске и сохраняй на странице альбома или артиста.',
                ),
              for (final item in items)
                CatalogTile(item, onTap: () => openCatalog(context, app, item)),
            ],
          ),
        ),
      );
    },
  );
}
