import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bordro_cikti.dart' show bordroKaydet;
import 'firmalar.dart';
import 'luca_aktar.dart';
import 'yedek.dart' show xlsxYaz;

class _Satir {
  final String ad, vergiNo, telefon;
  final double? ucret;
  _Satir(this.ad, this.vergiNo, this.telefon, this.ucret);
}

class _Eslesme {
  final Firma firma;
  final _Satir satir;
  final String? yeniTelefon;
  final double? yeniUcret;
  _Eslesme(this.firma, this.satir, this.yeniTelefon, this.yeniUcret);
}

List<String> _csvSatir(String s, String ayirac) {
  final r = <String>[];
  final b = StringBuffer();
  var tirnak = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') {
      if (tirnak && i + 1 < s.length && s[i + 1] == '"') {
        b.write('"');
        i++;
      } else {
        tirnak = !tirnak;
      }
    } else if (c == ayirac && !tirnak) {
      r.add(b.toString().trim());
      b.clear();
    } else {
      b.write(c);
    }
  }
  r.add(b.toString().trim());
  return r;
}

List<List<String>> _csvOku(Uint8List bytes) {
  var m = utf8.decode(bytes, allowMalformed: true);
  if (m.startsWith('﻿')) m = m.substring(1);
  final satirlar = m.split(RegExp(r'\r?\n')).where((e) => e.trim().isNotEmpty).toList();
  if (satirlar.isEmpty) return [];
  final ayirac = ';'.allMatches(satirlar.first).length >= ','.allMatches(satirlar.first).length && satirlar.first.contains(';') ? ';' : ',';
  return [for (final s in satirlar) _csvSatir(s, ayirac)];
}

double? _tutarCoz(String s) {
  var t = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', '');
  }
  return double.tryParse(t);
}

String _telefonTemizle(String s) {
  var t = s.replaceAll(RegExp(r'[^0-9+]'), '');
  if (t.isEmpty) return '';
  if (!t.startsWith('+') && t.length == 10 && t.startsWith('5')) t = '0$t';
  return t;
}

List<_Satir> _oku(Uint8List bytes, String ad) {
  final satirlar = ad.toLowerCase().endsWith('.csv') ? _csvOku(bytes) : xlsxSatirlari(bytes);
  var bi = -1;
  for (var i = 0; i < satirlar.length && i < 15; i++) {
    final h = satirlar[i].map(firmaAdiSadelestir).toList();
    if (h.any((e) => e.contains('firma') || e.contains('unvan') || e.contains('ad'))) {
      bi = i;
      break;
    }
  }
  if (bi < 0) throw 'Başlık satırı bulunamadı. İlk satırda "Firma" sütunu olmalı.';
  final bas = satirlar[bi].map(firmaAdiSadelestir).toList();
  int bul(bool Function(String) f) => bas.indexWhere(f);
  final iAd = bul((h) => h.contains('firma') || h.contains('unvan') || h == 'ad');
  final iVn = bul((h) => h.contains('vergi') && (h.contains('no') || h.contains('numara')));
  final iTel = bul((h) => h.contains('telefon') || h.contains('gsm') || h == 'tel');
  final iUc = bul((h) => h.contains('ucret') || h.contains('aylik'));
  if (iTel < 0 && iUc < 0) throw 'Telefon veya ücret sütunu bulunamadı.';
  String al(List<String> s, int i) => (i >= 0 && i < s.length) ? s[i] : '';
  return [
    for (final s in satirlar.skip(bi + 1))
      if (al(s, iAd).isNotEmpty || al(s, iVn).isNotEmpty)
        _Satir(al(s, iAd), al(s, iVn).replaceAll(RegExp(r'[^0-9]'), ''), _telefonTemizle(al(s, iTel)), _tutarCoz(al(s, iUc))),
  ];
}

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

/// Excel/CSV dosyasından firmaların telefon ve aylık ücretlerini toplu günceller. Değişiklik olduysa true döner.
Future<bool> topluAktar(BuildContext context) async {
  final db = Supabase.instance.client;
  final mesaj = ScaffoldMessenger.of(context);
  await FirmaDeposu.ornek.yukle();
  final firmalar = FirmaDeposu.ornek.liste;
  if (!context.mounted) return false;

  final secim = await showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Toplu aktar: telefon ve ücret'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text('Excel (.xlsx) veya CSV dosyası. İlk satırda başlıklar olmalı: Firma, Vergi No (isteğe bağlı), Telefon, Aylık Ücret. '
              'Firmalar vergi no veya firma adıyla eşleşir. Boş bırakılan hücreler değiştirilmez.'),
        ),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 1), child: const Text('Şablon indir (firmalarla dolu)')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 2), child: const Text('Dosya seç ve aktar')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 0), child: const Text('Vazgeç')),
      ],
    ),
  );
  if (secim == null || secim == 0) return false;

  if (secim == 1) {
    final satirlar = <List<dynamic>>[
      for (final f in firmalar) [f.unvan, f.vergiNo.isNotEmpty ? f.vergiNo : f.tcNo, f.telefon, ''],
    ];
    final bytes = xlsxYaz([('Toplu aktar', ['Firma', 'Vergi No', 'Telefon', 'Aylık Ücret'], satirlar)]);
    await bordroKaydet('toplu_aktar_sablon', bytes, 'xlsx');
    mesaj.showSnackBar(const SnackBar(content: Text('Şablon indirildi. Doldurup tekrar "Toplu aktar"dan yükle.')));
    return false;
  }

  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv'], withData: true);
  if (r == null || r.files.isEmpty || r.files.first.bytes == null) return false;
  List<_Satir> gelen;
  try {
    gelen = _oku(r.files.first.bytes!, r.files.first.name);
  } catch (e) {
    mesaj.showSnackBar(SnackBar(content: Text('Dosya okunamadı: $e')));
    return false;
  }
  if (gelen.isEmpty) {
    mesaj.showSnackBar(const SnackBar(content: Text('Dosyada satır bulunamadı.')));
    return false;
  }

  Firma? bul(_Satir g) {
    if (g.vergiNo.isNotEmpty) {
      final n = solSifirsiz(g.vergiNo);
      for (final f in firmalar) {
        final a = solSifirsiz(f.vergiNo.replaceAll(RegExp(r'[^0-9]'), ''));
        final b = solSifirsiz(f.tcNo.replaceAll(RegExp(r'[^0-9]'), ''));
        if (n.isNotEmpty && (a == n || b == n)) return f;
      }
    }
    if (g.ad.isNotEmpty) {
      final k = firmaAdiSadelestir(g.ad);
      for (final f in firmalar) {
        if (firmaAdiSadelestir(f.unvan) == k) return f;
      }
    }
    return null;
  }

  final ayarlar = await db.from('ucret_ayar').select();
  double? mevcutUcret(int firmaId, DateTime ay) {
    DateTime? enYeni;
    double? t;
    for (final a in ayarlar) {
      if (a['firma_id'] != firmaId) continue;
      final d = DateTime.parse(a['gecerli'] as String);
      if (d.isAfter(ay)) continue;
      if (enYeni == null || d.isAfter(enYeni)) {
        enYeni = d;
        t = (a['aylik'] as num).toDouble();
      }
    }
    return t;
  }

  var yil = DateTime.now().year, ay = DateTime.now().month;
  var uzerineYaz = false;
  if (!context.mounted) return false;
  final onay = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setD) {
      final bulunamayan = <_Satir>[];
      final liste = <_Eslesme>[];
      for (final g in gelen) {
        final f = bul(g);
        if (f == null) {
          bulunamayan.add(g);
          continue;
        }
        String? tel;
        if (g.telefon.isNotEmpty && g.telefon != f.telefon && (uzerineYaz || f.telefon.isEmpty)) tel = g.telefon;
        double? uc;
        if (g.ucret != null && g.ucret! > 0 && g.ucret != mevcutUcret(f.id, DateTime(yil, ay, 1))) uc = g.ucret;
        if (tel != null || uc != null) liste.add(_Eslesme(f, g, tel, uc));
      }
      final telSay = liste.where((e) => e.yeniTelefon != null).length;
      final ucSay = liste.where((e) => e.yeniUcret != null).length;
      _sonListe = liste;
      return AlertDialog(
        title: const Text('Toplu aktar: önizleme'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${gelen.length} satır okundu.\n'
                  '• $telSay firmanın telefonu güncellenecek\n'
                  '• $ucSay firmanın aylık ücreti güncellenecek\n'
                  '• ${bulunamayan.length} satır hiçbir firmayla eşleşmedi (atlanır)'),
              const SizedBox(height: 12),
              const Text('Ücretler şu aydan itibaren geçerli olur:', style: TextStyle(fontWeight: FontWeight.w600)),
              Row(children: [
                DropdownButton<int>(
                  value: ay,
                  items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(_aylar[i - 1]))],
                  onChanged: (v) => setD(() => ay = v ?? ay),
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: yil,
                  items: [for (var y = DateTime.now().year - 3; y <= DateTime.now().year + 1; y++) DropdownMenuItem(value: y, child: Text('$y'))],
                  onChanged: (v) => setD(() => yil = v ?? yil),
                ),
              ]),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Dolu telefonların üzerine de yaz'),
                value: uzerineYaz,
                onChanged: (v) => setD(() => uzerineYaz = v == true),
              ),
              if (liste.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Değişecekler:', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final e in liste.take(10))
                  Text('– ${e.firma.unvan}${e.yeniTelefon != null ? '  tel: ${e.yeniTelefon}' : ''}${e.yeniUcret != null ? '  ücret: ${e.yeniUcret!.toStringAsFixed(2)}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                if (liste.length > 10) Text('… ve ${liste.length - 10} firma daha', style: const TextStyle(fontSize: 12)),
              ],
              if (bulunamayan.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Eşleşmeyenler:', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final g in bulunamayan.take(8)) Text('– ${g.ad.isEmpty ? g.vergiNo : g.ad}', style: const TextStyle(fontSize: 12)),
                if (bulunamayan.length > 8) Text('… ve ${bulunamayan.length - 8} satır daha', style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 8),
              const Text('Hiçbir kayıt silinmez. Ücret geçmişi korunur.', style: TextStyle(fontSize: 12, color: Colors.black87)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: liste.isEmpty ? null : () => Navigator.pop(c, true), child: const Text('Aktar')),
        ],
      );
    }),
  );
  if (onay != true) return false;

  try {
    final gecerli = '$yil-${ay.toString().padLeft(2, '0')}-01';
    for (final e in _sonListe) {
      if (e.yeniTelefon != null) {
        await db.from('firmalar').update({'telefon': e.yeniTelefon}).eq('id', e.firma.id);
      }
      if (e.yeniUcret != null) {
        await db.from('ucret_ayar').upsert({'firma_id': e.firma.id, 'gecerli': gecerli, 'aylik': e.yeniUcret}, onConflict: 'firma_id,gecerli');
      }
    }
    await FirmaDeposu.ornek.yukle();
    mesaj.showSnackBar(SnackBar(content: Text('${_sonListe.length} firma güncellendi.')));
    return true;
  } catch (e) {
    mesaj.showSnackBar(SnackBar(content: Text('Aktarılamadı: $e')));
    return false;
  }
}

List<_Eslesme> _sonListe = [];
