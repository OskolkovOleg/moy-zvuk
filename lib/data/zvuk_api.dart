import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'audio_preferences.dart';
import 'catalog_models.dart';
import 'personal_models.dart';
import 'wave_source.dart';
import 'search_models.dart';
import 'wave_options.dart';

part 'catalog_api.dart';
part 'personal_api.dart';
part 'radio_api.dart';
part 'search_api.dart';

class ZvukException implements Exception {
  const ZvukException(this.message, {this.auth = false});
  final String message;
  final bool auth;
  @override
  String toString() => message;
}

class ZvukApi {
  ZvukApi(this.token, {http.Client? client})
    : _client = client ?? http.Client();
  final String token;
  final http.Client _client;
  final Map<String, Cookie> _cookies = {};
  static const _fields =
      'id title duration artists { id title } release { id image { src } }';
  void close() => _client.close();

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
  }) async {
    try {
      var uri = Uri.https('zvuk.com', path, params);
      var method = body == null ? 'GET' : 'POST';
      String? payload = body == null ? null : jsonEncode(body);
      late http.Response response;
      for (var redirects = 0; ; redirects++) {
        // Follow routing redirects ourselves, never forwarding credentials
        // outside the fixed HTTPS API origin.
        final request = http.Request(method, uri)..followRedirects = false;
        request.headers.addAll({
          'X-Auth-Token': token,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Referer': 'https://zvuk.com/',
          'Origin': 'https://zvuk.com',
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        });
        final cookies = _cookies.values.where(
          (c) =>
              (c.expires == null || c.expires!.isAfter(DateTime.now())) &&
              uri.path.startsWith(c.path ?? '/'),
        );
        if (cookies.isNotEmpty) {
          request.headers['Cookie'] = cookies
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
        }
        if (payload != null) request.body = payload;
        response = await http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 25)),
        ).timeout(const Duration(seconds: 25));
        final setCookie = response.headers['set-cookie'];
        if (setCookie != null) {
          for (final value in setCookie.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
            try {
              final cookie = Cookie.fromSetCookieValue(value.trim());
              final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '');
              if (domain == null || domain == 'zvuk.com') {
                if (cookie.maxAge == 0) {
                  _cookies.remove(cookie.name);
                } else {
                  _cookies[cookie.name] = cookie;
                }
              }
            } catch (_) {
              /* Ignore malformed optional routing cookies. */
            }
          }
        }
        if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
        final location = response.headers['location'];
        final next = location == null ? null : uri.resolve(location);
        if (redirects >= 3 ||
            next == null ||
            next.scheme != 'https' ||
            next.host != 'zvuk.com' ||
            next.port != 443 ||
            !next.path.startsWith('/api/')) {
          throw const ZvukException(
            'Не удалось безопасно подключиться к API Звука.',
          );
        }
        if (response.statusCode == 303 ||
            ((response.statusCode == 301 || response.statusCode == 302) &&
                method == 'POST')) {
          method = 'GET';
          payload = null;
        }
        uri = next;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ZvukException(
          'Подключение истекло. Обнови токен в настройках.',
          auth: true,
        );
      }
      if (response.statusCode != 200) {
        throw const ZvukException('Звук сейчас недоступен. Попробуй ещё раз.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['errors'] != null || data['error'] != null) {
        throw const ZvukException(
          'Звук не выполнил запрос. Проверь подключение.',
        );
      }
      return data;
    } on ZvukException {
      rethrow;
    } catch (_) {
      throw const ZvukException(
        'Не удалось связаться со Звуком. Проверь интернет.',
      );
    }
  }

  Future<Map<String, dynamic>> _graph(
    String name,
    String query, [
    Map<String, dynamic> variables = const {},
  ]) async {
    final raw = await _request(
      '/api/v1/graphql',
      body: {'operationName': name, 'query': query, 'variables': variables},
    );
    final data = raw['data'];
    if (data is! Map<String, dynamic>) {
      throw const ZvukException('Неожиданный ответ Звука.');
    }
    return data;
  }

  Future<Account> profile() async {
    final raw = await _request('/api/tiny/profile');
    final p = raw['result'];
    if (p is! Map ||
        p['id'] == null ||
        (p['is_anonymous'] ?? p['isAnonymous']) == true ||
        (p['is_registered'] ?? p['isRegistered']) != true) {
      throw const ZvukException(
        'Токен не подошёл. Введи токен своего аккаунта Звука.',
        auth: true,
      );
    }
    return Account(
      p['id'].toString(),
      (p['name'] ?? p['username'] ?? 'Мой аккаунт').toString(),
    );
  }

  Future<List<Track>> tracks(List<String> ids) async {
    final found = <String, Track>{};
    for (var start = 0; start < ids.length; start += 100) {
      final batch = ids.sublist(start, (start + 100).clamp(0, ids.length));
      final data = await _graph(
        'getTracks',
        'query getTracks(\$ids: [ID!]!) { getTracks(ids: \$ids) { $_fields } }',
        {'ids': batch},
      );
      for (final item
          in (data['getTracks'] as List? ?? [])
              .whereType<Map<String, dynamic>>()) {
        final track = Track.fromApi(item);
        found[track.id] = track;
      }
    }
    return ids
        .map((id) => found[id] ?? Track(id: id, title: 'Недоступный трек'))
        .toList();
  }

  Future<List<Track>> favorites() async {
    final data = await _graph(
      'userCollection',
      'query userCollection { collection { tracks { id } } }',
    );
    final ids = (data['collection']['tracks'] as List)
        .map((e) => e['id'].toString())
        .toList();
    return tracks(ids);
  }

  Future<List<PlaylistInfo>> playlists() async {
    final data = await _graph(
      'userPlaylists',
      'query userPlaylists { collection { playlists { id } } }',
    );
    final ids = (data['collection']['playlists'] as List)
        .map((e) => e['id'].toString())
        .toList();
    return getPlaylists(ids);
  }

  Future<List<Track>> playlistTracks(String id) async {
    final all = <Track>[];
    var offset = 0;
    while (true) {
      final data = await _graph(
        'getPlaylistTracks',
        'query getPlaylistTracks(\$id: ID!, \$limit: Int, \$offset: Int) { playlistTracks(id: \$id, limit: \$limit, offset: \$offset) { $_fields } }',
        {'id': id, 'limit': 100, 'offset': offset},
      );
      final rawBatch = data['playlistTracks'] as List;
      final batch = rawBatch
          .whereType<Map<String, dynamic>>()
          .map((j) => Track.fromApi(j))
          .toList();
      offset += rawBatch.length;
      all.addAll(batch);
      if (rawBatch.length < 100) return all;
    }
  }

  Future<SearchPage> search(String query, {String? cursor}) async {
    final data = await _graph(
      'search',
      'query search(\$query: String, \$cursor: Cursor) { search(query: \$query) { tracks(limit: 30, cursor: \$cursor) { page { next cursor } items { $_fields } } } }',
      {'query': query, 'cursor': cursor},
    );
    final result = data['search']['tracks'];
    return SearchPage(
      (result['items'] as List).map((j) => Track.fromApi(j)).toList(),
      result['page']?['next'] == null
          ? null
          : result['page']?['cursor']?.toString(),
    );
  }

  Future<String> streamUrl(
    String id, {
    AudioQuality quality = AudioQuality.high,
  }) async {
    final data = await _request(
      '/api/tiny/track/stream',
      params: {'id': id, 'quality': quality.apiValue},
    );
    final url = data['result']?['stream'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const ZvukException(
        'Для этого трека нет доступного потока. Выбери следующий.',
      );
    }
    return url as String;
  }
}
