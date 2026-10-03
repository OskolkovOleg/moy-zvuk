import 'models.dart';

enum CatalogKind { track, artist, album, playlist }

extension CatalogKindLabel on CatalogKind {
  String get label => switch (this) {
    CatalogKind.track => 'Треки',
    CatalogKind.artist => 'Артисты',
    CatalogKind.album => 'Альбомы',
    CatalogKind.playlist => 'Плейлисты',
  };
  String get field => switch (this) {
    CatalogKind.track => 'tracks',
    CatalogKind.artist => 'artists',
    CatalogKind.album => 'releases',
    CatalogKind.playlist => 'playlists',
  };
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.imageUrl,
  });
  final String id, title, subtitle;
  final String? imageUrl;
  final CatalogKind kind;
  factory CatalogItem.fromApi(Map<String, dynamic> j, CatalogKind kind) =>
      CatalogItem(
        id: j['id'].toString(),
        title: j['title'] as String? ?? '',
        kind: kind,
        subtitle: kind == CatalogKind.album
            ? (j['artists'] as List? ?? []).map((a) => a['title']).join(', ')
            : kind == CatalogKind.artist
            ? 'Артист'
            : 'Плейлист',
        imageUrl: artwork(j['image']?['src']),
      );
  factory CatalogItem.playlist(PlaylistInfo p) => CatalogItem(
    id: p.id,
    title: p.title,
    kind: CatalogKind.playlist,
    imageUrl: p.imageUrl,
    subtitle: trackCountLabel(p.trackCount),
  );
}

class CatalogPage {
  const CatalogPage({this.items = const [], this.tracks = const [], this.next});
  final List<CatalogItem> items;
  final List<Track> tracks;
  final String? next;
}

class CatalogDetail {
  const CatalogDetail(
    this.item,
    this.tracks, {
    this.albums = const [],
    this.playlist,
  });
  final CatalogItem item;
  final List<Track> tracks;
  final List<CatalogItem> albums;
  final PlaylistInfo? playlist;
}
