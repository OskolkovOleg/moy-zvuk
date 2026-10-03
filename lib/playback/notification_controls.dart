part of 'music_handler.dart';

extension _NotificationControls on MusicHandler {
  // The identity travels in the action name too: an old notification must not
  // apply its vote to a new track or a newly connected account.
  String _ratingActionName(int delta) =>
      'zvuk.rate.${delta > 0 ? 'plus' : 'minus'}:$_generation:'
      '${Uri.encodeComponent(_account ?? '')}:'
      '${Uri.encodeComponent(playlist.current?.id ?? '')}';

  List<MediaControl> _notificationControls(bool playing) => [
    MediaControl.skipToPrevious,
    playing ? MediaControl.pause : MediaControl.play,
    MediaControl.skipToNext,
    if (_account != null &&
        playlist.current != null &&
        onNotificationVote != null) ...[
      MediaControl.custom(
        androidIcon: 'drawable/ic_rating_minus',
        label: 'Минус 1 балл',
        name: _ratingActionName(-1),
      ),
      MediaControl.custom(
        androidIcon: 'drawable/ic_rating_plus',
        label: 'Плюс 1 балл',
        name: _ratingActionName(1),
      ),
    ],
  ];

  Future<bool> _rateFromNotification(String name) async {
    final account = _account, track = playlist.current;
    final vote = onNotificationVote;
    if (account == null || track == null || vote == null) return false;
    final delta = name == _ratingActionName(-1)
        ? -1
        : name == _ratingActionName(1)
        ? 1
        : null;
    if (delta == null) return false;
    try {
      await vote(account, track, delta);
      return true;
    } catch (_) {
      error.value = 'Оценка не сохранилась. Попробуй ещё раз.';
      return false;
    }
  }
}
