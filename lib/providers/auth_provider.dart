import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/jellyfin_service.dart';

class AuthProvider with ChangeNotifier {
  final JellyfinService _service;
  final FlutterSecureStorage _secureStorage;

  String? _serverUrl;
  String? _token;
  String? _userId;
  String? _username;
  String? _deviceId;
  bool _isLoading = false;

  String? get serverUrl => _serverUrl;
  String? get token => _token;
  String? get userId => _userId;
  String? get username => _username;
  String? get deviceId => _deviceId;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null;

  AuthProvider({
    JellyfinService? service,
    FlutterSecureStorage? secureStorage,
  })  : _service = service ?? JellyfinService(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _loadFromSecureStorage();
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // Version 4
    values[8] = (values[8] & 0x3f) | 0x80; // Variant 10xx
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-${hex.sublist(10, 16).join()}';
  }

  Future<void> _loadFromSecureStorage() async {
    _serverUrl = await _secureStorage.read(key: 'serverUrl');
    _token = await _secureStorage.read(key: 'token');
    _userId = await _secureStorage.read(key: 'userId');
    _username = await _secureStorage.read(key: 'username');
    _deviceId = await _secureStorage.read(key: 'deviceId');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _generateUuidV4();
      await _secureStorage.write(key: 'deviceId', value: _deviceId!);
    }
    JellyfinService.defaultDeviceId = _deviceId;
    notifyListeners();
  }

  Future<bool> login(String url, String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_deviceId == null || _deviceId!.isEmpty) {
        _deviceId = await _secureStorage.read(key: 'deviceId');
        if (_deviceId == null || _deviceId!.isEmpty) {
          _deviceId = _generateUuidV4();
          await _secureStorage.write(key: 'deviceId', value: _deviceId!);
        }
        JellyfinService.defaultDeviceId = _deviceId;
      }

      List<String> urlsToTry = [];
      String cleanUrl = url.trim();
      if (cleanUrl.endsWith('/')) {
        cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
      }

      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        urlsToTry.add('https://$cleanUrl');
        urlsToTry.add('http://$cleanUrl');
        urlsToTry.add('http://$cleanUrl:8096');
      } else {
        urlsToTry.add(cleanUrl);
      }

      Object? lastError;
      for (String tryUrl in urlsToTry) {
        try {
          final data = await _service.authenticate(
            tryUrl,
            username,
            password,
            deviceId: _deviceId,
          );

          final token = data['AccessToken'] as String?;
          final user = data['User'] is Map<String, dynamic>
              ? data['User'] as Map<String, dynamic>
              : null;
          final userId = user?['Id'] as String?;
          final name = user?['Name'] as String?;

          if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
            throw Exception(
              'Authentication response is missing an access token or user ID.',
            );
          }

          _serverUrl = tryUrl;
          _token = token;
          _userId = userId;
          _username = (name != null && name.isNotEmpty) ? name : username;

          await _secureStorage.write(key: 'serverUrl', value: _serverUrl!);
          await _secureStorage.write(key: 'token', value: _token!);
          await _secureStorage.write(key: 'userId', value: _userId!);
          await _secureStorage.write(key: 'username', value: _username!);

          _isLoading = false;
          notifyListeners();
          return true;
        } catch (e) {
          lastError = e;
          // Continue to next URL
        }
      }

      _isLoading = false;
      notifyListeners();
      if (lastError != null) throw lastError;
      return false;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    // Keep _username and _serverUrl for convenience on next login

    await _secureStorage.delete(key: 'token');
    await _secureStorage.delete(key: 'userId');
    // Keep username and serverUrl in preferences for pre-filling

    notifyListeners();
  }
}
