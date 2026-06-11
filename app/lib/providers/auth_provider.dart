import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authProvider = Provider<User?>((ref) {
  return Supabase.instance.client.auth.currentUser;
});
