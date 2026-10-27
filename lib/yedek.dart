import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart' show bordroKaydet;

/// Tüm firma, personel, izin ve kontrol listesi verisini tek bir Excel dosyasında (çok sayfalı) indirir.

String _kacis(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _sutunHarf(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _sayfaXml(List<String> baslik, List<List<dynamic>> satirlar, bool para) {
  final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">${para ? '<sheetFormatPr defaultRowHeight="18" defaultColWidth="28"/>' : ''}<sheetData>');
  void satir(int no, List<dynamic> hucreler, bool kalin) {
    b.write('<row r="$no">');
    for (var i = 0; i < hucreler.length; i++) {
      final ref = '${_sutunHarf(i)}$no';
      final v = hucreler[i];
      final stil = kalin ? ' s="1"' : (para && v is num ? ' s="2"' : '');
      if (v == null || (v is String && v.isEmpty)) continue;
      if (v is num) {
        b.write('<c r="$ref"$stil><v>$v</v></c>');
      } else {
        b.write('<c r="$ref"$stil t="inlineStr"><is><t xml:space="preserve">${_kacis('$v')}</t></is></c>');
      }
    }
    b.write('</row>');
  }

  satir(1, baslik, true);
  for (var i = 0; i < satirlar.length; i++) {
    satir(i + 2, satirlar[i], false);
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

/// [para] true ise sayılar 1.234,56 biçiminde gösterilir ve sütunlar geniş olur.
Uint8List xlsxYaz(List<(String, List<String>, List<List<dynamic>>)> sayfalar, {bool para = false}) {
  final arsiv = Archive();
  void ekle(String ad, String icerik) {
    final b = utf8.encode(icerik);
    arsiv.addFile(ArchiveFile(ad, b.length, b));
  }

  const xmlBas = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  final tipler = StringBuffer('$xmlBas<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  final kitap = StringBuffer(
      '$xmlBas<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>');
  final bag = StringBuffer('$xmlBas<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (var i = 0; i < sayfalar.length; i++) {
    final n = i + 1;
    tipler.write(
        '<Override PartName="/xl/worksheets/sheet$n.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    kitap.write('<sheet name="${_kacis(sayfalar[i].$1)}" sheetId="$n" r:id="rId$n"/>');
    bag.write(
        '<Relationship Id="rId$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$n.xml"/>');
    ekle('xl/worksheets/sheet$n.xml', _sayfaXml(sayfalar[i].$2, sayfalar[i].$3, para));
  }
  tipler.write('</Types>');
  kitap.write('</sheets></workbook>');
  bag.write(
      '<Relationship Id="rId${sayfalar.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
  const stiller = '$xmlBas<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><name val="Arial"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/></cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
  ekle('[Content_Types].xml', tipler.toString());
  ekle('_rels/.rels',
      '$xmlBas<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  ekle('xl/workbook.xml', kitap.toString());
  ekle('xl/_rels/workbook.xml.rels', bag.toString());
  ekle('xl/styles.xml', stiller);
  return Uint8List.fromList(ZipEncoder().encode(arsiv)!);
}

/// Satır listesinden sayfa üretir (sütunlar satırlardan toplanır).
(String, List<String>, List<List<dynamic>>) sayfaYap(String sayfa, List<Map<String, dynamic>> satirlar) {
  final sutunlar = <String>[];
  for (final s in satirlar) {
    for (final k in s.keys) {
      if (!sutunlar.contains(k)) sutunlar.add(k);
    }
  }
  return (
    sayfa,
    sutunlar,
    [
      for (final s in satirlar) [for (final k in sutunlar) s[k] is num ? s[k] : (s[k] ?? '').toString()]
    ]
  );
}

/// Bir tablonun tüm satırlarını sayfa halinde getirir.
Future<(String, List<String>, List<List<dynamic>>)> _tablo(String sayfa, String tablo) async {
  final db = Supabase.instance.client;
  final satirlar = <Map<String, dynamic>>[];
  var bas = 0;
  while (true) {
    final parca = await db.from(tablo).select().range(bas, bas + 999);
    satirlar.addAll(parca.cast<Map<String, dynamic>>());
    if (parca.length < 1000) break;
    bas += 1000;
  }
  return sayfaYap(sayfa, satirlar);
}

/// Sunucuda saklanan bir yedeği (supabase_yedek.sql) Excel olarak indirir.
Future<void> arsivYedegiIndir(int id) async {
  final db = Supabase.instance.client;
  final satir = await db.from('yedek_arsiv').select('tarih, veri').eq('id', id).single();
  final veri = Map<String, dynamic>.from(satir['veri'] as Map);
  final sayfalar = <(String, List<String>, List<List<dynamic>>)>[];
  for (final e in veri.entries) {
    final liste = (e.value as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final ad = e.key.replaceAll('_', ' ');
    sayfalar.add(sayfaYap(ad.length > 31 ? ad.substring(0, 31) : ad, liste));
  }
  final t = DateTime.parse(satir['tarih'] as String).toLocal();
  final adi =
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  await bordroKaydet('muhasebe_arsiv_yedek_$adi', xlsxYaz(sayfalar), 'xlsx');
}

/// Yedeği indirir; kaç tablo yazıldığını döndürür.
Future<int> yedekAl() async {
  final sayfalar = <(String, List<String>, List<List<dynamic>>)>[];
  for (final (ad, tablo) in [
    ('Firmalar', 'firmalar'),
    ('Personel', 'personel'),
    ('Izin kayitlari', 'izin_kayitlari'),
    ('Beyanname kontrol', 'beyanname_kontrol'),
    ('Belgeler', 'belgeler'),
  ]) {
    try {
      sayfalar.add(await _tablo(ad, tablo));
    } catch (_) {
      // tablo yoksa veya erişilemiyorsa o sayfa atlanır
    }
  }
  final n = DateTime.now();
  final tarih = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  await bordroKaydet('muhasebe_yedek_$tarih', xlsxYaz(sayfalar), 'xlsx');
  return sayfalar.length;
}
