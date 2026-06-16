import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/installation.dart';
import '../models/device_status.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

final currentInstallationProvider = FutureProvider<Map<String, dynamic>?>((ref) {
  // Invalidate on real auth identity changes (logout / account switch).
  // Guard: skip when prev is null or AsyncLoading — that's the INITIAL_SESSION
  // event Supabase emits on stream subscription, not a real change. Without this
  // guard, invalidateSelf() fires immediately and abandons the in-flight future,
  // causing a silent hang until the screen's timeout fires.
  ref.listen<AsyncValue<User?>>(authProvider, (prev, next) {
    if (prev == null || prev is AsyncLoading) return;
    if (prev.valueOrNull?.id != next.valueOrNull?.id) {
      ref.invalidateSelf();
    }
  });
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Future.value(null);
  return SupabaseService.getInstallation();
});

class InstallationsNotifier
    extends FamilyAsyncNotifier<List<Installation>, String> {
  @override
  Future<List<Installation>> build(String propertyId) async {
    final raw = await SupabaseService.getInstallationsByProperty(propertyId);
    return raw.map(Installation.fromMap).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final installationsProvider = AsyncNotifierProvider.family<
    InstallationsNotifier, List<Installation>, String>(
  InstallationsNotifier.new,
);

class DeviceStatusNotifier
    extends FamilyAsyncNotifier<Map<String, dynamic>?, String> {
  @override
  Future<Map<String, dynamic>?> build(String installationId) =>
      SupabaseService.getDeviceStatusById(installationId);

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final deviceStatusProvider = AsyncNotifierProvider.family<
    DeviceStatusNotifier, Map<String, dynamic>?, String>(
  DeviceStatusNotifier.new,
);

// ignore: unused_element
DeviceStatus? _toDeviceStatus(Map<String, dynamic>? map) =>
    map != null ? DeviceStatus.fromMap(map) : null;
