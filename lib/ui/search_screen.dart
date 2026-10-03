import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/zvuk_api.dart';
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
  CatalogPage page = const CatalogPage();
  CatalogKind kind = CatalogKind.track;
  String query = '', error = '';
  bool busy = false, searched = false;
  int request = 0;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> search({bool more = false}) async {
    final text = more ? query : input.text.trim(), api = widget.app.api;
    if (text.isEmpty) return;
    if (api == null) {
      setState(() => error = 'Обнови подключение в настройках.');
      return;
    }
    final current = ++request;
    setState(() {
      busy = true;
      error = '';
      if (!more) {
        query = text;
        page = const CatalogPage();
      }
    });
    try {
      final result = await api.searchCatalog(
        text,
        kind,
        cursor: more ? page.next : null,
      );
      if (!mounted || current != request || api != widget.app.api) return;
      setState(() {
        page = more
            ? CatalogPage(
                items: [...page.items, ...result.items],
                tracks: [...page.tracks, ...result.tracks],
                next: result.next,
              )
            : result;
        searched = true;
      });
    } catch (e) {
      if (mounted && current == request) {
        setState(() => error = catalogError(e));
      }
    } finally {
      if (mounted && current == request) setState(() => busy = false);
    }
  }

  void choose(CatalogKind value) {
    if (value == kind) return;
    setState(() {
      request++;
      kind = value;
      page = const CatalogPage();
      error = '';
      searched = false;
      busy = false;
    });
    search();
  }

  @override
  Widget build(BuildContext context) {
    final count = page.tracks.length + page.items.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            controller: input,
            onSubmitted: (_) => search(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Что хочешь послушать?',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Найти',
                onPressed: () => search(),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              for (final value in CatalogKind.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(value.label),
                    selected: kind == value,
                    showCheckmark: false,
                    onSelected: (_) => choose(value),
                  ),
                ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (error.isNotEmpty)
          CatalogFailure(error, () => search(more: count > 0)),
        Expanded(
          child: count == 0
              ? SingleChildScrollView(
                  child: EmptyState(
                    icon: Icons.search_rounded,
                    title: busy
                        ? 'Ищем музыку…'
                        : searched
                        ? 'Ничего не нашлось'
                        : 'Найди своё',
                    message: searched
                        ? 'Попробуй другое название или категорию.'
                        : 'Песни, артисты, альбомы и плейлисты Звука.',
                  ),
                )
              : ListView.builder(
                  itemCount: count + (page.next == null ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index == count) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: OutlinedButton(
                          onPressed: busy ? null : () => search(more: true),
                          child: const Text('Показать ещё'),
                        ),
                      );
                    }
                    if (kind != CatalogKind.track) {
                      return CatalogTile(
                        page.items[index],
                        onTap: () =>
                            openCatalog(context, widget.app, page.items[index]),
                      );
                    }
                    return TrackTile(
                      track: page.tracks[index],
                      app: widget.app,
                      catalog: true,
                      onPlay: () => widget.app.music.playList(
                        page.tracks,
                        index,
                        title: 'Поиск: $query',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
