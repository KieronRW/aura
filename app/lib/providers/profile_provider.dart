import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile.dart';
import '../models/vehicle.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

class ProfilesNotifier extends AsyncNotifier<List<Profile>> {
  @override
  Future<List<Profile>> build() async {
    ref.watch(authProvider);
    final raw = await SupabaseService.getProfiles();
    return raw.map(Profile.fromMap).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final profilesProvider =
    AsyncNotifierProvider<ProfilesNotifier, List<Profile>>(
      ProfilesNotifier.new,
    );

class VehiclesNotifier extends FamilyAsyncNotifier<List<Vehicle>, String> {
  @override
  Future<List<Vehicle>> build(String profileId) async {
    final raw = await SupabaseService.getVehiclesForProfile(profileId);
    return raw.map(Vehicle.fromMap).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final vehiclesProvider =
    AsyncNotifierProvider.family<VehiclesNotifier, List<Vehicle>, String>(
      VehiclesNotifier.new,
    );
