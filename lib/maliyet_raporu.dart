import 'marka.dart';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'bordro_cikti.dart' show bordroAylar, tl;
import 'bordro_hesap.dart';
import 'personel_takip.dart';

/// Yılbaşından seçili aya kadar çalışan başına işveren maliyeti raporu (PDF, yatay).
Future<Uint8List> maliyetRaporuPdf({
  required String firma,
  required List<Personel> personel,
  required YilParam param,
  required int yil,
  required int sonAy,
  required Map<int, Map<int, int>> gelmedi,
  int? indirimPuan,
}) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()),
  );

  final satirlar = <({String ad, List<AyBordro> aylar})>[];
  for (final k in personel) {
    final dizi = yillikBordro(
      param,
      BordroGirdi(ucret: k.ucret, net: k.maasTuru != 'brut', asgari: k.asgari, giris: k.giris, cikis: k.cikis),
      sonAy,
      indirimPuan: indirimPuan,
      gelmedi: gelmedi[k.id],
    );
    if (dizi.every((a) => a.gun == 0)) continue;
    satirlar.add((ad: k.ad, aylar: dizi));
  }
  satirlar.sort((a, b) => a.ad.compareTo(b.ad));

  double topla(List<AyBordro> l, double Function(AyBordro) f) => l.fold(0.0, (t, a) => t + f(a));

  final ozetBas = ['Ad soyad', 'Brüt', 'İşçi kesintileri', 'Net ödenen', 'İşveren payı', 'Toplam maliyet', 'Aylık ortalama'];
  final ozet = <List<String>>[];
  var tBrut = 0.0, tKes = 0.0, tNet = 0.0, tIsv = 0.0, tMal = 0.0;
  for (final s in satirlar) {
    final brut = topla(s.aylar, (a) => a.brut);
    final kes = topla(s.aylar, (a) => a.isciKesinti);
    final net = topla(s.aylar, (a) => a.net);
    final isv = topla(s.aylar, (a) => a.isverenPayi);
    final mal = topla(s.aylar, (a) => a.maliyet);
    final calisan = s.aylar.where((a) => a.gun > 0).length;
    tBrut += brut;
    tKes += kes;
    tNet += net;
    tIsv += isv;
    tMal += mal;
    ozet.add([s.ad, tl(brut), tl(kes), tl(net), tl(isv), tl(mal), tl(calisan == 0 ? 0 : mal / calisan)]);
  }
  ozet.add(['TOPLAM', tl(tBrut), tl(tKes), tl(tNet), tl(tIsv), tl(tMal), '']);

  final aylikBas = ['Ad soyad', for (var a = 1; a <= sonAy; a++) bordroAylar[a - 1].substring(0, 3), 'Toplam'];
  final aylik = <List<String>>[];
  final aySutun = List<double>.filled(sonAy, 0);
  for (final s in satirlar) {
    final satir = <String>[s.ad];
    var top = 0.0;
    for (var a = 0; a < sonAy; a++) {
      final m = a < s.aylar.length ? s.aylar[a].maliyet : 0.0;
      aySutun[a] += m;
      top += m;
      satir.add(m == 0 ? '-' : tl(m));
    }
    satir.add(tl(top));
    aylik.add(satir);
  }
  aylik.add(['TOPLAM', for (final m in aySutun) tl(m), tl(tMal)]);

  pw.Widget t(String s, {bool kalin = false, double boyut = 9}) =>
      pw.Text(s, style: pw.TextStyle(fontSize: boyut, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal));

  pw.Widget tablo(List<String> bas, List<List<String>> veri, {double boyut = 8.5}) => pw.TableHelper.fromTextArray(
        headers: bas,
        data: veri,
        headerStyle: pw.TextStyle(fontSize: boyut, fontWeight: pw.FontWeight.bold),
        cellStyle: pw.TextStyle(fontSize: boyut),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignments: {for (var i = 1; i < bas.length; i++) i: pw.Alignment.centerRight},
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    footer: (c) => markaAlt(c),
    header: (c) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        t('PERSONEL MALİYET RAPORU', kalin: true, boyut: 14),
        t('$firma   |   Ocak - ${bordroAylar[sonAy - 1]} $yil', boyut: 10),
      ]),
    ),
    build: (c) => [
      t('Personel bazında özet', kalin: true, boyut: 11),
      pw.SizedBox(height: 4),
      tablo(ozetBas, ozet),
      pw.SizedBox(height: 16),
      t('Aylık işveren maliyeti', kalin: true, boyut: 11),
      pw.SizedBox(height: 4),
      tablo(aylikBas, aylik, boyut: sonAy > 8 ? 6.5 : 8),
      pw.SizedBox(height: 10),
      t(
        'Maliyet: brüt ücret ile işveren SGK ve işsizlik primi payının toplamıdır. İşçi kesintileri: SGK, işsizlik, gelir vergisi ve damga vergisi (asgari ücret istisnaları düşülmüş). '
        'Bordro motorunun hesabıdır, kesin tutar için resmi bordro ve bildirgeleri esas al.',
        boyut: 8,
      ),
    ],
  ));
  return doc.save();
}
