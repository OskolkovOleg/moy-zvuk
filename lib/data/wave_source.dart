import 'catalog_models.dart';
import 'models.dart';

enum WaveKind { personal, favorites, track, artist, album, playlist }

class WaveSource {
  const WaveSource.personal()
    : kind = WaveKind.personal,
      id = '',
      title = 'Мой поток';
  const WaveSource.favorites()
    : kind = WaveKind.favorites,
      id = '',
      title = 'Любимое';
  const WaveSource({required this.kind, required this.id, required this.title});
  final WaveKind kind;
  final String id, title;
  String get queueTitle => switch (kind) {
    WaveKind.personal => 'Мой поток',
    WaveKind.favorites => 'Поток по любимому',
    _ => 'Поток · $title',
  };
  factory WaveSource.fromTrack(Track t) =>
      WaveSource(kind: WaveKind.track, id: t.id, title: t.title);
  factory WaveSource.fromCatalog(CatalogItem item) => WaveSource(
    kind: switch (item.kind) {
      CatalogKind.track => WaveKind.track,
      CatalogKind.artist => WaveKind.artist,
      CatalogKind.album => WaveKind.album,
      CatalogKind.playlist => WaveKind.playlist,
    },
    id: item.id,
    title: item.title,
  );
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'title': title,
  };
  factory WaveSource.fromJson(Map<String, dynamic> j) {
    final kind = WaveKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (kind == null) throw const FormatException('Invalid flow kind');
    if (kind == WaveKind.personal) return const WaveSource.personal();
    if (kind == WaveKind.favorites) return const WaveSource.favorites();
    final id = j['id'], title = j['title'];
    if (id is! String ||
        title is! String ||
        id.trim().isEmpty ||
        title.trim().isEmpty ||
        (kind == WaveKind.playlist && (int.tryParse(id) ?? 0) <= 0)) {
      throw const FormatException('Invalid flow source');
    }
    return WaveSource(kind: kind, id: id, title: title);
  }
}

class RadioPage {
  const RadioPage(this.tracks, {this.cursor = 0});
  final List<Track> tracks;
  final int cursor;
}
