import 'package:flutter_riverpod/flutter_riverpod.dart';

// True once the current user's terms acceptance is confirmed for this session.
// Reset to false on sign-out.
final termsAcceptedProvider = StateProvider<bool>((ref) => false);
