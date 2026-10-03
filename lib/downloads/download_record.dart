import 'dart:convert';

import '../data/models.dart';

enum DownloadState { queued, downloading, ready, failed }

class DownloadRecord {
  const DownloadRecord({
    required this.account,
    required this.track,
    required this.file,
    required this.state,
    required this.bytes,
    required this.created,
    this.total,
    this.error,
  });
  final String account, file;
  final Track track;
  final DownloadState state;
  final int bytes;
  final int? total;
  final DateTime created;
  final String? error;
  bool get active =>
      state == DownloadState.queued || state == DownloadState.downloading;
  double? get progress =>
      total == null || total == 0 ? null : (bytes / total!).clamp(0.0, 1.0);

  DownloadRecord withState(
    DownloadState state, {
    int bytes = 0,
    int? total,
    String? error,
  }) => DownloadRecord(
    account: account,
    track: track,
    file: file,
    state: state,
    bytes: bytes,
    total: total,
    created: created,
    error: error,
  );

  Map<String, Object?> toRow() => {
    'account': account,
    'track': track.id,
    'metadata': jsonEncode(track.toJson()),
    'file': file,
    'state': state.name,
    'bytes': bytes,
    'created': created.toUtc().toIso8601String(),
    'error': error,
  };

  factory DownloadRecord.fromRow(Map<String, Object?> row) => DownloadRecord(
    account: row['account'] as String,
    track: Track.fromJson(jsonDecode(row['metadata'] as String)),
    file: row['file'] as String,
    state: DownloadState.values.byName(row['state'] as String),
    bytes: row['bytes'] as int,
    created: DateTime.parse(row['created'] as String),
    error: row['error'] as String?,
  );
}

String downloadSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} КБ'
    : bytes < 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ'
    : '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
