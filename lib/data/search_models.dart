import 'catalog_models.dart';
import 'models.dart';

/// One quick-search hit, preserving the service's mixed relevance order.
class SearchHit {
  const SearchHit.track(Track value) : track = value, item = null;
  const SearchHit.item(CatalogItem value) : item = value, track = null;
  final Track? track;
  final CatalogItem? item;
  String get key =>
      track != null ? 'track:${track!.id}' : '${item!.kind.name}:${item!.id}';
}
