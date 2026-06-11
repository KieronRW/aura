// Supabase service — all database calls in one place, no UI logic here

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  // ── Properties ────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getProperties() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('properties')
          .select('*')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

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

      debugPrint('getInstallation: properties = $properties');

      if ((properties as List).isEmpty) return null;

      final propertyIds = (properties as List)
          .map((p) => p['id'] as String)
          .toList();

      debugPrint('getInstallation: propertyIds = $propertyIds');

      final response = await _client
          .from('installations')
          .select('*')
          .inFilter('property_id', propertyIds)
          .eq('is_active', true)
          .maybeSingle();

      debugPrint('getInstallation: installation = $response');

      return response;
    } catch (e) {
      debugPrint('getInstallation error: $e');
      return null;
    }
  }

  // ── Installations by property ─────────────────────────────

  static Future<List<Map<String, dynamic>>> getInstallationsByProperty(
    String propertyId,
  ) async {
    try {
      final response = await _client
          .from('installations')
          .select('*')
          .eq('property_id', propertyId)
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
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

  static Future<Map<String, dynamic>?> getDeviceStatusById(
    String installationId,
  ) async {
    try {
      final response = await _client
          .from('device_status')
          .select('*')
          .eq('installation_id', installationId)
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
      debugPrint('getRecentEvents error: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getRecentEventsByInstallation(
    String installationId, {
    int limit = 20,
  }) async {
    try {
      final response = await _client
          .from('recognition_events')
          .select('*')
          .eq('installation_id', installationId)
          .not('detected_make', 'is', null)
          .neq('detected_make', '')
          .order('arrived_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // ── Storage ───────────────────────────────────────────────

  static Future<String?> getSignedImageUrl(String path) async {
    try {
      final response = await _client.storage
          .from('recognition-images')
          .createSignedUrl(path, 3600); // 1 hour expiry
      return response;
    } catch (e) {
      debugPrint('getSignedImageUrl error: $e');
      return null;
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

  // ── Visitors ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getExpectedVisitors(
    String installationId,
  ) async {
    try {
      final response = await _client
          .from('visitors')
          .select('*')
          .eq('installation_id', installationId)
          .eq('is_active', true)
          .order('expected_from', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('getExpectedVisitors error: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUnknownVehicles(
    String installationId,
  ) async {
    try {
      final response = await _client
          .from('unknown_vehicles')
          .select('*')
          .eq('installation_id', installationId)
          .eq('status', 'unreviewed')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('getUnknownVehicles error: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getVisitorHistory(
    String installationId, {
    int limit = 50,
  }) async {
    try {
      final response = await _client
          .from('recognition_events')
          .select('arrived_at, detected_make, visitor_id, visitors(name)')
          .eq('installation_id', installationId)
          .not('visitor_id', 'is', null)
          .order('arrived_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('getVisitorHistory error: $e');
      return [];
    }
  }
}
