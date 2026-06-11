class Profile {
  final String id;
  final String installationId;
  final String? firstName;
  final String? lastName;
  final String displayName;
  final String? greeting;
  final String? avatarPath;
  final bool isActive;
  final List<Map<String, dynamic>> vehicles;

  const Profile({
    required this.id,
    required this.installationId,
    this.firstName,
    this.lastName,
    required this.displayName,
    this.greeting,
    this.avatarPath,
    required this.isActive,
    this.vehicles = const [],
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
    id: map['id'] as String,
    installationId: map['installation_id'] as String? ?? '',
    firstName: map['first_name'] as String?,
    lastName: map['last_name'] as String?,
    displayName: map['display_name'] as String? ?? '',
    greeting: map['greeting'] as String?,
    avatarPath: map['avatar_path'] as String?,
    isActive: map['is_active'] as bool? ?? true,
    vehicles: map['vehicles'] != null
        ? List<Map<String, dynamic>>.from(map['vehicles'] as List)
        : [],
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'installation_id': installationId,
    'first_name': firstName,
    'last_name': lastName,
    'display_name': displayName,
    'greeting': greeting,
    'avatar_path': avatarPath,
    'is_active': isActive,
    'vehicles': vehicles,
  };
}
