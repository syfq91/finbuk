import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/jellyfin_service.dart';

class AuthProvider with ChangeNotifier {
  final JellyfinService _service = JellyfinService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _serverUrl;
  String? _token;
  String? _userId;
  String? _username;
  bool _isLoading = false;

  String? get serverUrl => _serverUrl;
  String? get token => _token;
  String? get userId => _userId;
  String? get username => _username;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null;

  AuthProvider() {
    _loadFromSecureStorage();
  }

  Future<void> _loadFromSecureStorage() async {
    _serverUrl = await _secureStorage.read(key: 'serverUrl');
    _token = await _secureStorage.read(key: 'token');
    _userId = await _secureStorage.read(key: 'userId');
    _username = await _secureStorage.read(key: 'username');
    notifyListeners();
  }

  Future<bool> login(String url, String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
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

      dynamic lastError;
      for (String tryUrl in urlsToTry) {
        try {
          final data = await _service.authenticate(tryUrl, username, password);

          _serverUrl = tryUrl;
          _token = data['AccessToken'];
          _userId = data['User']['Id'];
          _username = data['User']['Name'];

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
