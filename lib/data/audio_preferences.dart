enum AudioQuality {
  high('high', 'Высокое', 'Для лучшего звучания'),
  economy('mid', 'Экономное', 'Меньше трафика и памяти');

  const AudioQuality(this.apiValue, this.label, this.description);
  final String apiValue, label, description;

  static AudioQuality fromValue(Object? value) =>
      value == 'mid' ? AudioQuality.economy : AudioQuality.high;
}

class AudioPreferences {
  const AudioPreferences({
    this.streaming = AudioQuality.high,
    this.downloads = AudioQuality.high,
  });

  final AudioQuality streaming, downloads;

  factory AudioPreferences.fromJson(Object? value) {
    final json = value is Map ? value : const {};
    return AudioPreferences(
      streaming: AudioQuality.fromValue(json['streaming']),
      downloads: AudioQuality.fromValue(json['downloads']),
    );
  }

  AudioPreferences copyWith({
    AudioQuality? streaming,
    AudioQuality? downloads,
  }) => AudioPreferences(
    streaming: streaming ?? this.streaming,
    downloads: downloads ?? this.downloads,
  );

  Map<String, String> toJson() => {
    'streaming': streaming.apiValue,
    'downloads': downloads.apiValue,
  };
}
