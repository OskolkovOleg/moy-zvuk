enum GenreSource { track, release }

/// Original catalog metadata. A name can be valid even if it has no known group.
class TrackGenre {
  const TrackGenre({required this.id, required this.name, this.shortName});

  final String id, name;
  final String? shortName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'shortName': shortName,
  };

  static List<TrackGenre> listFromJson(dynamic value) {
    if (value is! List) return const [];
    return List.unmodifiable(
      value
          .whereType<Map>()
          .where(
            (j) =>
                j['name'] is String && (j['name'] as String).trim().isNotEmpty,
          )
          .map(
            (j) => TrackGenre(
              id: j['id']?.toString() ?? '',
              name: j['name'] as String,
              shortName: j['shortName'] is String
                  ? j['shortName'] as String
                  : null,
            ),
          ),
    );
  }
}
