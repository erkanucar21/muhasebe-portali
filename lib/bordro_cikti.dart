import 'marka.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'bordro_hesap.dart';

const bordroAylar = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
];

/// Bir personelin seçili aydaki bordro sonucu ve kimlik bilgileri.
class PersonelBordro {
  final String ad, tc, meslek, sgkSicil;
  final int gelmedi; // o ay işe gelmediği gün
  final DateTime giris;
  final DateTime? cikis;
  final bool asgari, netMaas;
  final double kayitliMaas;
  final AyBordro b;
  final double tazBrut, tazKesinti; // çıkış ayına yansıtılan kıdem + ihbar tazminatı
  double get tazNet => tazBrut - tazKesinti;
  const PersonelBordro({
    this.tazBrut = 0,
    this.tazKesinti = 0,
    required this.ad,
    required this.tc,
    required this.meslek,
    required this.sgkSicil,
    this.gelmedi = 0,
    required this.giris,
    this.cikis,
    required this.asgari,
    required this.netMaas,
    required this.kayitliMaas,
    required this.b,
  });
}

/// 28075.5 -> "28.075,50"
String tl(double v) {
  final negatif = v < 0;
  final p = v.abs().toStringAsFixed(2).split('.');
  final bin = p[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '${negatif ? '-' : ''}$bin,${p[1]}';
}

class BordroToplam {
  double brut = 0, sgk = 0, iss = 0, gv = 0, damga = 0, net = 0, isvSgk = 0, isvIss = 0, maliyet = 0;
  BordroToplam(Iterable<PersonelBordro> l) {
    for (final p in l) {
      brut += p.b.brut;
      sgk += p.b.sgkIsci;
      iss += p.b.issizlikIsci;
      gv += p.b.gelirVergisi;
      damga += p.b.damga;
      net += p.b.net;
      isvSgk += p.b.isverenSgk;
      isvIss += p.b.isverenIssizlik;
      maliyet += p.b.maliyet;
    }
  }
}

Future<void> bordroKaydet(String ad, Uint8List veri, String uzanti) async {
  final dynamic fs = FileSaver.instance;
  try {
    await fs.saveFile(name: ad, bytes: veri, fileExtension: uzanti, mimeType: MimeType.other);
  } on NoSuchMethodError {
    await fs.saveFile(name: ad, bytes: veri, ext: uzanti, mimeType: MimeType.other);
  }
}

// ======================================================================== PDF

Future<Uint8List> bordroPdf(List<PersonelBordro> liste,
    {required String firma, required int yil, required int ay, bool ozetSayfasi = false}) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
    ),
  );
  final donem = '${bordroAylar[ay - 1]} $yil';

  pw.Widget t(String s, {bool kalin = false, double boyut = 9, pw.TextAlign? hiza}) => pw.Text(s,
      textAlign: hiza,
      style: pw.TextStyle(fontSize: boyut, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal));

  if (ozetSayfasi && liste.length > 1) {
    final top = BordroToplam(liste);
    final bas = ['No', 'Ad soyad', 'Gün', 'Brüt', 'SGK+İşsizlik', 'Gelir vergisi', 'Damga', 'Net', 'İşveren payı', 'Maliyet'];
    final satirlar = <List<String>>[
      for (var i = 0; i < liste.length; i++)
        [
          '${i + 1}',
          liste[i].ad,
          '${liste[i].b.gun}',
          tl(liste[i].b.brut),
          tl(liste[i].b.sgkIsci + liste[i].b.issizlikIsci),
          tl(liste[i].b.gelirVergisi),
          tl(liste[i].b.damga),
          tl(liste[i].b.net),
          tl(liste[i].b.isverenPayi),
          tl(liste[i].b.maliyet),
        ],
      ['', 'TOPLAM', '', tl(top.brut), tl(top.sgk + top.iss), tl(top.gv), tl(top.damga), tl(top.net), tl(top.isvSgk + top.isvIss), tl(top.maliyet)],
    ];
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      footer: (c) => markaAlt(c),
      header: (c) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          t('BORDRO ÖZETİ', kalin: true, boyut: 14),
          t('$firma   |   Dönem: $donem', boyut: 10),
        ]),
      ),
      build: (c) => [
        pw.TableHelper.fromTextArray(
          headers: bas,
          data: satirlar,
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: {
            for (var i = 2; i < 10; i++) i: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FixedColumnWidth(28),
          },
        ),
      ],
    ));
  }

  for (final p in liste) {
    final b = p.b;
    pw.TableRow satir(String e, String d, {bool kalin = false, PdfColor? zemin}) => pw.TableRow(
          decoration: zemin == null ? null : pw.BoxDecoration(color: zemin),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5), child: t(e, kalin: kalin)),
            pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                child: t(d, kalin: kalin, hiza: pw.TextAlign.right)),
          ],
        );

    pw.Widget baslik(String s) => pw.Container(
          width: double.infinity,
          color: PdfColors.grey300,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: t(s, kalin: true),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(child: t('ÜCRET PUSULASI / BORDRO', kalin: true, boyut: 15)),
        pw.SizedBox(height: 4),
        pw.Center(child: t('$firma', boyut: 10.5)),
        pw.Center(child: t('Dönem: $donem', boyut: 10.5)),
        pw.SizedBox(height: 14),
        pw.Table(columnWidths: {0: const pw.FixedColumnWidth(110), 1: const pw.FlexColumnWidth()}, children: [
          pw.TableRow(children: [t('Ad soyad', kalin: true, boyut: 10), t(p.ad, boyut: 10)]),
          pw.TableRow(children: [t('TC kimlik no', kalin: true, boyut: 10), t(p.tc.isEmpty ? '-' : p.tc, boyut: 10)]),
          pw.TableRow(children: [t('Meslek', kalin: true, boyut: 10), t(p.meslek.isEmpty ? '-' : p.meslek, boyut: 10)]),
          pw.TableRow(children: [t('Çalışılan gün', kalin: true, boyut: 10), t('${b.gun} / 30', boyut: 10)]),
        ]),
        pw.SizedBox(height: 14),
        baslik('KAZANÇ'),
        pw.Table(columnWidths: {0: const pw.FlexColumnWidth(), 1: const pw.FixedColumnWidth(110)}, children: [
          satir('Brüt ücret', tl(b.brut), kalin: true),
        ]),
        pw.SizedBox(height: 8),
        baslik('İŞÇİ KESİNTİLERİ'),
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(width: 0.3, color: PdfColors.grey500)),
          columnWidths: {0: const pw.FlexColumnWidth(), 1: const pw.FixedColumnWidth(110)},
          children: [
            satir('SGK matrahı', tl(b.sgkMatrah)),
            satir('SGK işçi payı (%14)', tl(b.sgkIsci)),
            satir('İşsizlik sigortası işçi payı (%1)', tl(b.issizlikIsci)),
            satir('Gelir vergisi matrahı', tl(b.gvMatrah)),
            satir('Kümülatif gelir vergisi matrahı', tl(b.kumMatrah)),
            satir('Hesaplanan gelir vergisi', tl(b.gvHesap)),
            satir('Asgari ücret gelir vergisi istisnası', '-${tl(b.gvIstisna)}'),
            satir('Ödenecek gelir vergisi', tl(b.gelirVergisi), kalin: true),
            satir('Hesaplanan damga vergisi (%0,759)', tl(b.damgaHesap)),
            satir('Asgari ücret damga vergisi istisnası', '-${tl(b.damgaIstisna)}'),
            satir('Ödenecek damga vergisi', tl(b.damga), kalin: true),
            satir('Toplam kesinti', tl(b.isciKesinti), kalin: true),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Table(columnWidths: {0: const pw.FlexColumnWidth(), 1: const pw.FixedColumnWidth(110)}, children: [
          satir('NET ÖDENECEK', tl(b.net), kalin: true, zemin: PdfColors.grey200),
          if (p.tazBrut > 0) satir('Kıdem / ihbar tazminatı (brüt)', tl(p.tazBrut)),
          if (p.tazBrut > 0) satir('Tazminat vergi kesintileri', '-${tl(p.tazKesinti)}'),
          if (p.tazBrut > 0) satir('TOPLAM ÖDENECEK (maaş + tazminat)', tl(b.net + p.tazNet), kalin: true, zemin: PdfColors.grey200),
        ]),
        pw.SizedBox(height: 12),
        baslik('İŞVEREN MALİYETİ (bilgi)'),
        pw.Table(columnWidths: {0: const pw.FlexColumnWidth(), 1: const pw.FixedColumnWidth(110)}, children: [
          satir('İşveren SGK payı', tl(b.isverenSgk)),
          satir('İşveren işsizlik payı (%2)', tl(b.isverenIssizlik)),
          satir('Toplam işveren maliyeti', tl(b.maliyet), kalin: true),
        ]),
        pw.Spacer(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t('Yukarıdaki ücreti eksiksiz teslim aldım.', boyut: 9),
            pw.SizedBox(height: 28),
            t('${p.ad}  -  İmza', boyut: 9),
          ]),
        ]),
        pw.SizedBox(height: 6),
        t('Bu belge bilgi amaçlıdır; resmî bordro yerine geçmez. Hesap, ilgili yılın yasal oranlarına göre yapılmıştır.',
            boyut: 7.5),
      ]),
    ));
  }
  return Uint8List.fromList(await doc.save());
}

// ============================================ LUCA BİÇİMİNDE BORDRO (liste)

const bordroAylarBuyuk = [
  'OCAK', 'ŞUBAT', 'MART', 'NİSAN', 'MAYIS', 'HAZİRAN', 'TEMMUZ', 'AĞUSTOS', 'EYLÜL', 'EKİM', 'KASIM', 'ARALIK'
];

/// Bordro başlığındaki işyeri bilgileri
class FirmaBilgi {
  final String ad, adres, sgkSicil, sgkSube, vergiDairesi, vergiNo, mersis, ticaretSicil;
  const FirmaBilgi({
    required this.ad,
    this.adres = '',
    this.sgkSicil = '',
    this.sgkSube = '',
    this.vergiDairesi = '',
    this.vergiNo = '',
    this.mersis = '',
    this.ticaretSicil = '',
  });

  String get vergiSatiri =>
      '${vergiDairesi.isEmpty ? '' : vergiDairesi}${vergiDairesi.isNotEmpty && vergiNo.isNotEmpty ? ' / ' : ''}$vergiNo';
}

String _tarih(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _bosIse(double v) => v == 0 ? '-' : tl(v);

const _listeBasliklar = [
  'ADI SOYADI', 'GİRİŞ TARİHİ', 'ÇIKIŞ TARİHİ', 'T.C. KİMLİK NO', 'SSK SİCİL NO', 'GÜN', 'NORMAL KAZANÇ',
  'DİĞER KAZANÇ', 'TOPLAM KAZANÇ', 'SSK MATRAH', 'SSK PRİMİ', 'İŞSİZLİK PRİMİ', 'G.V.M. (AYLIK)', 'GELİR VERGİSİ',
  'ASGARİ GEÇ.İND.', 'KALAN G.VER.', 'DAMGA VERGİSİ', 'ÖZEL KESİNTİ', 'NET İSTİHKAK', 'İMZA'
];

/// Bir personelin sayısal sütunları (GÜN'den sonra, İMZA'dan önce): 13 değer
List<double> _sayilar(AyBordro b) => [
      b.brut, // normal kazanç
      0, // diğer kazanç
      b.brut, // toplam kazanç
      b.sgkMatrah,
      b.sgkIsci,
      b.issizlikIsci,
      b.gvMatrah,
      b.gelirVergisi, // asgari ücret istisnası düşülmüş gelir vergisi (Luca ile aynı)
      0, // asgari geçim indirimi (2022'den beri yok)
      b.gelirVergisi, // kalan gelir vergisi
      b.damga,
      0, // özel kesinti
      b.net, // net istihkak
    ];

Future<Uint8List> bordroListePdf(List<PersonelBordro> liste,
    {required FirmaBilgi firma, required int yil, required int ay}) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
    ),
  );
  const f = 6.2;
  pw.Widget t(String s, {bool kalin = false, double boyut = f, pw.TextAlign hiza = pw.TextAlign.left}) => pw.Text(s,
      textAlign: hiza,
      style: pw.TextStyle(fontSize: boyut, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal));

  pw.Widget hucre(String s, {bool sag = false, bool kalin = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2.5),
        child: t(s, kalin: kalin, hiza: sag ? pw.TextAlign.right : pw.TextAlign.left),
      );

  final toplam = List<double>.filled(13, 0);
  var gunToplam = 0;
  for (final p in liste) {
    final v = _sayilar(p.b);
    for (var i = 0; i < 13; i++) {
      toplam[i] += v[i];
    }
    gunToplam += p.b.gun;
  }

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      repeat: true,
      children: [
        for (var i = 0; i < _listeBasliklar.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: t(_listeBasliklar[i], kalin: true, hiza: i < 5 ? pw.TextAlign.left : pw.TextAlign.center),
          ),
      ],
    ),
  ];
  for (final p in liste) {
    final v = _sayilar(p.b);
    rows.add(pw.TableRow(children: [
      hucre(p.ad, kalin: true),
      hucre(_tarih(p.giris)),
      hucre(_tarih(p.cikis)),
      hucre(p.tc),
      hucre(p.sgkSicil.trim()),
      hucre('${p.b.gun} Gün', sag: true),
      for (final x in v) hucre(_bosIse(x), sag: true),
      hucre(''),
    ]));
  }
  rows.add(pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
    children: [
      for (var i = 0; i < 5; i++) hucre(''),
      hucre('$gunToplam Gün', sag: true, kalin: true),
      for (var i = 0; i < 13; i++) hucre(_bosIse(toplam[i]), sag: true, kalin: true),
      hucre(''),
    ],
  ));

  doc.addPage(pw.MultiPage(
    pageFormat: const PdfPageFormat(1190, 842, marginAll: 22), // A3 yatay
    header: (c) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Center(child: t('${bordroAylarBuyuk[ay - 1]} $yil ÜCRET BORDROSU', kalin: true, boyut: 12)),
        pw.SizedBox(height: 6),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t('İşyeri: ${firma.ad}', boyut: 8, kalin: true),
              t('İşyeri S.No: ${firma.sgkSicil}', boyut: 8),
              t('SSK Şube: ${firma.sgkSube}', boyut: 8),
              t('Vergi D./No: ${firma.vergiSatiri}', boyut: 8),
              t('MERSİS No: ${firma.mersis}', boyut: 8),
              t('Ticaret Sicil No: ${firma.ticaretSicil}', boyut: 8),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t('Adres: ${firma.adres}', boyut: 8),
              pw.SizedBox(height: 4),
              t('Merkez Adresi: ${firma.adres}', boyut: 8),
              pw.SizedBox(height: 4),
              t('Web Adresi: -', boyut: 8),
            ]),
          ),
        ]),
      ]),
    ),
    footer: (c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: t('Listelenen ${liste.length} Personel   |   Sayfa ${c.pageNumber}/${c.pagesCount}', boyut: 7),
    ),
    build: (c) => [
      pw.Table(
        border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey600),
        columnWidths: {
          0: const pw.FixedColumnWidth(92),
          1: const pw.FixedColumnWidth(52),
          2: const pw.FixedColumnWidth(52),
          3: const pw.FixedColumnWidth(62),
          4: const pw.FixedColumnWidth(54),
          5: const pw.FixedColumnWidth(36),
          for (var i = 6; i < 19; i++) i: const pw.FixedColumnWidth(58),
          19: const pw.FixedColumnWidth(80),
        },
        children: rows,
      ),
    ],
  ));
  return Uint8List.fromList(await doc.save());
}

// ===================================================================== EXCEL (Luca biçimi)

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _kolon(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

Uint8List bordroListeXlsx(List<PersonelBordro> liste, {required FirmaBilgi firma, required int yil, required int ay}) {
  final sat = StringBuffer();
  final birlestir = <String>[];
  var r = 0;

  String metin(int k, String m, int stil) => m.isEmpty
      ? '<c r="${_kolon(k)}$r" s="$stil"/>'
      : '<c r="${_kolon(k)}$r" s="$stil" t="inlineStr"><is><t xml:space="preserve">${_x(m)}</t></is></c>';
  String sayi(int k, double v, int stil) => '<c r="${_kolon(k)}$r" s="$stil"><v>${v.toStringAsFixed(2)}</v></c>';
  void satir(String icerik, {double? yukseklik}) {
    sat.write('<row r="$r"${yukseklik == null ? '' : ' ht="$yukseklik" customHeight="1"'}>$icerik</row>');
  }

  r = 2;
  satir(metin(8, '${bordroAylarBuyuk[ay - 1]} $yil ÜCRET BORDROSU', 3));
  birlestir.add('I2:N2');
  r = 3;
  satir(metin(0, 'İşyeri: ${firma.ad}', 4) + metin(13, 'Adres: ${firma.adres}', 0));
  r = 4;
  satir(metin(0, 'İşyeri S.No: ${firma.sgkSicil}', 0));
  r = 5;
  satir(metin(0, 'SSK Şube: ${firma.sgkSube}', 0));
  r = 6;
  satir(metin(0, 'Vergi D./No: ${firma.vergiSatiri}', 0) + metin(13, 'Merkez Adresi: ${firma.adres}', 0));
  r = 7;
  satir(metin(0, 'MERSİS No: ${firma.mersis}', 0));
  r = 8;
  satir(metin(0, 'Ticaret Sicil No: ${firma.ticaretSicil}', 0) + metin(13, 'Web Adresi: -', 0));

  // Başlık iki satır (10-11) birleşik, veri 12. satırdan başlar. GÜN F, "Gün" etiketi G sütununda.
  const kolonlar = [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
  r = 10;
  satir([for (var i = 0; i < _listeBasliklar.length; i++) metin(kolonlar[i], _listeBasliklar[i], 1)].join(),
      yukseklik: 22);
  r = 11;
  satir([for (var i = 0; i < _listeBasliklar.length; i++) metin(kolonlar[i], '', 1)].join(), yukseklik: 22);
  for (final k in kolonlar) {
    birlestir.add('${_kolon(k)}10:${_kolon(k)}11');
  }

  final toplam = List<double>.filled(13, 0);
  var gunToplam = 0;
  r = 11;
  for (final p in liste) {
    final v = _sayilar(p.b);
    for (var i = 0; i < 13; i++) {
      toplam[i] += v[i];
    }
    gunToplam += p.b.gun;
    r++;
    satir([
      metin(0, p.ad, 4),
      metin(1, _tarih(p.giris), 0),
      metin(2, _tarih(p.cikis), 0),
      metin(3, p.tc, 0),
      metin(4, p.sgkSicil.trim(), 0),
      sayi(5, p.b.gun.toDouble(), 5),
      metin(6, 'Gün', 0),
      for (var i = 0; i < 13; i++) sayi(7 + i, v[i], 2),
    ].join());
  }
  r++;
  satir([
    sayi(5, gunToplam.toDouble(), 5),
    metin(6, 'Gün', 0),
    for (var i = 0; i < 13; i++) sayi(7 + i, toplam[i], 6),
  ].join());
  r++;
  satir(metin(0, 'Listelenen ${liste.length} Personel', 4));

  final birlesimler = birlestir.map((m) => '<mergeCell ref="$m"/>').join();
  final sayfa = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<sheetViews><sheetView showGridLines="0" workbookViewId="0"/></sheetViews>'
      '<cols><col min="1" max="1" width="26" customWidth="1"/><col min="2" max="3" width="12" customWidth="1"/>'
      '<col min="4" max="4" width="14" customWidth="1"/><col min="5" max="5" width="12" customWidth="1"/>'
      '<col min="6" max="6" width="5" customWidth="1"/><col min="7" max="7" width="5" customWidth="1"/>'
      '<col min="8" max="20" width="14" customWidth="1"/><col min="21" max="21" width="18" customWidth="1"/></cols>'
      '<sheetData>$sat</sheetData>'
      '<mergeCells count="${birlestir.length}">$birlesimler</mergeCells>'
      '<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>'
      '<pageSetup paperSize="8" orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
      '</worksheet>';

  const tipler = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>';
  const kok = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';
  const kitap = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Bordro" sheetId="1" r:id="rId1"/></sheets></workbook>';
  const kitapBag = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';
  // Stiller: 0 normal, 1 kalın başlık (gri, kenarlıklı), 2 sayı (sıfır "-"), 3 kalın büyük ortalı, 4 kalın,
  // 5 tam sayı, 6 kalın gri sayı
  const stiller = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00;\\-#,##0.00;&quot;-&quot;"/></numFmts>'
      '<fonts count="3"><font><sz val="9"/><name val="Arial"/></font><font><b/><sz val="9"/><name val="Arial"/></font><font><b/><sz val="12"/><name val="Arial"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9D9D9"/></patternFill></fill></fills>'
      '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FF808080"/></left><right style="thin"><color rgb="FF808080"/></right><top style="thin"><color rgb="FF808080"/></top><bottom style="thin"><color rgb="FF808080"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="7">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center"/></xf>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>'
      '<xf numFmtId="164" fontId="1" fillId="2" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>'
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  final arsiv = Archive();
  void ekle(String ad, String icerik) {
    final b = utf8.encode(icerik);
    arsiv.addFile(ArchiveFile(ad, b.length, b));
  }

  ekle('[Content_Types].xml', tipler);
  ekle('_rels/.rels', kok);
  ekle('xl/workbook.xml', kitap);
  ekle('xl/_rels/workbook.xml.rels', kitapBag);
  ekle('xl/styles.xml', stiller);
  ekle('xl/worksheets/sheet1.xml', sayfa);
  return Uint8List.fromList(ZipEncoder().encode(arsiv)!);
}
