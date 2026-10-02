import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen(this.app, {super.key});
  final AppController app;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final input = TextEditingController();
  List<Track> tracks = [];
  String query = '', error = '';
  String? next;
  bool busy = false, searched = false;
  int request = 0;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> search({bool more = false}) async {
    final text = more ? query : input.text.trim();
    if (text.isEmpty || widget.app.api == null) return;
    final current = ++request;
    setState(() {
      busy = true;
      error = '';
      if (!more) {
        query = text;
        tracks = [];
        next = null;
      }
    });
    try {
      final result = await widget.app.api!.search(
        text,
        cursor: more ? next : null,
      );
      if (!mounted || current != request) return;
      setState(() {
        tracks = more ? [...tracks, ...result.tracks] : result.tracks;
        next = result.next;
        searched = true;
      });
    } catch (e) {
      if (mounted && current == request) {
        setState(
          () => error = e is ZvukException
              ? e.message
              : 'Поиск недоступен. Попробуй снова.',
        );
      }
    } finally {
      if (mounted && current == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: TextField(
          controller: input,
          onSubmitted: (_) => search(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Песня или исполнитель',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Найти',
              onPressed: busy ? null : () => search(),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2),
      if (error.isNotEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text(error)),
      Expanded(
        child: tracks.isEmpty
            ? EmptyState(
                icon: Icons.search_rounded,
                title: searched
                    ? 'Ничего не нашлось'
                    : 'Найди свой следующий трек',
                message: 'Запусти песню сразу или добавь её в очередь через меню рядом с названием.',
              )
            : ListView.builder(
                itemCount: tracks.length + (next == null ? 0 : 1),
                itemBuilder: (_, index) => index == tracks.length
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: OutlinedButton(
                          onPressed: busy ? null : () => search(more: true),
                          child: const Text('Ещё треки'),
                        ),
                      )
                    : TrackTile(
                        track: tracks[index],
                        app: widget.app,
                        onPlay: () => widget.app.music.playList(
                          tracks,
                          index,
                          title: 'Поиск: $query',
                        ),
                      ),
              ),
      ),
    ],
  );
}
