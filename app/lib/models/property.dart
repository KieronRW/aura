class Property {
  final String id;
  final String name;
  final String? address;
  final String userId;
  final bool isActive;

  const Property({
    required this.id,
    required this.name,
    this.address,
    required this.userId,
    required this.isActive,
  });

  factory Property.fromMap(Map<String, dynamic> map) => Property(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    address: map['address'] as String?,
    userId: map['user_id'] as String? ?? '',
    isActive: map['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'address': address,
    'user_id': userId,
    'is_active': isActive,
  };
}
