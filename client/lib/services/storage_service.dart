import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';

class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // Server URL
  String get serverUrl =>
      _prefs.getString(AppConstants.keyServerUrl) ?? 'http://127.0.0.1:8000';
  Future<void> setServerUrl(String url) =>
      _prefs.setString(AppConstants.keyServerUrl, url.trim().replaceAll(RegExp(r'/+$'), ''));

  // Auth Token
  String? get token => _prefs.getString(AppConstants.keyAuthToken);
  Future<void> setToken(String? token) async {
    if (token == null) {
      await _prefs.remove(AppConstants.keyAuthToken);
    } else {
      await _prefs.setString(AppConstants.keyAuthToken, token);
    }
  }

  // User Info
  String? get email => _prefs.getString(AppConstants.keyUserEmail);
  String? get username => _prefs.getString(AppConstants.keyUsername);
  int? get userId => _prefs.getInt(AppConstants.keyUserId);

  Future<void> saveUser({required int id, required String email, required String username}) async {
    await _prefs.setInt(AppConstants.keyUserId, id);
    await _prefs.setString(AppConstants.keyUserEmail, email);
    await _prefs.setString(AppConstants.keyUsername, username);
  }

  Future<void> clearUser() async {
    await _prefs.remove(AppConstants.keyAuthToken);
    await _prefs.remove(AppConstants.keyUserId);
    await _prefs.remove(AppConstants.keyUserEmail);
    await _prefs.remove(AppConstants.keyUsername);
  }

  // Device ID (persistent UUID for this machine)
  String get deviceId {
    String? id = _prefs.getString(AppConstants.keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(AppConstants.keyDeviceId, id);
    }
    return id;
  }

  // Device Name
  String? get deviceName => _prefs.getString(AppConstants.keyDeviceName);
  Future<void> setDeviceName(String name) =>
      _prefs.setString(AppConstants.keyDeviceName, name);

  // Transfer Port
  int get transferPort =>
      _prefs.getInt(AppConstants.keyTransferPort) ?? AppConstants.defaultTransferPort;
  Future<void> setTransferPort(int port) =>
      _prefs.setInt(AppConstants.keyTransferPort, port);

  // Download Directory
  String? get downloadPath => _prefs.getString(AppConstants.keyDownloadPath);
  Future<void> setDownloadPath(String path) =>
      _prefs.setString(AppConstants.keyDownloadPath, path);

  // Auto-Accept Transfers from own account
  bool get autoAccept => _prefs.getBool(AppConstants.keyAutoAccept) ?? false;
  Future<void> setAutoAccept(bool val) =>
      _prefs.setBool(AppConstants.keyAutoAccept, val);
}
