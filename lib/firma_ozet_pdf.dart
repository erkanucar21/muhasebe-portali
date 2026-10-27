import 'marka.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart' show bordroKaydet, tl;
import 'firmalar.dart';
import 'secili_firma.dart';

const _aylarAd = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

String _gun(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _dosyaAdi(String s) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosuCGIOSU';
  var r = s;
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
}

Future<List<Map<String, dynamic>>> _oku(Future<dynamic> Function() f) async {
  try {
    final r = await f();
    return (r as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
}

/// Firmanın tek sayfalık durum özeti (PDF). Mükellefle görüşme veya raporlama için.
Future<void> firmaOzetPdfIndir(BuildContext context, Firma f) async {
  final db = Supabase.instance.client;
  final mesaj = ScaffoldMessenger.of(context);
  mesaj.showSnackBar(const SnackBar(content: Text('Özet hazırlanıyor...'), duration: Duration(seconds: 2)));
  try {
    final bugun = DateTime.now();
    final onceki = DateTime(bugun.year, bugun.month - 1, 1);

    final personel = await _oku(() => db.from('personel').select('ad, meslek, giris, cikis, sozlesme_bitis').eq('firma_id', f.id).filter('cikis', 'is', null).order('ad'));
    final kontrol = await _oku(() => db.from('beyanname_kontrol').select('yil, ay, beyanname, durum').eq('firma_id', f.id).gte('yil', onceki.year));
    final notlar = await _oku(() => db.from('ozet_not').select('metin, hatirlatma').eq('firma_id', f.id).eq('tamam', false).order('hatirlatma', ascending: true));
    final arsiv = await _oku(() => db.from('firma_belge').select('ad, gecerlilik').eq('firma_id', f.id).not('gecerlilik', 'is', null).order('gecerlilik'));
    final belgeler = await _oku(() => db.from('belgeler').select('tur, beyanname, yil, donem, yuklenme').eq('firma_id', f.id).order('yuklenme', ascending: false).limit(5));

    double? borc;
    double? aylikUcret;
    if (yoneticiOturumu) {
      final ayar = await _oku(() => db.from('ucret_ayar').select('gecerli, aylik').eq('firma_id', f.id).order('gecerli'));
      final takip = await _oku(() => db.from('ucret_takip').select('yil, ay, tutar, tahsil').eq('firma_id', f.id));
      double ayarBul(int y, int a) {
        double r = 0;
        final d = DateTime(y, a, 1);
        for (final x in ayar) {
          if (!DateTime.parse(x['gecerli'] as String).isAfter(d)) r = (x['aylik'] as num).toDouble();
        }
        return r;
      }

      if (ayar.isNotEmpty) aylikUcret = ayarBul(bugun.year, bugun.month);
      var toplam = 0.0;
      for (final t in takip) {
        final y = (t['yil'] as num).toInt(), a = (t['ay'] as num).toInt();
        if (!DateTime(y, a, 1).isBefore(DateTime(bugun.year, bugun.month, 1))) continue;
        final tutar = t['tutar'] == null ? ayarBul(y, a) : (t['tutar'] as num).toDouble();
        final kalan = tutar - ((t['tahsil'] as num?)?.toDouble() ?? 0);
        if (kalan > 0.5) toplam += kalan;
      }
      borc = toplam;
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()),
    );

    pw.Widget baslik(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
        );
    pw.Widget satir(String e, String d) => d.trim().isEmpty
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 110, child: pw.Text(e, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
              pw.Expanded(child: pw.Text(d, style: const pw.TextStyle(fontSize: 9))),
            ]),
          );
    pw.Widget madde(String t, {PdfColor? renk}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Text('•  $t', style: pw.TextStyle(fontSize: 9, color: renk)),
        );

    String durumAd(int d) => d == 2 ? 'Gönderildi' : (d == 1 ? 'Onaylandı' : 'Bekliyor');
    List<pw.Widget> donemDurum(DateTime d) {
      final r = [for (final k in kontrol) if (k['yil'] == d.year && k['ay'] == d.month) k];
      return [
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text('${_aylarAd[d.month - 1]} ${d.year}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
        if (r.isEmpty) madde('Kayıt girilmemiş', renk: PdfColors.grey700),
        for (final k in r) madde('${k['beyanname']}: ${durumAd((k['durum'] as num).toInt())}'),
      ];
    }

    final sozlesmeler = [for (final p in personel) if (p['sozlesme_bitis'] != null) p];

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (c) => markaUst(),
      footer: (c) => markaAlt(c),
      build: (c) => [
        pw.Text(f.unvan, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
        pw.Text('Firma durum özeti - ${_gun(bugun)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Divider(),
        baslik('Firma bilgileri'),
        satir('Vergi dairesi / no', [f.vergiDairesi, f.vergiNo].where((e) => e.isNotEmpty).join(' / ')),
        satir('TC kimlik no', f.tcNo),
        satir('SGK sicil no', f.sgkSicilNo),
        satir('Faaliyet', [f.faaliyetKodu, f.faaliyetAciklama].where((e) => e.isNotEmpty).join(' - ')),
        satir('Adres', f.adres),
        satir('Telefon', f.telefon),
        satir('Ek yükümlülükler', [if (f.eDefter) 'E-Defter', if (f.gekap) 'GEKAP'].join(', ')),
        if (f.not.trim().isNotEmpty) satir('Firma notu', f.not),
        baslik('Personel (${personel.length} kişi çalışıyor)'),
        if (personel.isEmpty) madde('Çalışan personel yok', renk: PdfColors.grey700),
        for (final p in personel.take(15))
          madde('${p['ad']}${'${p['meslek'] ?? ''}'.isEmpty ? '' : ' - ${p['meslek']}'}'
              '${p['giris'] == null ? '' : '  (giriş ${_gun(DateTime.parse(p['giris'] as String))})'}'),
        if (personel.length > 15) madde('... ve ${personel.length - 15} kişi daha', renk: PdfColors.grey700),
        for (final p in sozlesmeler)
          madde('${p['ad']}: sözleşme bitişi ${_gun(DateTime.parse(p['sozlesme_bitis'] as String))}', renk: PdfColors.deepOrange800),
        baslik('Beyanname durumu'),
        ...donemDurum(bugun),
        ...donemDurum(onceki),
        if (belgeler.isNotEmpty) ...[
          baslik('Son yüklenen belgeler'),
          for (final b in belgeler)
            madde('${b['tur']}${'${b['beyanname'] ?? ''}'.isEmpty ? '' : ' - ${b['beyanname']}'}: ${b['donem']} ${b['yil']}'),
        ],
        if (borc != null) ...[
          baslik('Müşavirlik ücreti'),
          if (aylikUcret != null) satir('Aylık ücret', '${tl(aylikUcret)} TL'),
          satir('Geçmiş aylardan kalan', borc > 0 ? '${tl(borc)} TL' : 'Borç yok'),
        ],
        if (notlar.isNotEmpty) ...[
          baslik('Açık notlar ve hatırlatmalar'),
          for (final n in notlar.take(8))
            madde('${n['hatirlatma'] == null ? '' : '${_gun(DateTime.parse(n['hatirlatma'] as String))}  '}${n['metin']}'),
        ],
        if (arsiv.isNotEmpty) ...[
          baslik('Belge geçerlilik tarihleri'),
          for (final a in arsiv)
            madde('${a['ad']}: ${_gun(DateTime.parse(a['gecerlilik'] as String))}',
                renk: DateTime.parse(a['gecerlilik'] as String).isBefore(bugun) ? PdfColors.red800 : null),
        ],
      ],
    ));

    final Uint8List bytes = await doc.save();
    await bordroKaydet('${_dosyaAdi(f.unvan)}_ozet_${bugun.year}_${bugun.month.toString().padLeft(2, '0')}', bytes, 'pdf');
    mesaj.showSnackBar(const SnackBar(content: Text('Özet PDF indirildi.')));
  } catch (e) {
    mesaj.showSnackBar(SnackBar(content: Text('Özet hazırlanamadı: $e')));
  }
}
