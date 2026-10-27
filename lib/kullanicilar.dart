import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ayarlar.dart';
import 'hesap_islem.dart';
import 'firmalar.dart';
import 'main.dart';

class KullanicilarSayfasi extends StatefulWidget {
  const KullanicilarSayfasi({super.key});
  @override
  State<KullanicilarSayfasi> createState() => _KullanicilarSayfasiState();
}

class _KullanicilarSayfasiState extends State<KullanicilarSayfasi> {
  SupabaseClient get _db => Supabase.instance.client;
  List<Map<String, dynamic>> _liste = [];
  bool _yukleniyor = true;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await _db.from('profiller').select().eq('rol', 'yardimci').order('giris_adi');
      _liste = List<Map<String, dynamic>>.from(r);
      _hata = null;
    } catch (e) {
      _hata = 'Liste alınamadı: $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Önce doğrudan kayıt adresini dener; kayıt kapalıysa sunucu işlevini (hesap-olustur) dener.
  /// Hata mesajları hangi adımın başarısız olduğunu belirtir.
  Future<bool> _hesapOlusturYedekli(String eposta, String sifre) async {
    String adim1;
    try {
      final r = await http.post(
        Uri.parse('$supabaseUrl/auth/v1/signup'),
        headers: {'apikey': supabaseAnonKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'email': eposta, 'password': sifre}),
      );
      if (r.statusCode < 400) return true;
      var mesaj = 'Kayıt adresi ${r.statusCode} döndürdü';
      try {
        final m = jsonDecode(r.body);
        mesaj = (m['msg'] ?? m['error_description'] ?? m['message'] ?? mesaj).toString();
      } catch (_) {}
      if (mesaj.toLowerCase().contains('already')) return false;
      adim1 = mesaj;
    } catch (e) {
      adim1 = 'Kayıt adresine bağlanılamadı: $e';
    }
    try {
      return await authHesapOlustur(eposta, sifre);
    } catch (e) {
      throw 'Adım 1 (kayıt adresi): $adim1\nAdım 2 (hesap-olustur işlevi): $e';
    }
  }

  Future<void> _hesapAc(String girisAdi, String sifre, String ad, List<String> izinler) async {
    final eposta = girisEposta(girisAdi);
    final yeniHesap = await _hesapOlusturYedekli(eposta, sifre);
    if (!yeniHesap) throw 'Bu giriş adı zaten kayıtlı.';
    await _db.rpc('yardimci_bagla', params: {
      'p_eposta': eposta,
      'p_giris_adi': girisAdi.trim(),
      'p_ad': ad.trim(),
      'p_izinler': izinler,
    });
  }

  Future<void> _form({Map<String, dynamic>? mevcut}) async {
    final yeni = mevcut == null;
    final ad = TextEditingController(text: (mevcut?['gorunen_ad'] ?? '') as String);
    final giris = TextEditingController(text: (mevcut?['giris_adi'] ?? '') as String);
    final sifre = TextEditingController();
    final secili = <String>{...((mevcut?['izinler'] ?? const []) as List).map((e) => e.toString())};
    String? hata;
    var kaydediliyor = false;
    final tamam = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(yeni ? 'Yardımcı kullanıcı ekle (v2)' : 'Yetkileri düzenle'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: ad, decoration: const InputDecoration(labelText: 'Adı (örn. Ayşe stajyer)')),
                const SizedBox(height: 10),
                if (yeni) ...[
                  TextField(controller: giris, decoration: const InputDecoration(labelText: 'Giriş adı')),
                  const SizedBox(height: 10),
                  TextField(controller: sifre, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre (en az 8 karakter)')),
                ] else
                  Text('Giriş adı: ${giris.text}', style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 14),
                const Text('Görebileceği bölümler', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final b in yardimciBolumleri)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(b),
                    value: secili.contains(b),
                    onChanged: (v) => setD(() => v == true ? secili.add(b) : secili.remove(b)),
                  ),
                const Text('Ücret takibi, yedekler, duyurular, kullanıcılar ve parametreler yalnızca yöneticidedir.',
                    style: TextStyle(fontSize: 12, color: Colors.black87)),
                if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: kaydediliyor ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: kaydediliyor
                  ? null
                  : () async {
                      if (ad.text.trim().isEmpty) {
                        setD(() => hata = 'Ad yaz');
                        return;
                      }
                      if (yeni) {
                        if (giris.text.trim().isEmpty || girisEposta(giris.text).startsWith('@')) {
                          setD(() => hata = 'Giriş adında en az bir harf veya rakam olmalı');
                          return;
                        }
                        if (girisEposta(giris.text) == 'admin@muhasebeportal.app') {
                          setD(() => hata = 'Bu giriş adı kullanılamaz');
                          return;
                        }
                        if (sifre.text.length < 8) {
                          setD(() => hata = 'Şifre en az 8 karakter olmalı');
                          return;
                        }
                      }
                      setD(() { kaydediliyor = true; hata = null; });
                      try {
                        if (yeni) {
                          await _hesapAc(giris.text, sifre.text, ad.text, secili.toList());
                        } else {
                          await _db.from('profiller').update({'gorunen_ad': ad.text.trim(), 'izinler': secili.toList()}).eq('user_id', mevcut['user_id']);
                        }
                        if (c.mounted) Navigator.pop(c, true);
                      } catch (e) {
                        setD(() { kaydediliyor = false; hata = '$e'; });
                      }
                    },
              child: Text(kaydediliyor ? 'Kaydediliyor...' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (tamam == true) {
      _mesaj(yeni ? 'Kullanıcı eklendi.' : 'Kaydedildi.');
      _yukle();
    }
  }

  Future<void> _sifreDegistir(Map<String, dynamic> p) async {
    final k = TextEditingController();
    final yeni = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Yeni şifre: ${p['giris_adi']}'),
        content: TextField(controller: k, obscureText: true, decoration: const InputDecoration(labelText: 'Yeni şifre (en az 8 karakter)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, k.text), child: const Text('Kaydet')),
        ],
      ),
    );
    if (yeni == null) return;
    if (yeni.length < 8) {
      _mesaj('Şifre en az 8 karakter olmalı.');
      return;
    }
    try {
      await _db.rpc('yardimci_sifre', params: {'p_user_id': p['user_id'], 'p_sifre': yeni});
      _mesaj('Şifre değiştirildi.');
    } catch (e) {
      _mesaj('Şifre değiştirilemedi: $e');
    }
  }

  Future<void> _aktifDegistir(Map<String, dynamic> p) async {
    try {
      await _db.from('profiller').update({'aktif': !(p['aktif'] == true)}).eq('user_id', p['user_id']);
      _yukle();
    } catch (e) {
      _mesaj('Değiştirilemedi: $e');
    }
  }

  Future<void> _sil(Map<String, dynamic> p) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kullanıcı silinsin mi?'),
        content: Text('${p['giris_adi']} hesabı tamamen silinir. Yaptığı kayıtlar silinmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _db.rpc('yardimci_sil', params: {'p_user_id': p['user_id']});
      _yukle();
    } catch (e) {
      _mesaj('Silinemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Kullanıcı ekle'),
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : _hata != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_hata!)))
              : _liste.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Henüz yardımcı kullanıcı yok. Çalışanın veya stajyerin sadece seçtiğin bölümleri görmesi için ekle.', textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      children: [
                        for (final p in _liste)
                          Card(
                            child: ListTile(
                              leading: Icon(p['aktif'] == true ? Icons.person_outline : Icons.person_off_outlined),
                              title: Text(((p['gorunen_ad'] ?? '') as String).isEmpty ? '${p['giris_adi']}' : '${p['gorunen_ad']}'),
                              subtitle: Text('Giriş: ${p['giris_adi']}  |  ${((p['izinler'] ?? const []) as List).isEmpty ? 'Bölüm yok' : ((p['izinler'] as List).join(', '))}${p['aktif'] == true ? '' : '  |  Kapalı'}'),
                              trailing: PopupMenuButton<int>(
                                onSelected: (v) {
                                  if (v == 1) _form(mevcut: p);
                                  if (v == 2) _sifreDegistir(p);
                                  if (v == 3) _aktifDegistir(p);
                                  if (v == 4) _sil(p);
                                },
                                itemBuilder: (c) => [
                                  const PopupMenuItem(value: 1, child: Text('Yetkileri düzenle')),
                                  const PopupMenuItem(value: 2, child: Text('Şifre değiştir')),
                                  PopupMenuItem(value: 3, child: Text(p['aktif'] == true ? 'Girişi kapat' : 'Girişi aç')),
                                  const PopupMenuItem(value: 4, child: Text('Sil')),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}
