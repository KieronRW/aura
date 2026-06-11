class Installation {
  final String id;
  final String propertyId;
  final String name;
  final bool isActive;

  const Installation({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.isActive,
  });

  factory Installation.fromMap(Map<String, dynamic> map) => Installation(
    id: map['id'] as String,
    propertyId: map['property_id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    isActive: map['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'property_id': propertyId,
    'name': name,
    'is_active': isActive,
  };
}
