part of 'zvuk_api.dart';

extension ZvukCatalog on ZvukApi {
  Future<List<PlaylistInfo>> getPlaylists(List<String> ids) async {
    final found = <String, PlaylistInfo>{};
    for (var start = 0; start < ids.length; start += 50) {
      final data = await _graph(
        'getPlaylists',
        r'query getPlaylists($ids: [ID!]!) { getPlaylists(ids: $ids) { id title userId isPublic description image { src } tracks { id } } }',
        {'ids': ids.sublist(start, (start + 50).clamp(0, ids.length))},
      );
      for (final j
          in (data['getPlaylists'] as List? ?? [])
              .whereType<Map<String, dynamic>>()) {
        final p = PlaylistInfo.fromJson(j);
        found[p.id] = p;
      }
    }
    return ids.where(found.containsKey).map((id) => found[id]!).toList();
  }

  Future<CatalogPage> searchCatalog(
    String query,
    CatalogKind kind, {
    String? cursor,
  }) async {
    final fields = switch (kind) {
      CatalogKind.track => ZvukApi._fields,
      CatalogKind.album => 'id title image { src } artists { id title }',
      _ => 'id title image { src }',
    };
    final data = await _graph(
      'catalogSearch',
      'query catalogSearch(\$query: String, \$cursor: Cursor) { search(query: \$query) { ${kind.field}(limit: 30, cursor: \$cursor) { page { next cursor } items { $fields } } } }',
      {'query': query, 'cursor': cursor},
    );
    final result = data['search'][kind.field];
    final items = (result['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final next = items.isEmpty || result['page']?['next'] == null
        ? null
        : result['page']?['cursor']?.toString();
    return kind == CatalogKind.track
        ? CatalogPage(
            tracks: items.map((j) => Track.fromApi(j)).toList(),
            next: next,
          )
        : CatalogPage(
            items: items.map((j) => CatalogItem.fromApi(j, kind)).toList(),
            next: next,
          );
  }

  Future<CatalogDetail> catalogDetail(CatalogItem item) async {
    if (item.kind == CatalogKind.playlist) {
      final lists = await getPlaylists([item.id]);
      if (lists.isEmpty) {
        throw const ZvukException('Плейлист больше недоступен.');
      }
      return CatalogDetail(
        CatalogItem.playlist(lists.single),
        await playlistTracks(item.id),
        playlist: lists.single,
      );
    }
    final artist = item.kind == CatalogKind.artist;
    final field = artist ? 'getArtists' : 'getReleases';
    final nested = artist
        ? 'popularTracks(offset: 0, limit: 100) { ${ZvukApi._fields} } releases(offset: 0, limit: 100) { id title image { src } artists { id title } }'
        : 'artists { id title } tracks { ${ZvukApi._fields} }';
    final data = await _graph(
      'catalogDetail',
      'query catalogDetail(\$ids: [ID!]!) { $field(ids: \$ids) { id title image { src } $nested } }',
      {
        'ids': [item.id],
      },
    );
    final items = (data[field] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (items.isEmpty) {
      throw const ZvukException('Эта музыка сейчас недоступна.');
    }
    final j = items.first;
    return CatalogDetail(
      CatalogItem.fromApi(j, item.kind),
      (j[artist ? 'popularTracks' : 'tracks'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((t) => Track.fromApi(t))
          .toList(),
      albums: (j['releases'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((a) => CatalogItem.fromApi(a, CatalogKind.album))
          .toList(),
    );
  }

  Future<List<Track>> personalWave({
    int count = 15,
    Map<String, dynamic>? waveInput,
    WaveOptions options = const WaveOptions(),
  }) async {
    final data = await _graph(
      'getPersonalWave',
      'query getPersonalWave(\$first: PositiveInt!, \$waveInput: WaveInput, \$options: PersonalWaveOptions) { personalWaveContent(first: \$first, waveInput: \$waveInput, options: \$options) { ${ZvukApi._fields} } }',
      {
        'first': count,
        'waveInput': ?waveInput,
        if (!options.isDefault) 'options': options.toApi(),
      },
    );
    return (data['personalWaveContent'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((j) => Track.fromApi(j))
        .toList();
  }

  Future<List<PlaylistInfo>> chartPlaylists() =>
      getPlaylists(['1062105', '6477975', '6477976']);
  Future<List<PlaylistInfo>> personalPlaylists() =>
      getPlaylists(['6', '3', '4', '9']);
  Future<List<PlaylistInfo>> editorialPlaylists() async {
    final data = await _request(
      '/api/tiny/grid/content',
      params: {'name': 'editorial_playlist', 'ranker_enabled': 'true'},
    );
    final result = data['result'] ?? data;
    final items = result['page']?['data'] as List? ?? [];
    return getPlaylists(
      items
          .where((j) => j['type'] == 'playlist')
          .map((j) => j['id'].toString())
          .toList(),
    );
  }

  List<Map<String, String>> _playlistItems(List<String> ids) =>
      ids.map((id) => {'type': 'track', 'item_id': id}).toList();
  void _checkMutation(dynamic object, String field) {
    // Zvuk's void mutations return an explicitly present null on success.
    // GraphQL errors are already rejected by _request; missing/false is failure.
    if (object is! Map ||
        !object.containsKey(field) ||
        object[field] == false) {
      throw const ZvukException(
        'Изменение не сохранилось в Звуке. Попробуй снова.',
      );
    }
  }

  Future<String> createPlaylist(
    String name, {
    List<String> trackIds = const [],
  }) async {
    final data = await _graph(
      'createPlayList',
      r'mutation createPlayList($items: [PlaylistItem!]!, $name: String!) { playlist { create(items: $items, name: $name) } }',
      {'name': name, 'items': <Map<String, String>>[]},
    );
    final id = data['playlist']?['create'];
    if (id == null || id == false || id.toString().isEmpty) {
      throw const ZvukException('Плейлист не создался. Попробуй снова.');
    }
    final created = id.toString();
    try {
      final privacy = await _graph(
        'setPlaylistToPublic',
        r'mutation setPlaylistToPublic($id: ID!, $isPublic: Boolean!) { playlist { setPublic(id: $id, isPublic: $isPublic) } }',
        {'id': created, 'isPublic': false},
      );
      _checkMutation(privacy['playlist'], 'setPublic');
      if (trackIds.isNotEmpty) await addPlaylistTracks(created, trackIds);
    } catch (_) {
      // Only the playlist created in this call may be rolled back.
      try {
        await deletePlaylist(created);
      } catch (_) {
        throw const ZvukException(
          'Плейлист создан, но закрыть его не удалось. Проверь его видимость в Звуке перед добавлением песен.',
        );
      }
      throw const ZvukException(
        'Не удалось создать приватный плейлист. Попробуй снова.',
      );
    }
    return created;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final data = await _graph(
      'renamePlaylist',
      r'mutation renamePlaylist($id: ID!, $name: String!) { playlist { rename(id: $id, name: $name) } }',
      {'id': id, 'name': name},
    );
    _checkMutation(data['playlist'], 'rename');
  }

  Future<void> deletePlaylist(String id) async {
    final data = await _graph(
      'deletePlaylist',
      r'mutation deletePlaylist($id: ID!) { playlist { delete(id: $id) } }',
      {'id': id},
    );
    _checkMutation(data['playlist'], 'delete');
  }

  Future<void> addPlaylistTracks(String id, List<String> tracks) async {
    final data = await _graph(
      'addTracksToPlaylist',
      r'mutation addTracksToPlaylist($id: ID!, $items: [PlaylistItem!]!) { playlist { addItems(id: $id, items: $items) } }',
      {'id': id, 'items': _playlistItems(tracks)},
    );
    _checkMutation(data['playlist'], 'addItems');
  }

  Future<void> replacePlaylistTracks(
    PlaylistInfo playlist,
    List<String> tracks,
  ) async {
    final data = await _graph(
      'updataPlaylist',
      r'mutation updataPlaylist($id: ID!, $items: [PlaylistItem!]!, $isPublic: Boolean!, $name: String!) { playlist { update(id: $id, items: $items, isPublic: $isPublic, name: $name) } }',
      {
        'id': playlist.id,
        'name': playlist.title,
        'isPublic': playlist.isPublic,
        'items': _playlistItems(tracks),
      },
    );
    _checkMutation(data['playlist'], 'update');
  }

  Future<void> setCollectionItem(
    String id, {
    required bool liked,
    bool playlist = false,
    CatalogKind kind = CatalogKind.track,
  }) async {
    final action = liked ? 'addItem' : 'removeItem';
    final data = await _graph(
      'changeCollection',
      'mutation changeCollection(\$id: ID, \$type: CollectionItemType) { collection { $action(id: \$id, type: \$type) } }',
      {
        'id': id,
        'type': playlist
            ? 'playlist'
            : switch (kind) {
                CatalogKind.album => 'release',
                _ => kind.name,
              },
      },
    );
    _checkMutation(data['collection'], action);
  }
}
