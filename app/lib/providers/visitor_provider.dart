import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';

class VisitorDataNotifier
    extends FamilyAsyncNotifier<Map<String, List<Map<String, dynamic>>>, String> {
  @override
  Future<Map<String, List<Map<String, dynamic>>>> build(
    String installationId,
  ) async {
    debugPrint('visitorDataProvider: fetching expected visitors...');
    final visitors = await SupabaseService.getExpectedVisitors(installationId);
    debugPrint('visitorDataProvider: got ${visitors.length} visitors — fetching unknown vehicles...');
    final unknownVehicles = await SupabaseService.getUnknownVehicles(installationId);
    debugPrint('visitorDataProvider: got ${unknownVehicles.length} unknown vehicles — fetching history...');
    final history = await SupabaseService.getVisitorHistory(installationId);
    debugPrint('visitorDataProvider: got ${history.length} history rows — done');
    return {
      'visitors': visitors,
      'unknownVehicles': unknownVehicles,
      'history': history,
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
