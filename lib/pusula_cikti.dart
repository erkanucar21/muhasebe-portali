import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bordro_cikti.dart' show bordroKaydet, tl;
import 'yedek.dart' show xlsxYaz;

/// Firmanın aylık hesap listesi (ödeme kalemleri). Resim, PDF, Excel ve WhatsApp çıktısı buradan üretilir.
class PusulaVeri {
  final String firma;
  final String donem; // örn. "Ekim 2026"
  final double gecenAy; // 0 ise boş gösterilir
  final List<(String, double)> kalemler; // (ad, tutar); tutar 0 ise boş gösterilir
  const PusulaVeri({required this.firma, required this.donem, required this.gecenAy, required this.kalemler});

  double get toplam => gecenAy + kalemler.fold(0.0, (t, k) => t + k.$2);

  /// (sol, sağ) satırlar: başlık hariç, TOPLAM dahil.
  List<(String, String)> get satirlar => [
        ('GEÇEN AY', gecenAy == 0 ? '' : tl(gecenAy)),
        for (final k in kalemler) (k.$1, k.$2 == 0 ? '' : tl(k.$2)),
        ('TOPLAM', tl(toplam)),
      ];

  String get dosyaAdi {
    final temiz = firma.replaceAll(RegExp(r'[^A-Za-z0-9ĞÜŞİÖÇğüşıöç ]'), '').trim().replaceAll(' ', '_');
    return 'hesap_listesi_${temiz.isEmpty ? 'firma' : temiz}_${donem.replaceAll(' ', '_')}';
  }

  String get metin {
    final b = StringBuffer('$firma\n$donem\n\n');
    for (final s in satirlar) {
      if (s.$2.isEmpty) continue;
      b.writeln('${s.$1}: ${s.$2}');
    }
    return b.toString().trimRight();
  }
}

// ================================================================ RESİM (PNG)

Future<Uint8List> pusulaPng(PusulaVeri v) async {
  const olcek = 2.5;
  const w = 540.0, sol = 290.0, satirH = 36.0, baslikH = 56.0;
  final satirlar = v.satirlar;
  final h = baslikH + satirH * satirlar.length;
  final kayit = ui.PictureRecorder();
  final c = ui.Canvas(kayit);
  c.scale(olcek);
  c.drawRect(const Rect.fromLTWH(0, 0, w, 4000), ui.Paint()..color = const Color(0xFFFFFFFF));
  final cizgi = ui.Paint()
    ..color = const Color(0xFF000000)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1;

  void yaz(String t, double x, double y, double genislik, double yukseklik,
      {bool kalin = false, bool sagaYasla = false, double boyut = 15}) {
    if (t.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: const Color(0xFF000000), fontSize: boyut, fontWeight: kalin ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: genislik - 20);
    final dx = sagaYasla ? x + genislik - 10 - tp.width : x + 10;
    tp.paint(c, Offset(dx, y + (yukseklik - tp.height) / 2));
  }

  // başlık
  c.drawRect(const Rect.fromLTWH(0, 0, w, baslikH), ui.Paint()..color = const Color(0xFFF2F2F2));
  c.drawRect(const Rect.fromLTWH(0, 0, w, baslikH), cizgi);
  c.drawLine(const Offset(sol, 0), const Offset(sol, baslikH), cizgi);
  yaz('TÜRÜ', 0, 0, sol, baslikH, kalin: true);
  final tp = TextPainter(
    text: TextSpan(children: [
      TextSpan(text: '${v.firma}\n', style: const TextStyle(color: Color(0xFF000000), fontSize: 15, fontWeight: FontWeight.w700)),
      TextSpan(text: v.donem, style: const TextStyle(color: Color(0xFF444444), fontSize: 12)),
    ]),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: w - sol - 20);
  tp.paint(c, Offset(sol + 10, (baslikH - tp.height) / 2));

  var y = baslikH;
  for (var i = 0; i < satirlar.length; i++) {
    final son = i == satirlar.length - 1;
    if (son) c.drawRect(Rect.fromLTWH(0, y, w, satirH), ui.Paint()..color = const Color(0xFFF2F2F2));
    c.drawRect(Rect.fromLTWH(0, y, w, satirH), cizgi);
    c.drawLine(Offset(sol, y), Offset(sol, y + satirH), cizgi);
    yaz(satirlar[i].$1, 0, y, sol, satirH, kalin: son);
    yaz(satirlar[i].$2, sol, y, w - sol, satirH, kalin: son, sagaYasla: true);
    y += satirH;
  }

  final resim = await kayit.endRecording().toImage((w * olcek).round(), (h * olcek).round());
  final veri = await resim.toByteData(format: ui.ImageByteFormat.png);
  return veri!.buffer.asUint8List();
}

// ================================================================ PDF

Future<Uint8List> pusulaPdf(PusulaVeri v) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
    ),
  );
  pw.Widget hucre(String t, {bool kalin = false, bool sag = false, double boyut = 11, PdfColor? zemin}) => pw.Container(
        color: zemin,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        alignment: sag ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(t, style: pw.TextStyle(fontSize: boyut, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
  const gri = PdfColor.fromInt(0xFFF2F2F2);
  final satirlar = v.satirlar;
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(28),
    build: (c) => pw.Table(
      border: pw.TableBorder.all(width: 0.8),
      columnWidths: const {0: pw.FlexColumnWidth(1.1), 1: pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(children: [
          hucre('TÜRÜ', kalin: true, zemin: gri),
          pw.Container(
            color: gri,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(v.firma, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(v.donem, style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
        ]),
        for (var i = 0; i < satirlar.length; i++)
          pw.TableRow(children: [
            hucre(satirlar[i].$1, kalin: i == satirlar.length - 1, zemin: i == satirlar.length - 1 ? gri : null),
            hucre(satirlar[i].$2, kalin: i == satirlar.length - 1, sag: true, zemin: i == satirlar.length - 1 ? gri : null),
          ]),
      ],
    ),
  ));
  return doc.save();
}

// ================================================================ EXCEL

Uint8List pusulaXlsx(PusulaVeri v) {
  final satirlar = <List<dynamic>>[
    ['DÖNEM', v.donem],
    ['GEÇEN AY', v.gecenAy == 0 ? '' : v.gecenAy],
    for (final k in v.kalemler) [k.$1, k.$2 == 0 ? '' : k.$2],
    ['TOPLAM', v.toplam],
  ];
  return xlsxYaz([('Liste', ['TÜRÜ', v.firma], satirlar)], para: true);
}

// ================================================================ İNDİR / PAYLAŞ

Future<void> pusulaIndir(PusulaVeri v, String tur) async {
  switch (tur) {
    case 'png':
      await bordroKaydet(v.dosyaAdi, await pusulaPng(v), 'png');
    case 'pdf':
      await bordroKaydet(v.dosyaAdi, await pusulaPdf(v), 'pdf');
    case 'xlsx':
      await bordroKaydet(v.dosyaAdi, pusulaXlsx(v), 'xlsx');
  }
}

String _whatsappNo(String telefon) {
  var d = telefon.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = '90${d.substring(1)}';
  if (d.length == 10) d = '90$d';
  return d;
}

bool get _telefonMu => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Telefonda: paylaşım menüsü açılır, WhatsApp'ı seçersin, resim hazır gelir.
/// Bilgisayarda: resim indirilir ve firmanın WhatsApp sohbeti açılır (telefon kayıtlıysa); resmi sohbete sürükleyip bırakırsın.
/// Döndürdüğü metin kullanıcıya gösterilecek kısa bilgidir.
Future<String> pusulaWhatsapp(PusulaVeri v, String telefon) async {
  final png = await pusulaPng(v);
  if (_telefonMu) {
    await Share.shareXFiles([XFile.fromData(png, mimeType: 'image/png', name: '${v.dosyaAdi}.png')], text: v.metin);
    return 'Paylaşım menüsünden WhatsApp\'ı seçebilirsin.';
  }
  await bordroKaydet(v.dosyaAdi, png, 'png');
  final no = _whatsappNo(telefon);
  final adres = no.isEmpty
      ? Uri.parse('https://web.whatsapp.com/')
      : Uri.parse('https://wa.me/$no?text=${Uri.encodeComponent('${v.firma} - ${v.donem} hesap listesi')}');
  await launchUrl(adres, mode: LaunchMode.externalApplication);
  return 'Resim indirildi. WhatsApp sohbeti açıldı, indirilen resmi sohbete sürükleyip gönder.'
      '${no.isEmpty ? ' (Firmada telefon kayıtlı değil, Firmalar bölümünden eklersen sohbet doğrudan açılır.)' : ''}';
}


/// Verilen metinle firmanın WhatsApp sohbetini açar. Telefon kayıtlı değilse WhatsApp Web açılır ve false döner.
Future<bool> whatsappMesajAc(String telefon, String metin) async {
  final no = _whatsappNo(telefon);
  if (no.isEmpty) {
    await launchUrl(Uri.parse('https://web.whatsapp.com/'), mode: LaunchMode.externalApplication);
    return false;
  }
  await launchUrl(Uri.parse('https://wa.me/$no?text=${Uri.encodeComponent(metin)}'), mode: LaunchMode.externalApplication);
  return true;
}
