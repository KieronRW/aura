import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/property.dart';
import '../services/supabase_service.dart';

class PropertiesNotifier extends AsyncNotifier<List<Property>> {
  @override
  Future<List<Property>> build() async {
    final raw = await SupabaseService.getProperties();
    return raw.map(Property.fromMap).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final propertiesProvider =
    AsyncNotifierProvider<PropertiesNotifier, List<Property>>(
      PropertiesNotifier.new,
    );
