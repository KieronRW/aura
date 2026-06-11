class Visitor {
  final String id;
  final String installationId;
  final String? detectedMake;
  final String? detectedModel;
  final String? detectedColour;
  final String? detectedPlate;
  final String? imagePath;
  final String? status;
  final String? assignedVehicleId;
  final DateTime? assignedAt;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final int visitCount;

  const Visitor({
    required this.id,
    required this.installationId,
    this.detectedMake,
    this.detectedModel,
    this.detectedColour,
    this.detectedPlate,
    this.imagePath,
    this.status,
    this.assignedVehicleId,
    this.assignedAt,
    this.firstSeenAt,
    this.lastSeenAt,
    this.visitCount = 1,
  });

  factory Visitor.fromMap(Map<String, dynamic> map) => Visitor(
    id: map['id'] as String,
    installationId: map['installation_id'] as String? ?? '',
    detectedMake: map['detected_make'] as String?,
    detectedModel: map['detected_model'] as String?,
    detectedColour: map['detected_colour'] as String?,
    detectedPlate: map['detected_plate'] as String?,
    imagePath: map['image_path'] as String?,
    status: map['status'] as String?,
    assignedVehicleId: map['assigned_vehicle_id'] as String?,
    assignedAt: map['assigned_at'] != null
        ? DateTime.tryParse(map['assigned_at'] as String)
        : null,
    firstSeenAt: map['first_seen_at'] != null
        ? DateTime.tryParse(map['first_seen_at'] as String)
        : null,
    lastSeenAt: map['last_seen_at'] != null
        ? DateTime.tryParse(map['last_seen_at'] as String)
        : null,
    visitCount: map['visit_count'] as int? ?? 1,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'installation_id': installationId,
    'detected_make': detectedMake,
    'detected_model': detectedModel,
    'detected_colour': detectedColour,
    'detected_plate': detectedPlate,
    'image_path': imagePath,
    'status': status,
    'assigned_vehicle_id': assignedVehicleId,
    'assigned_at': assignedAt?.toIso8601String(),
    'first_seen_at': firstSeenAt?.toIso8601String(),
    'last_seen_at': lastSeenAt?.toIso8601String(),
    'visit_count': visitCount,
  };
}
