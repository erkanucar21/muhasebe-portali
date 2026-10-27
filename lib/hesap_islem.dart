import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ayarlar.dart';

/// Giriş hesabı (auth kullanıcısı) oluşturur. Önce sunucudaki "hesap-olustur" işlevini dener,
/// işlev henüz yayınlanmamışsa eski kayıt (signup) adresine düşer.
/// Dönüş: true = yeni hesap açıldı, false = bu e-posta zaten kayıtlıydı.
Future<bool> authHesapOlustur(String eposta, String sifre) async {
  try {
    await Supabase.instance.client.functions.invoke('hesap-olustur', body: {'email': eposta, 'password': sifre});
    return true;
  } on FunctionException catch (e) {
    if (e.status == 409) return false;
    if (e.status != 404) {
      final d = e.details;
      final mesaj = d is Map ? '${d['error'] ?? d['message'] ?? ''}' : '${d ?? ''}';
      throw mesaj.isEmpty ? 'Hesap oluşturulamadı (${e.status})' : mesaj;
    }
    // 404: işlev kurulmamış, aşağıdaki eski yola devam
  } catch (e) {
    if (e is String) rethrow;
    // "Failed to fetch": işlev yayınlanmamış veya erişilemiyor, aşağıdaki eski yola devam
  }
  final r = await http.post(
    Uri.parse('$supabaseUrl/auth/v1/signup'),
    headers: {'apikey': supabaseAnonKey, 'Content-Type': 'application/json'},
    body: jsonEncode({'email': eposta, 'password': sifre}),
  );
  if (r.statusCode >= 400) {
    var mesaj = 'Hesap oluşturulamadı (${r.statusCode})';
    try {
      final m = jsonDecode(r.body);
      mesaj = (m['msg'] ?? m['error_description'] ?? m['message'] ?? mesaj).toString();
    } catch (_) {}
    if (mesaj.toLowerCase().contains('already')) return false;
    throw mesaj;
  }
  return true;
}
