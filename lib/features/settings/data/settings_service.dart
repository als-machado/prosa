import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../domain/models/app_settings.dart';

class SettingsService {
  static const _key = 'app_settings';
  static const _tokenKey = 'git_token';
  static const _secure = FlutterSecureStorage();

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    var settings = raw == null
        ? const AppSettings()
        : AppSettings.fromMap(jsonDecode(raw) as Map<String, dynamic>);

    final secureToken = await _secure.read(key: _tokenKey);
    final token = secureToken ?? settings.gitToken;
    settings = token != null ? settings.copyWith(gitToken: token) : settings;

    // Migração: versões antigas gravavam o token em texto claro no
    // shared_preferences. Move para o armazenamento seguro e reescreve o
    // JSON sem ele.
    if (raw != null && (jsonDecode(raw) as Map).containsKey('gitToken')) {
      if (token != null) await _secure.write(key: _tokenKey, value: token);
      await prefs.setString(_key, jsonEncode(settings.toMap()));
    }

    return settings;
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toMap()));
    if (settings.gitToken != null && settings.gitToken!.isNotEmpty) {
      await _secure.write(key: _tokenKey, value: settings.gitToken);
    } else {
      await _secure.delete(key: _tokenKey);
    }
  }
}
