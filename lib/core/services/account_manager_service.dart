import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SavedAccount {
  final String email;
  final String password;
  final String label; // Ej. "Administrador", "Repartidor", "Cliente"

  SavedAccount({
    required this.email,
    required this.password,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'label': label,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        email: json['email'] ?? '',
        password: json['password'] ?? '',
        label: json['label'] ?? '',
      );
}

class AccountManagerService {
  static const _key = 'saved_accounts_list';

  static Future<List<SavedAccount>> getSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List decoded = jsonDecode(jsonString);
      return decoded.map((e) => SavedAccount.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAccount(SavedAccount account) async {
    final accounts = await getSavedAccounts();
    // Evitar duplicados por correo
    accounts.removeWhere((a) => a.email.toLowerCase() == account.email.toLowerCase());
    accounts.insert(0, account);

    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  static Future<void> removeAccount(String email) async {
    final accounts = await getSavedAccounts();
    accounts.removeWhere((a) => a.email.toLowerCase() == email.toLowerCase());

    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}