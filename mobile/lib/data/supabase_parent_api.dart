import 'package:supabase_flutter/supabase_flutter.dart';

import 'parent_portal.dart';

/// [ParentApi] over the parent_* RPCs of sql/0018. They are callable with
/// the anon key alone; the parent's token travels as a parameter.
class SupabaseParentApi implements ParentApi {
  SupabaseClient get _sb => Supabase.instance.client;

  @override
  Future<ParentSession> login(String phone, String password) async {
    final dynamic res;
    try {
      res = await _sb.rpc('parent_login', params: {'p_phone': phone, 'p_password': password, 'p_client': 'app'});
    } on PostgrestException catch (e) {
      throw ParentLoginFailed(e.message);
    }
    final m = Map<String, dynamic>.from(res as Map);
    if (m['error'] != null) throw ParentLoginFailed('${m['error']}');
    final parent = Map<String, dynamic>.from((m['parent'] as Map?) ?? const {});
    return ParentSession(
      token: m['token'] as String,
      name: parent['name'] as String?,
      phone: (parent['phone'] as String?) ?? phone,
    );
  }

  @override
  Future<ParentPortal> fetchPortal(String token) async {
    try {
      final res = await _sb.rpc('parent_portal', params: {'p_token': token});
      return ParentPortal(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      if (e.message == 'session_expired') throw ParentSessionExpired();
      rethrow;
    }
  }

  @override
  Future<void> logout(String token) async {
    await _sb.rpc('parent_logout', params: {'p_token': token});
  }
}
