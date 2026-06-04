// Supabase service — all database calls in one place, no UI logic here

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  // ── Installation ──────────────────────────────────────────

  static Future<Map<String, dynamic>?> getInstallation() async {
    try {
      final response = await _client
          .from('installations')
          .select('id, name, properties!inner(user_id)')
          .eq('properties.user_id', _client.auth.currentUser!.id)
          .eq('is_active', true)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  // ── Device Status ─────────────────────────────────────────

  static Future<Map<String, dynamic>?> getDeviceStatus() async {
    try {
      final installation = await getInstallation();
      if (installation == null) return null;

      final response = await _client
          .from('device_status')
          .select('*')
          .eq('installation_id', installation['id'])
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  // ── Recognition Events ────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRecentEvents({
    int limit = 20,
  }) async {
    try {
      final installation = await getInstallation();
      if (installation == null) return [];

      final response = await _client
          .from('recognition_events')
          .select('*')
          .eq('installation_id', installation['id'])
          .order('arrived_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // ── Profiles ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    try {
      final installation = await getInstallation();
      if (installation == null) return [];

      final response = await _client
          .from('profiles')
          .select('*, vehicles(*)')
          .eq('installation_id', installation['id'])
          .eq('is_active', true)
          .order('display_name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // ── Vehicles ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getVehiclesForProfile(
    String profileId,
  ) async {
    try {
      final response = await _client
          .from('vehicles')
          .select('*')
          .eq('profile_id', profileId)
          .eq('is_active', true)
          .order('make');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }
}
