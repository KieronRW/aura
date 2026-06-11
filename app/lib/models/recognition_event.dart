class RecognitionEvent {
  final String id;
  final String installationId;
  final String? vehicleId;
  final DateTime? arrivedAt;
  final DateTime? departedAt;
  final String? detectedMake;
  final String? detectedModel;
  final String? detectedColour;
  final String? detectedPlate;
  final String? imagePath;
  final double? confidence;

  const RecognitionEvent({
    required this.id,
    required this.installationId,
    this.vehicleId,
    this.arrivedAt,
    this.departedAt,
    this.detectedMake,
    this.detectedModel,
    this.detectedColour,
    this.detectedPlate,
    this.imagePath,
    this.confidence,
  });

  factory RecognitionEvent.fromMap(Map<String, dynamic> map) => RecognitionEvent(
    id: map['id'] as String,
    installationId: map['installation_id'] as String? ?? '',
    vehicleId: map['vehicle_id'] as String?,
    arrivedAt: map['arrived_at'] != null
        ? DateTime.tryParse(map['arrived_at'] as String)
        : null,
    departedAt: map['departed_at'] != null
        ? DateTime.tryParse(map['departed_at'] as String)
        : null,
    detectedMake: map['detected_make'] as String?,
    detectedModel: map['detected_model'] as String?,
    detectedColour: map['detected_colour'] as String?,
    detectedPlate: map['detected_plate'] as String?,
    imagePath: map['image_path'] as String?,
    confidence: (map['confidence'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'installation_id': installationId,
    'vehicle_id': vehicleId,
    'arrived_at': arrivedAt?.toIso8601String(),
    'departed_at': departedAt?.toIso8601String(),
    'detected_make': detectedMake,
    'detected_model': detectedModel,
    'detected_colour': detectedColour,
    'detected_plate': detectedPlate,
    'image_path': imagePath,
    'confidence': confidence,
  };
}
