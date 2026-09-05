import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/device.dart';
import 'storage_service.dart';

class AuthExpiredException implements Exception {
  final String message;
  AuthExpiredException([this.message = 'Sitzung abgelaufen oder Server neu aufgesetzt.']);
  @override
  String toString() => message;
}

class ApiService {
  final StorageService _storage;

  ApiService(this._storage);

  String get _baseUrl => _storage.serverUrl;

  Map<String, String> _headers({bool auth = true}) {
    final map = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth && _storage.token != null) {
      map['Authorization'] = 'Bearer ${_storage.token}';
    }
    return map;
  }

  // Register
  Future<AppUser> register(String email, String username, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/register'),
      headers: _headers(auth: false),
      body: jsonEncode({
        'email': email.trim(),
        'username': username.trim(),
        'password': password,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final token = data['access_token'];
      final user = AppUser.fromJson(data, token);
      await _storage.setToken(token);
      await _storage.saveUser(id: user.id, email: user.email, username: user.username);
      return user;
    } else {
      final error = _parseError(response.body);
      throw Exception(error.isNotEmpty ? error : 'Registrierung fehlgeschlagen (${response.statusCode})');
    }
  }

  // Login
  Future<AppUser> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/login'),
      headers: _headers(auth: false),
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['access_token'];
      final user = AppUser.fromJson(data, token);
      await _storage.setToken(token);
      await _storage.saveUser(id: user.id, email: user.email, username: user.username);
      return user;
    } else {
      final error = _parseError(response.body);
      throw Exception(error.isNotEmpty ? error : 'Login fehlgeschlagen (${response.statusCode})');
    }
  }

  // Register Device
  Future<void> registerDevice({
    required String deviceId,
    required String name,
    required String platform,
    required List<String> localIps,
    required List<String> vpnIps,
    required int transferPort,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/devices/register'),
      headers: _headers(),
      body: jsonEncode({
        'device_id': deviceId,
        'name': name,
        'platform': platform,
        'local_ips': localIps,
        'vpn_ips': vpnIps,
        'transfer_port': transferPort,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 401) {
      throw AuthExpiredException();
    }
    if (response.statusCode != 200) {
      throw Exception('Gerät konnte nicht registriert werden: ${_parseError(response.body)}');
    }
  }

  // Heartbeat
  Future<void> sendHeartbeat({
    required String deviceId,
    required List<String> localIps,
    required List<String> vpnIps,
    required int transferPort,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/devices/$deviceId/heartbeat'),
      headers: _headers(),
      body: jsonEncode({
        'local_ips': localIps,
        'vpn_ips': vpnIps,
        'transfer_port': transferPort,
      }),
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      throw AuthExpiredException();
    }
  }

  // Get Devices
  Future<List<DeviceModel>> getDevices() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/devices'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      throw AuthExpiredException();
    }

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => DeviceModel.fromJson(json)).toList();
    } else {
      throw Exception('Geräteliste konnte nicht geladen werden.');
    }
  }

  // Delete Device
  Future<void> deleteDevice(String deviceId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/devices/$deviceId'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 401) {
      throw AuthExpiredException();
    }
    if (response.statusCode != 200) {
      throw Exception('Gerät konnte nicht entfernt werden.');
    }
  }

  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
    } catch (_) {}
    return '';
  }
}
