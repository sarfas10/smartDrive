import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const _kUserId = 'userId';
  static const _kRole = 'role';     // 'student' | 'instructor' | ...
  static const _kStatus = 'status'; // 'active' | 'pending' | ...

  Future<void> save({required String userId, required String role, required String status}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUserId, userId);
    await sp.setString(_kRole, role);
    await sp.setString(_kStatus, status);
  }

  Future<({String? userId, String? role, String? status})> read() async {
    final sp = await SharedPreferences.getInstance();
    return (userId: sp.getString(_kUserId), role: sp.getString(_kRole), status: sp.getString(_kStatus));
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kUserId);
    await sp.remove(_kRole);
    await sp.remove(_kStatus);
  }
}
