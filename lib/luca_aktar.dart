import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firmalar.dart';

/// Luca'dan alınan "Müşteri listesi" Excel dosyasından firmaları içe aktarır.
/// Beklenen sütunlar: Uzun Ad, Vergi Dairesi, Vergi No, T.C. Kimlik Numarası, Kuruluş Tarihi.
/// Eşleşme: vergi no, yoksa TC no, yoksa firma adı. Yeni firmalar eklenir, eşleşenler güncellenir.

String _xmlCoz(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&amp;', '&');

String _metin(ArchiveFile? f) => f == null ? '' : utf8.decode(f.content as List<int>, allowMalformed: true);

int _sutunNo(String ref) {
  var n = 0;
  for (final r in ref.runes) {
    if (r < 65 || r > 90) break;
    n = n * 26 + (r - 64);
  }
  return n - 1;
}

/// İlk sayfayı satır satır hücre metinleri olarak okur.
List<List<String>> _xlsxOku(Uint8List bytes) {
  final arsiv = ZipDecoder().decodeBytes(bytes);
  final ortak = <String>[];
  final ortakXml = _metin(arsiv.findFile('xl/sharedStrings.xml'));
  for (final si in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(ortakXml)) {
    final b = StringBuffer();
    for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(si[1]!)) {
      b.write(_xmlCoz(t[1]!));
    }
    ortak.add(b.toString());
  }
  final sayfaAdlari = [
    for (final f in arsiv.files)
      if (f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) f.name
  ]..sort();
  if (sayfaAdlari.isEmpty) throw 'Excel içinde sayfa bulunamadı.';
  final sayfa = _metin(arsiv.findFile(sayfaAdlari.first));
  final satirlar = <List<String>>[];
  for (final satir in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true).allMatches(sayfa)) {
    final hucreler = <int, String>{};
    for (final h in RegExp(r'<c\s([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(satir[1]!)) {
      final oz = h[1]!;
      final ic = h[2] ?? '';
      final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(oz)?[1];
      if (ref == null) continue;
      final tip = RegExp(r'\bt="(\w+)"').firstMatch(oz)?[1];
      var deger = '';
      if (tip == 'inlineStr') {
        deger = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(ic).map((m) => _xmlCoz(m[1]!)).join();
      } else {
        final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(ic)?[1] ?? '';
        deger = tip == 's' ? (ortak.elementAtOrNull(int.tryParse(v) ?? -1) ?? '') : _xmlCoz(v);
      }
      hucreler[_sutunNo(ref)] = deger.trim();
    }
    if (hucreler.isEmpty) continue;
    final en = hucreler.keys.reduce((a, b) => a > b ? a : b);
    satirlar.add([for (var i = 0; i <= en; i++) hucreler[i] ?? '']);
  }
  return satirlar;
}

class _LucaFirma {
  final String unvan, vergiDairesi, vergiNo, tcNo;
  final String? kurulus; // yyyy-aa-gg
  _LucaFirma(this.unvan, this.vergiDairesi, this.vergiNo, this.tcNo, this.kurulus);
}

String _rakamlar(String s, int uzunluk) {
  final r = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (r.isEmpty) return '';
  return r.length < uzunluk ? r.padLeft(uzunluk, '0') : r;
}

String? _tarihCoz(String s) {
  if (s.isEmpty) return null;
  final sayi = double.tryParse(s.replaceAll(',', '.'));
  DateTime? d;
  if (sayi != null && sayi > 1000) {
    d = DateTime.utc(1899, 12, 30).add(Duration(days: sayi.floor()));
  } else {
    final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(s);
    if (m != null) d = DateTime.utc(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }
  if (d == null) return null;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

List<_LucaFirma> _firmalariOku(Uint8List bytes) {
  final satirlar = _xlsxOku(bytes);
  final baslikIdx = satirlar.indexWhere((s) => s.any((h) => h.toLowerCase().contains('uzun ad')));
  if (baslikIdx < 0) throw 'Bu dosya Luca müşteri listesine benzemiyor ("Uzun Ad" sütunu yok).';
  final bas = satirlar[baslikIdx].map((h) => h.toLowerCase()).toList();
  int bul(bool Function(String) f) => bas.indexWhere(f);
  final iAd = bul((h) => h.contains('uzun ad'));
  final iVd = bul((h) => h.contains('vergi dairesi'));
  final iVn = bul((h) => h.contains('vergi no'));
  final iTc = bul((h) => h.contains('kimlik'));
  final iKt = bul((h) => h.contains('kuruluş') || h.contains('kurulus'));
  String al(List<String> s, int i) => (i >= 0 && i < s.length) ? s[i] : '';
  final sonuc = <_LucaFirma>[];
  for (final s in satirlar.skip(baslikIdx + 1)) {
    final ad = al(s, iAd);
    if (ad.isEmpty) continue;
    final vd = al(s, iVd).replaceAll(RegExp(r'\s*VERG[İIiı]\s*DA[İIiı]RES[İIiı]\s*$', caseSensitive: false), '').trim();
    sonuc.add(_LucaFirma(ad, vd, _rakamlar(al(s, iVn), 10), _rakamlar(al(s, iTc), 11), _tarihCoz(al(s, iKt))));
  }
  return sonuc;
}

/// Türkçe harfleri sadeleştirir (İ/I/ı/i hepsi i olur), noktalama ve boşlukları atar; "AŞ." ile "A.Ş" aynı çıkar.
String _kucuk(String s) {
  const harita = {'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', 'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c'};
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(harita[ch] ?? ch.toLowerCase());
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _solSifirsiz(String s) => s.replaceFirst(RegExp(r'^0+'), '');

/// Dosyayı seçtirir, özet gösterir, onaylanırsa firmaları ekler/günceller. Değişiklik olduysa true döner.
Future<bool> lucaFirmalariAktar(BuildContext context) async {
  final db = Supabase.instance.client;
  final mesaj = ScaffoldMessenger.of(context);
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
  if (r == null || r.files.isEmpty || r.files.first.bytes == null) return false;

  List<_LucaFirma> gelen;
  try {
    gelen = _firmalariOku(r.files.first.bytes!);
  } catch (e) {
    mesaj.showSnackBar(SnackBar(content: Text('Dosya okunamadı: $e')));
    return false;
  }
  if (gelen.isEmpty) {
    mesaj.showSnackBar(const SnackBar(content: Text('Dosyada firma bulunamadı.')));
    return false;
  }

  await FirmaDeposu.ornek.yukle();
  final mevcut = FirmaDeposu.ornek.liste;
  Firma? eslestir(_LucaFirma g) {
    // vergi no / TC no çapraz eşleşir (şahıs firmalarında vergi no yerine TC yazılmış olabilir)
    final numaralar = {
      if (g.vergiNo.isNotEmpty) _solSifirsiz(g.vergiNo),
      if (g.tcNo.isNotEmpty) _solSifirsiz(g.tcNo),
    }..remove('');
    for (final f in mevcut) {
      final fn = {_solSifirsiz(f.vergiNo.replaceAll(RegExp(r'[^0-9]'), '')), _solSifirsiz(f.tcNo.replaceAll(RegExp(r'[^0-9]'), ''))}..remove('');
      if (fn.any(numaralar.contains)) return f;
    }
    for (final f in mevcut) {
      if (_kucuk(f.unvan) == _kucuk(g.unvan)) return f;
    }
    return null;
  }

  final yeniler = <_LucaFirma>[];
  final guncellenecek = <(Firma, _LucaFirma)>[];
  for (final g in gelen) {
    final f = eslestir(g);
    if (f == null) {
      yeniler.add(g);
    } else {
      guncellenecek.add((f, g));
    }
  }

  if (!context.mounted) return false;
  final onay = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Luca\'dan firma aktar'),
      content: Text('${gelen.length} firma bulundu.\n\n'
          '• ${yeniler.length} yeni firma eklenecek\n'
          '• ${guncellenecek.length} mevcut firma güncellenecek '
          '(unvan, vergi dairesi, vergi no, TC no, kuruluş tarihi)\n\n'
          'Mevcut firmaların personel, izin, belge ve tüm kayıtlarına dokunulmaz; hiçbir şey silinmez.'
          '${yeniler.isEmpty ? '' : '\n\nYeni eklenecekler (beklemediğin bir firma varsa Vazgeç de, aynı firmanın ikinci kopyası olabilir):\n'
              '${yeniler.take(12).map((g) => '– ${g.unvan}').join('\n')}${yeniler.length > 12 ? '\n… ve ${yeniler.length - 12} firma daha' : ''}'}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aktar')),
      ],
    ),
  );
  if (onay != true) return false;

  try {
    if (yeniler.isNotEmpty) {
      await db.from('firmalar').insert([
        for (final g in yeniler)
          {
            'unvan': g.unvan,
            'vergi_dairesi': g.vergiDairesi,
            'vergi_no': g.vergiNo,
            'tc_no': g.tcNo,
            'kurulus': g.kurulus,
          }
      ]);
    }
    for (final (f, g) in guncellenecek) {
      await db.from('firmalar').update({
        'unvan': g.unvan,
        if (g.vergiDairesi.isNotEmpty) 'vergi_dairesi': g.vergiDairesi,
        if (g.vergiNo.isNotEmpty) 'vergi_no': g.vergiNo,
        if (g.tcNo.isNotEmpty) 'tc_no': g.tcNo,
        if (g.kurulus != null) 'kurulus': g.kurulus,
      }).eq('id', f.id);
    }
    mesaj.showSnackBar(SnackBar(content: Text('${yeniler.length} firma eklendi, ${guncellenecek.length} firma güncellendi.')));
    return true;
  } catch (e) {
    mesaj.showSnackBar(SnackBar(content: Text('Aktarılamadı: $e')));
    return false;
  }
}

List<List<String>> xlsxSatirlari(Uint8List bytes) => _xlsxOku(bytes);
String firmaAdiSadelestir(String s) => _kucuk(s);
String solSifirsiz(String s) => _solSifirsiz(s);
