class Profile {
  final String id;
  final String installationId;
  final String displayName;
  final String? greetingMessage;
  final String? avatarUrl;
  final bool isActive;
  final List<Map<String, dynamic>> vehicles;

  const Profile({
    required this.id,
    required this.installationId,
    required this.displayName,
    this.greetingMessage,
    this.avatarUrl,
    required this.isActive,
    this.vehicles = const [],
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
    id: map['id'] as String,
    installationId: map['installation_id'] as String? ?? '',
    displayName: map['display_name'] as String? ?? '',
    greetingMessage: map['greeting_message'] as String?,
    avatarUrl: map['avatar_url'] as String?,
    isActive: map['is_active'] as bool? ?? true,
    vehicles: map['vehicles'] != null
        ? List<Map<String, dynamic>>.from(map['vehicles'] as List)
        : [],
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'installation_id': installationId,
    'display_name': displayName,
    'greeting_message': greetingMessage,
    'avatar_url': avatarUrl,
    'is_active': isActive,
  };
}
