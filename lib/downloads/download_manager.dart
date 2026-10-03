import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/library_store.dart';
import '../data/audio_preferences.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import 'download_record.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager(
    this.store, {
    http.Client Function()? clientFactory,
    Directory? directory,
    this.maxBytes = 256 * 1024 * 1024,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _directory =
           directory ??
           Directory(
             path.join(path.dirname(store.db.path), 'downloaded_audio'),
           );

  final LibraryStore store;
  final http.Client Function() _clientFactory;
  final Directory _directory;
  final int maxBytes;
  AudioQuality quality = AudioQuality.high;
  List<DownloadRecord> _items = [];
  List<DownloadRecord> get items => List.unmodifiable(_items);
  List<Track> get tracks => _items
      .where((item) => item.state == DownloadState.ready)
      .map((item) => item.track)
      .toList();
  int get storedBytes => _items
      .where((item) => item.state == DownloadState.ready)
      .fold(0, (sum, item) => sum + item.bytes);
  int get pendingCount => _items.where((item) => item.active).length;
  String? _account;
  ZvukApi? _api;
  bool _closed = false, _suspended = false, _recovered = false;
  Future<void> _commands = Future.value();
  Future<void>? _worker;
  _DownloadJob? _job;

  DownloadRecord? forTrack(String id) =>
      _items.where((item) => item.track.id == id).firstOrNull;

  Future<void> _command(Future<void> Function() action) {
    final next = _commands.catchError((_) {}).then((_) async {
      if (_closed) return;
      await action();
    });
    _commands = next;
    return next;
  }

  Future<void> configure(String account, ZvukApi? api) => _command(() async {
    if (!_recovered) {
      await _recover();
      _recovered = true;
    }
    if (_account == account) {
      _api = api;
      return;
    }
    _suspended = true;
    _job?.cancel();
    await _worker;
    if (_account != null) {
      await store.db.update(
        'downloads',
        {
          'state': 'failed',
          'bytes': 0,
          'error': 'Загрузка прервана. Нажми повтор.',
        },
        where: 'account=? AND state IN (?,?)',
        whereArgs: [_account, 'queued', 'downloading'],
      );
    }
    _account = account;
    _api = api;
    _items = (await store.db.query(
      'downloads',
      where: 'account=?',
      whereArgs: [account],
      orderBy: 'created,track',
    )).map(DownloadRecord.fromRow).toList();
    _suspended = false;
    _notify();
  });

  static bool _safeName(String name) => RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.audio$',
  ).hasMatch(name);

  File _file(String name) {
    if (!_safeName(name)) {
      throw const _DownloadFailure(
        'Файл загрузки повреждён. Скачай песню снова.',
      );
    }
    return File(path.join(_directory.path, name));
  }

  Future<void> _recover() async {
    await _directory.create(recursive: true);
    final retained = <String>{};
    for (final row in await store.db.query('downloads')) {
      try {
        final item = DownloadRecord.fromRow(row);
        final file = _file(item.file);
        if (item.state == DownloadState.ready &&
            item.bytes > 0 &&
            await file.exists() &&
            await file.length() == item.bytes) {
          retained.add(item.file);
        } else {
          await _write(
            item.withState(
              DownloadState.failed,
              error: item.state == DownloadState.ready
                  ? 'Файл не найден. Скачай песню снова.'
                  : item.error ?? 'Загрузка прервана. Нажми повтор.',
            ),
          );
        }
      } catch (_) {
        await store.db.delete(
          'downloads',
          where: 'account=? AND track=?',
          whereArgs: [row['account'], row['track']],
        );
      }
    }
    await for (final entity in _directory.list()) {
      final name = path.basename(entity.path);
      if (entity is File && !retained.contains(name)) await entity.delete();
    }
  }

  Future<String?> localPath(String account, String id) async {
    final rows = await store.db.query(
      'downloads',
      where: 'account=? AND track=? AND state=?',
      whereArgs: [account, id, 'ready'],
    );
    if (rows.isEmpty) return null;
    try {
      final item = DownloadRecord.fromRow(rows.single);
      final file = _file(item.file);
      if (item.bytes > 0 &&
          await file.exists() &&
          await file.length() == item.bytes) {
        return file.path;
      }
      // A concurrent removal/retry must not be resurrected by an old lookup.
      final changed = await store.db.update(
        'downloads',
        {
          'state': 'failed',
          'bytes': 0,
          'error': 'Файл не найден. Скачай песню снова.',
        },
        where: 'account=? AND track=? AND file=? AND state=?',
        whereArgs: [account, id, item.file, 'ready'],
      );
      if (changed > 0 && forTrack(id)?.file == item.file) {
        _replace(
          item.withState(
            DownloadState.failed,
            error: 'Файл не найден. Скачай песню снова.',
          ),
        );
        _notify();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> enqueue(List<Track> tracks) => _command(() async {
    final account = _account;
    if (account == null || _api == null) {
      throw const ZvukException('Для скачивания подключи Звук в настройках.');
    }
    final added = <DownloadRecord>[];
    final seen = <String>{};
    for (final track in tracks) {
      if (!seen.add(track.id)) continue;
      final old = forTrack(track.id);
      if (old?.active == true || old?.state == DownloadState.ready) continue;
      added.add(
        DownloadRecord(
          account: account,
          track: track,
          file: '${const Uuid().v4()}.audio',
          state: DownloadState.queued,
          bytes: 0,
          created: old?.created ?? DateTime.now().toUtc(),
        ),
      );
    }
    await store.db.transaction((txn) async {
      for (final item in added) {
        await txn.insert(
          'downloads',
          item.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    for (final item in added) {
      _replace(item);
    }
    _notify();
    _startWorker();
  });

  void _replace(DownloadRecord item) {
    if (item.account != _account || _closed) return;
    final index = _items.indexWhere((old) => old.track.id == item.track.id);
    if (index < 0) {
      _items.add(item);
    } else {
      _items[index] = item;
    }
  }

  Future<void> _write(DownloadRecord item) async {
    await store.db.insert(
      'downloads',
      item.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _replace(item);
    _notify();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _startWorker() {
    if (_worker != null || _closed || _suspended) return;
    _worker = _drain().whenComplete(() {
      _worker = null;
      if (!_closed &&
          !_suspended &&
          _items.any((item) => item.state == DownloadState.queued)) {
        _startWorker();
      }
    });
    // All transfer failures are represented by retryable rows. Contain database
    // failures too, so an asynchronous worker never becomes an unhandled error.
    unawaited(_worker!.catchError((_) {}));
  }

  Future<void> _drain() async {
    while (!_closed && !_suspended) {
      final item = _items
          .where((item) => item.state == DownloadState.queued)
          .firstOrNull;
      if (item == null) return;
      final job = _DownloadJob(item.track.id, _clientFactory());
      _job = job;
      try {
        await _transfer(item, job, _api);
      } catch (_) {
        _replace(
          item.withState(
            DownloadState.failed,
            error: 'Не удалось сохранить загрузку. Повтори позже.',
          ),
        );
        _notify();
      } finally {
        job.client.close();
        job.done.complete();
        if (identical(_job, job)) _job = null;
      }
    }
  }

  Future<void> _transfer(
    DownloadRecord item,
    _DownloadJob job,
    ZvukApi? api,
  ) async {
    final file = _file(item.file),
        partial = File('${_file(item.file).path}.part');
    IOSink? sink;
    StreamIterator<List<int>>? chunks;
    var committed = false;
    try {
      await _write(item.withState(DownloadState.downloading));
      if (api == null) {
        throw const _DownloadFailure('Подключи Звук и повтори загрузку.');
      }
      final url = Uri.tryParse(
        await job.run(api.streamUrl(item.track.id, quality: quality)),
      );
      job.check();
      if (url == null ||
          url.host.isEmpty ||
          (url.scheme != 'https' &&
              !(kDebugMode &&
                  url.scheme == 'http' &&
                  url.host == '127.0.0.1'))) {
        throw const _DownloadFailure(
          'Звук не предоставил файл для скачивания.',
        );
      }
      final response = await job.run(
        job.client
            .send(http.Request('GET', url))
            .timeout(const Duration(seconds: 30)),
      );
      job.check();
      final type = response.headers['content-type']
          ?.split(';')
          .first
          .toLowerCase();
      if (response.statusCode != 200 ||
          (type != null &&
              !type.startsWith('audio/') &&
              type != 'application/octet-stream' &&
              type != 'binary/octet-stream')) {
        throw const _DownloadFailure(
          'Не удалось получить аудиофайл. Попробуй снова.',
        );
      }
      final total = response.contentLength;
      if (total != null && (total < 128 || total > maxBytes)) {
        throw const _DownloadFailure('Аудиофайл имеет неподходящий размер.');
      }
      sink = partial.openWrite();
      var received = 0;
      final prefix = <int>[];
      var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      chunks = StreamIterator(
        response.stream.timeout(const Duration(seconds: 30)),
      );
      var buffered = 0;
      final deadline = DateTime.now().add(const Duration(minutes: 15));
      while (await job.run(chunks.moveNext())) {
        job.check();
        if (DateTime.now().isAfter(deadline)) {
          throw const _DownloadFailure(
            'Загрузка заняла слишком много времени. Повтори позже.',
          );
        }
        final chunk = chunks.current;
        received += chunk.length;
        buffered += chunk.length;
        if (received > maxBytes) {
          throw const _DownloadFailure('Песня слишком большая для скачивания.');
        }
        if (prefix.length < 64) prefix.addAll(chunk.take(64 - prefix.length));
        if (prefix.length >= 64 && !_audioHeader(prefix)) {
          throw const _DownloadFailure(
            'Вместо музыки получен повреждённый файл.',
          );
        }
        sink.add(chunk);
        if (buffered >= 1024 * 1024) {
          await sink.flush();
          buffered = 0;
        }
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 250) {
          lastUpdate = now;
          _replace(
            item.withState(
              DownloadState.downloading,
              bytes: received,
              total: total,
            ),
          );
          _notify();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      job.check();
      if (received < 128 ||
          (total != null && received != total) ||
          !_audioHeader(prefix)) {
        throw const _DownloadFailure('Загрузка не завершилась. Нажми повтор.');
      }
      await partial.rename(file.path);
      job.check();
      await _write(
        item.withState(DownloadState.ready, bytes: received, total: received),
      );
      committed = true;
    } catch (e) {
      if (!job.cancelled) {
        await _write(
          item.withState(
            DownloadState.failed,
            error: e is _DownloadFailure
                ? e.message
                : e is FileSystemException && e.osError?.errorCode == 28
                ? 'На устройстве нет места. Удали лишние загрузки и повтори.'
                : 'Не удалось скачать. Проверь интернет и свободное место, затем повтори.',
          ),
        );
        if (e is FileSystemException && e.osError?.errorCode == 28) {
          // Do not spend mobile traffic on the rest of a list when storage is full.
          for (final queued in List<DownloadRecord>.of(
            _items.where((item) => item.state == DownloadState.queued),
          )) {
            await _write(
              queued.withState(
                DownloadState.failed,
                error:
                    'На устройстве нет места. Удали лишние загрузки и повтори.',
              ),
            );
          }
        }
      }
    } finally {
      job.client.close();
      await chunks?.cancel();
      try {
        await sink?.close();
      } catch (_) {
        /* Failed writes may already be closed. */
      }
      if (!committed) {
        for (final candidate in [partial, file]) {
          if (await candidate.exists()) await candidate.delete();
        }
      }
    }
  }

  static bool _audioHeader(List<int> b) {
    bool text(int at, String value) =>
        b.length >= at + value.length &&
        listEquals(b.sublist(at, at + value.length), value.codeUnits);
    return text(0, 'ID3') ||
        (b.length > 1 && b[0] == 0xff && (b[1] & 0xe0) == 0xe0) ||
        (text(0, 'RIFF') && text(8, 'WAVE')) ||
        text(0, 'fLaC') ||
        text(0, 'OggS') ||
        text(4, 'ftyp');
  }

  Future<void> cancel(String id) => remove(id);

  Future<void> remove(String id) => _command(() async {
    final item = forTrack(id);
    if (item == null) return;
    _items.removeWhere((item) => item.track.id == id);
    if (_job?.id == id) {
      final job = _job!;
      job.cancel();
      await job.done.future;
    }
    final file = _file(item.file);
    for (final candidate in [file, File('${file.path}.part')]) {
      if (await candidate.exists()) await candidate.delete();
    }
    await store.db.delete(
      'downloads',
      where: 'account=? AND track=?',
      whereArgs: [item.account, id],
    );
    _items.removeWhere((item) => item.track.id == id);
    _notify();
  });

  Future<void> clear() => _command(() async {
    _suspended = true;
    _job?.cancel();
    await _worker;
    try {
      for (final item in _items) {
        final file = _file(item.file);
        for (final candidate in [file, File('${file.path}.part')]) {
          if (await candidate.exists()) await candidate.delete();
        }
      }
      await store.db.delete(
        'downloads',
        where: 'account=?',
        whereArgs: [_account],
      );
      _items = [];
      _notify();
    } finally {
      _suspended = false;
    }
  });

  Future<void> close() async {
    await _commands.catchError((_) {});
    _closed = true;
    _job?.cancel();
    await _worker;
    super.dispose();
  }
}

class _DownloadJob {
  _DownloadJob(this.id, this.client);
  final String id;
  final http.Client client;
  final done = Completer<void>();
  final _cancelled = Completer<void>();
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    if (!_cancelled.isCompleted) _cancelled.complete();
    client.close();
  }

  Future<T> run<T>(Future<T> operation) => Future.any([
    operation,
    _cancelled.future.then<T>(
      (_) => throw const _DownloadFailure('Загрузка отменена.'),
    ),
  ]);

  void check() {
    if (cancelled) throw const _DownloadFailure('Загрузка отменена.');
  }
}

class _DownloadFailure implements Exception {
  const _DownloadFailure(this.message);
  final String message;
}
