import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'bordro_cikti.dart' show bordroKaydet, tl;

class OrtakPayi {
  final String ad, tc;
  final double pay, brut, stopaj, net;
  const OrtakPayi({required this.ad, required this.tc, required this.pay, required this.brut, required this.stopaj, required this.net});
}

class KarBelgeVeri {
  final String unvan, donem, genelKurulTarihi;
  final DateTime odemeTarihi;
  final double kar, zarar, yedek1, dagitilabilir, birinci, ikinci, yedek2, olaganustu, toplamPay, stopajOrani;
  final List<OrtakPayi> ortaklar;
  const KarBelgeVeri({
    required this.unvan,
    required this.donem,
    required this.genelKurulTarihi,
    required this.odemeTarihi,
    required this.kar,
    required this.zarar,
    required this.yedek1,
    required this.dagitilabilir,
    required this.birinci,
    required this.ikinci,
    required this.yedek2,
    required this.olaganustu,
    required this.toplamPay,
    required this.stopajOrani,
    required this.ortaklar,
  });
}

String _t(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
String _buyuk(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
String _yz(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');

String _dosya(String s) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosuCGIOSU';
  var r = s;
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
}

Future<pw.Document> _doc() async => pw.Document(
      theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()),
    );

pw.Widget _p(String m, {double boyut = 11, double alt = 8, bool kalin = false, pw.TextAlign hiza = pw.TextAlign.justify}) => pw.Padding(
      padding: pw.EdgeInsets.only(bottom: alt),
      child: pw.Text(m, textAlign: hiza, style: pw.TextStyle(fontSize: boyut, lineSpacing: 3, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

pw.Widget _hucre(String m, {bool kalin = false, bool sag = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(m, textAlign: sag ? pw.TextAlign.right : pw.TextAlign.left, style: pw.TextStyle(fontSize: 9.5, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

/// Kâr dağıtımı hesabından genel kurul karar taslağı.
Future<void> genelKurulKarariPdf(KarBelgeVeri v) async {
  final doc = await _doc();
  final gk = v.genelKurulTarihi.trim().isEmpty ? '....../....../........' : v.genelKurulTarihi.trim();
  final satirlar = <String>[
    '${v.donem} hesap dönemine ait finansal tablolar ve faaliyet raporu görüşülerek onaylanmıştır.',
    '${v.donem} hesap döneminde ${tl(v.kar)} TL net dönem kârı oluşmuştur.',
    if (v.zarar > 0) 'Geçmiş yıllardan devreden ${tl(v.zarar > v.kar ? v.kar : v.zarar)} TL zarar, net dönem kârından mahsup edilmiştir.',
    if (v.yedek1 > 0) '6102 sayılı Türk Ticaret Kanunu m.519 uyarınca ${tl(v.yedek1)} TL genel kanuni yedek akçe ayrılmasına,',
    'Dağıtılabilir kâr ${tl(v.dagitilabilir)} TL olarak belirlenmiş olup bunun ${tl(v.birinci)} TL\'sinin birinci kâr payı, ${tl(v.ikinci)} TL\'sinin ikinci kâr payı olarak ortaklara pay oranlarına göre dağıtılmasına, toplam brüt ${tl(v.toplamPay)} TL kâr payı ödenmesine,',
    if (v.yedek2 > 0) '${tl(v.yedek2)} TL ikinci tertip yedek akçe ayrılmasına,',
    if (v.olaganustu > 0) 'Kalan ${tl(v.olaganustu)} TL\'nin olağanüstü yedek akçe / geçmiş yıl kârı olarak bırakılmasına,',
    'Kâr payı ödemelerinin ${_t(v.odemeTarihi)} tarihinde yapılmasına, ödemelerden yürürlükteki orana göre (%${_yz(v.stopajOrani)}) gelir vergisi stopajı kesilerek muhtasar beyanname ile beyan ve ödenmesine, oybirliği ile karar verilmiştir.',
  ];
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(50, 50, 50, 44),
    build: (c) => [
      _p(_buyuk(v.unvan), kalin: true, boyut: 13, hiza: pw.TextAlign.center, alt: 2),
      _p('OLAĞAN GENEL KURUL KARARI (TASLAK)', kalin: true, boyut: 13, hiza: pw.TextAlign.center, alt: 16),
      _p('Toplantı tarihi: $gk', alt: 14),
      for (var i = 0; i < satirlar.length; i++) _p('${i + 1}- ${satirlar[i]}'),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(2.2),
          2: const pw.FlexColumnWidth(1.2),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(1.8),
          5: const pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            _hucre('Ortak', kalin: true),
            _hucre('TC / Vergi no', kalin: true),
            _hucre('Pay %', kalin: true, sag: true),
            _hucre('Brüt kâr payı', kalin: true, sag: true),
            _hucre('Stopaj', kalin: true, sag: true),
            _hucre('Net ödenen', kalin: true, sag: true),
          ]),
          for (final o in v.ortaklar)
            pw.TableRow(children: [
              _hucre(o.ad),
              _hucre(o.tc),
              _hucre(_yz(o.pay), sag: true),
              _hucre(tl(o.brut), sag: true),
              _hucre(tl(o.stopaj), sag: true),
              _hucre(tl(o.net), sag: true),
            ]),
        ],
      ),
      pw.SizedBox(height: 22),
      pw.Wrap(spacing: 40, runSpacing: 22, children: [
        for (final o in v.ortaklar)
          pw.SizedBox(
            width: 200,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(o.ad, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 22),
              pw.Text('İmza', style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
      ]),
      pw.SizedBox(height: 18),
      pw.Text(
        'Bu belge hesaplamadan üretilmiş bir taslaktır. Şirket türüne göre toplantı ve karar nisapları, esas sözleşme hükümleri ve tutanak şekil şartları ayrıca kontrol edilmelidir.',
        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
      ),
    ],
  ));
  await bordroKaydet('genel_kurul_karari_taslak_${_dosya(v.unvan)}', Uint8List.fromList(await doc.save()), 'pdf');
}

/// Her ortak için ayrı sayfada kâr payı ödeme makbuzu.
Future<void> karPayiMakbuzlariPdf(KarBelgeVeri v) async {
  final doc = await _doc();
  for (final o in v.ortaklar) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 60, 56, 50),
      build: (c) {
        pw.TableRow satir(String a, String b, {bool kalin = false}) => pw.TableRow(children: [_hucre(a, kalin: true), _hucre(b, kalin: kalin)]);
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _p(_buyuk(v.unvan), kalin: true, boyut: 13, hiza: pw.TextAlign.center, alt: 2),
          _p('KÂR PAYI ÖDEME MAKBUZU', kalin: true, boyut: 14, hiza: pw.TextAlign.center, alt: 22),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
            children: [
              satir('Ortağın adı soyadı / unvanı', o.ad),
              satir('T.C. kimlik / vergi no', o.tc.isEmpty ? '...........................' : o.tc),
              satir('Hesap dönemi', v.donem),
              satir('Ödeme tarihi', _t(v.odemeTarihi)),
              satir('Pay oranı', '%${_yz(o.pay)}'),
              satir('Brüt kâr payı', '${tl(o.brut)} TL'),
              satir('Gelir vergisi stopajı (%${_yz(o.stopaj > 0 ? v.stopajOrani : 0)})', '${tl(o.stopaj)} TL'),
              satir('Net ödenen kâr payı', '${tl(o.net)} TL', kalin: true),
            ],
          ),
          pw.SizedBox(height: 22),
          _p('Yukarıda belirtilen net kâr payı tutarını eksiksiz olarak tahsil ettim. Bu ödeme dışında ${v.donem} dönemi kâr payından alacağım kalmamıştır.'),
          pw.SizedBox(height: 28),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(o.ad, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 26),
              pw.Text('İmza', style: const pw.TextStyle(fontSize: 10)),
            ]),
          ),
        ]);
      },
    ));
  }
  await bordroKaydet('kar_payi_makbuzlari_${_dosya(v.unvan)}', Uint8List.fromList(await doc.save()), 'pdf');
}
