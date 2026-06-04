// Supabase service — all database calls in one place, no UI logic here

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  // ── Installation ──────────────────────────────────────────

  static Future<Map<String, dynamic>?> getInstallation() async {
    try {
      final userId = _client.auth.currentUser?.id;
      debugPrint('getInstallation: user_id = $userId');

      if (userId == null) return null;

      final properties = await _client
          .from('properties')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true);

      debugPrint(
        'getInstallation: properties found = ${(properties as List).length}',
      );

      if ((properties as List).isEmpty) return null;

      final propertyIds = (properties as List)
          .map((p) => p['id'] as String)
          .toList();

      final response = await _client
          .from('installations')
          .select('*')
          .inFilter('property_id', propertyIds)
          .eq('is_active', true)
          .maybeSingle();

      debugPrint('getInstallation: installation found = ${response != null}');

      return response;
    } catch (e) {
      debugPrint('getInstallation error: $e');
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
      debugPrint('getDeviceStatus error: $e');
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
      debugPrint('getRecentEvents error: $e');
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
      debugPrint('getProfiles error: $e');
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
      debugPrint('getVehiclesForProfile error: $e');
      return [];
    }
  }
}
