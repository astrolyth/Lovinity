class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.timezone,
    required this.madhhab,
    required this.calcMethod,
    this.latitude,
    this.longitude,
    this.gender,
  });

  final String id;
  final String displayName;
  final String timezone;
  final String madhhab;
  final String calcMethod;
  final double? latitude;
  final double? longitude;
  final String? gender;

  factory UserProfile.fromRow(Map<String, dynamic> row) => UserProfile(
        id: row['id'] as String,
        displayName: (row['display_name'] ?? '') as String,
        timezone: (row['timezone'] ?? 'UTC') as String,
        madhhab: (row['madhhab'] ?? 'shafi') as String,
        calcMethod: (row['calc_method'] ?? 'muslim_world_league') as String,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        gender: row['gender'] as String?,
      );

  UserProfile copyWith({
    String? displayName,
    String? timezone,
    String? madhhab,
    String? calcMethod,
    double? latitude,
    double? longitude,
    String? gender,
  }) =>
      UserProfile(
        id: id,
        displayName: displayName ?? this.displayName,
        timezone: timezone ?? this.timezone,
        madhhab: madhhab ?? this.madhhab,
        calcMethod: calcMethod ?? this.calcMethod,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        gender: gender ?? this.gender,
      );
}
