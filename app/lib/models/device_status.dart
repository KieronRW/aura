class DeviceStatus {
  final String installationId;
  final String? currentState;
  final bool? isOnline;
  final DateTime? lastSeenAt;
  final Map<String, dynamic> raw;

  const DeviceStatus({
    required this.installationId,
    this.currentState,
    this.isOnline,
    this.lastSeenAt,
    required this.raw,
  });

  factory DeviceStatus.fromMap(Map<String, dynamic> map) => DeviceStatus(
    installationId: map['installation_id'] as String? ?? '',
    currentState: map['current_state'] as String?,
    isOnline: map['is_online'] as bool?,
    lastSeenAt: map['last_seen_at'] != null
        ? DateTime.tryParse(map['last_seen_at'] as String)
        : null,
    raw: Map<String, dynamic>.from(map),
  );
}
