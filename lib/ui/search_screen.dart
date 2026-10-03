import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/search_history_store.dart';
import '../search_controller.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen(this.app, {super.key});
  final AppController app;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final input = TextEditingController();
  late final search = MusicSearchController(
    widget.app.api,
    SearchHistoryStore(widget.app.store),
    widget.app.account!.id,
  );

  @override
  void initState() {
    super.initState();
    unawaited(search.initialize());
  }

  @override
  void dispose() {
    search.dispose();
    input.dispose();
    super.dispose();
  }

  void submit([String? text]) {
    if (text != null) {
      input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    FocusScope.of(context).unfocus();
    unawaited(search.submit(input.text));
  }

  Widget history() => Column(
    children: [
      if (search.historyError.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(search.historyError),
        ),
      if (search.recent.isEmpty)
        const EmptyState(
          icon: Icons.search_rounded,
          title: 'Найди своё',
          message:
              'Начни вводить название песни, артиста, альбома или плейлиста.',
        )
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Недавние запросы',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: search.clearRecent,
                child: const Text('Очистить'),
              ),
            ],
          ),
        ),
        for (final value in search.recent)
          ListTile(
            key: ValueKey('recent:$value'),
            contentPadding: const EdgeInsets.only(left: 20, right: 8),
            leading: const Icon(Icons.history_rounded),
            title: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Удалить запрос «$value»',
              onPressed: () => search.removeRecent(value),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
            onTap: () => submit(value),
          ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: search,
    builder: (context, _) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            controller: input,
            onChanged: search.edit,
            onSubmitted: (_) => submit(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Что хочешь послушать?',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Очистить поиск',
                      onPressed: () {
                        input.clear();
                        search.edit('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              for (final value in <CatalogKind?>[null, ...CatalogKind.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(value?.label ?? 'Всё'),
                    selected: search.kind == value,
                    showCheckmark: false,
                    onSelected: (_) => search.choose(value),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: search.busy ? const LinearProgressIndicator() : null,
        ),
        Expanded(
          child: CustomScrollView(
            key: ValueKey('${search.query}:${search.kind}'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              if (search.query.isEmpty)
                SliverToBoxAdapter(child: history())
              else ...[
                if (search.error.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CatalogFailure(search.error, search.retry),
                  ),
                if (search.hits.isEmpty && search.error.isEmpty)
                  SliverToBoxAdapter(
                    child: EmptyState(
                      icon: Icons.search_rounded,
                      title: search.busy
                          ? 'Ищем музыку…'
                          : search.searched
                          ? 'Ничего не нашлось'
                          : 'Продолжай вводить',
                      message: search.searched
                          ? 'Попробуй другое название или категорию.'
                          : 'Поиск начнётся после двух символов.',
                    ),
                  ),
                if (search.hits.isNotEmpty && search.kind == null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        'Быстрый поиск',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                SliverList.builder(
                  itemCount: search.hits.length,
                  itemBuilder: (context, index) {
                    final hit = search.hits[index];
                    if (hit.item != null) {
                      return CatalogTile(
                        hit.item!,
                        compact: true,
                        key: ValueKey(hit.key),
                        onTap: () {
                          unawaited(search.remember());
                          FocusScope.of(context).unfocus();
                          openCatalog(context, widget.app, hit.item!);
                        },
                      );
                    }
                    return TrackTile(
                      key: ValueKey(hit.key),
                      track: hit.track!,
                      app: widget.app,
                      catalog: true,
                      onPlay: () {
                        unawaited(search.remember());
                        FocusScope.of(context).unfocus();
                        final tracks = search.hits
                            .where((h) => h.track != null)
                            .map((h) => h.track!)
                            .toList();
                        unawaited(
                          widget.app.music.playList(
                            tracks,
                            tracks.indexWhere((t) => t.id == hit.track!.id),
                            title: 'Поиск: ${search.query}',
                          ),
                        );
                      },
                    );
                  },
                ),
                if (search.next != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: OutlinedButton(
                        onPressed: search.busy ? null : search.loadMore,
                        child: const Text('Показать ещё'),
                      ),
                    ),
                  ),
                if (search.hits.isNotEmpty && search.kind == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Больше результатов — в категориях сверху.'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
