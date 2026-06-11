import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recognition_event.dart';
import '../services/supabase_service.dart';

class RecognitionEventsNotifier
    extends FamilyAsyncNotifier<List<RecognitionEvent>, String> {
  @override
  Future<List<RecognitionEvent>> build(String installationId) async {
    final raw = await SupabaseService.getRecentEventsByInstallation(
      installationId,
    );
    return raw.map(RecognitionEvent.fromMap).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final recognitionEventsProvider = AsyncNotifierProvider.family<
    RecognitionEventsNotifier, List<RecognitionEvent>, String>(
  RecognitionEventsNotifier.new,
);
