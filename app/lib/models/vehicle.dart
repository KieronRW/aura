class Vehicle {
  final String id;
  final String profileId;
  final String? make;
  final String? model;
  final String? colour;
  final String? registration;
  final String? nickname;
  final bool isActive;

  const Vehicle({
    required this.id,
    required this.profileId,
    this.make,
    this.model,
    this.colour,
    this.registration,
    this.nickname,
    required this.isActive,
  });

  factory Vehicle.fromMap(Map<String, dynamic> map) => Vehicle(
    id: map['id'] as String,
    profileId: map['profile_id'] as String? ?? '',
    make: map['make'] as String?,
    model: map['model'] as String?,
    colour: map['colour'] as String?,
    registration: map['registration'] as String?,
    nickname: map['nickname'] as String?,
    isActive: map['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'profile_id': profileId,
    'make': make,
    'model': model,
    'colour': colour,
    'registration': registration,
    'nickname': nickname,
    'is_active': isActive,
  };
}
