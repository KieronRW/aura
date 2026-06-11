import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';

class VisitorDataNotifier
    extends FamilyAsyncNotifier<Map<String, List<Map<String, dynamic>>>, String> {
  @override
  Future<Map<String, List<Map<String, dynamic>>>> build(
    String installationId,
  ) async {
    final results = await Future.wait([
      SupabaseService.getExpectedVisitors(installationId),
      SupabaseService.getUnknownVehicles(installationId),
      SupabaseService.getVisitorHistory(installationId),
    ]);
    return {
      'visitors': results[0],
      'unknownVehicles': results[1],
      'history': results[2],
    };
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final visitorDataProvider = AsyncNotifierProvider.family<
    VisitorDataNotifier, Map<String, List<Map<String, dynamic>>>, String>(
  VisitorDataNotifier.new,
);
