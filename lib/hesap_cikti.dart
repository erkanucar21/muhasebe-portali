import 'marka.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'bordro_cikti.dart' show bordroKaydet;
import 'bordro_hesap.dart' show kurus;

const imzaMetni = 'SMMM ERKAN UÇAR';

// ====================================================================== PDF

/// Hesaplayıcı sonucunu PDF olarak indirir. Satır değeri boşsa başlık satırıdır, etiketi ">" ile başlayan satırlar vurgulanır.
/// Sayfanın üstünde ve altında "SMMM ERKAN UÇAR" yazar.
Future<void> hesapPdfKaydet(String ad, String baslik, List<(String, String)> satirlar) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()),
  );
  const yesil = PdfColor.fromInt(0xFF1B5E20);
  pw.Widget imza({required bool ust}) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        decoration: pw.BoxDecoration(
          border: ust ? const pw.Border(bottom: pw.BorderSide(color: yesil, width: 1.2)) : const pw.Border(top: pw.BorderSide(color: yesil, width: 1.2)),
        ),
        child: pw.Center(
          child: pw.Text(imzaMetni, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: yesil, letterSpacing: 2)),
        ),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: (c) => markaUst(),
    footer: (c) => markaAlt(c),
    build: (c) => [
      pw.Text(baslik, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      for (final x in satirlar)
        x.$2.isEmpty
            ? pw.Padding(padding: const pw.EdgeInsets.only(top: 8, bottom: 2), child: pw.Text(x.$1, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))
            : pw.Container(
                color: x.$1.startsWith('>') ? PdfColors.green100 : null,
                padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text(x.$1.startsWith('>') ? x.$1.substring(1) : x.$1, style: x.$1.startsWith('>') ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
                  pw.Text(x.$2, style: x.$1.startsWith('>') ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
                ]),
              ),
      pw.SizedBox(height: 16),
      pw.Text('Bu çıktı bir ön hesaptır. Oran ve sınırları güncel mevzuattan kontrol edin.', style: const pw.TextStyle(fontSize: 9)),
    ],
  ));
  await bordroKaydet(ad, await doc.save(), 'pdf');
}

// ====================================================================== XLSX yazıcı

const _sNormal = 0, _sBaslik = 1, _sPara = 2, _sBuyuk = 3, _sKalin = 4, _sOran = 5, _gPara = 6, _sSonuc = 7, _gTarih = 8;
const _sImza = 9, _sMetin = 10, _gTam = 11, _gOran = 12, _sEtiket = 13, _sNot = 14, _sParaKalin = 15, _sTarih = 16, _gMetin = 17;
const _sYuzde = 18, _sYuzdeKalin = 19, _sTam = 20;

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _kol(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

double _serial(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1899, 12, 30)).inDays.toDouble();

class _Xls {
  final List<double> genislik;
  final StringBuffer _sat = StringBuffer();
  final List<String> _birlesim = [];
  final List<String> _hucre = [];
  final List<String> _dogrulama = [];
  int r = 1;
  _Xls(this.genislik);

  int get sonKolon => genislik.length - 1;

  void metin(int k, String m, int stil) {
    _hucre.add(m.isEmpty
        ? '<c r="${_kol(k)}$r" s="$stil"/>'
        : '<c r="${_kol(k)}$r" s="$stil" t="inlineStr"><is><t xml:space="preserve">${_x(m)}</t></is></c>');
  }

  void sayi(int k, double v, int stil) => _hucre.add('<c r="${_kol(k)}$r" s="$stil"><v>${_sayiYaz(v)}</v></c>');

  void formul(int k, String f, double onbellek, int stil) =>
      _hucre.add('<c r="${_kol(k)}$r" s="$stil"><f>${_x(f)}</f><v>${_sayiYaz(onbellek)}</v></c>');

  String _sayiYaz(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void birlestir(String aralik) => _birlesim.add(aralik);

  void liste(String aralik, List<String> secenek) =>
      _dogrulama.add('<dataValidation type="list" allowBlank="1" showErrorMessage="1" sqref="$aralik"><formula1>"${_x(secenek.join(','))}"</formula1></dataValidation>');

  void satir({double? yukseklik}) {
    _sat.write('<row r="$r"${yukseklik == null ? '' : ' ht="$yukseklik" customHeight="1"'}>${_hucre.join()}</row>');
    _hucre.clear();
    r++;
  }

  /// Üst imza + başlık + açıklama
  void ust(String baslik) {
    metin(0, imzaMetni, _sImza);
    birlestir('A$r:${_kol(sonKolon)}$r');
    satir(yukseklik: 28);
    metin(0, baslik, _sBuyuk);
    birlestir('A$r:${_kol(sonKolon)}$r');
    satir(yukseklik: 24);
    final t = DateTime.now();
    String i(int n) => n.toString().padLeft(2, '0');
    metin(0, 'Düzenlenme: ${i(t.day)}.${i(t.month)}.${t.year}   •   Sarı hücreler girdidir; değiştirirsen sonuçlar otomatik güncellenir.', _sNot);
    birlestir('A$r:${_kol(sonKolon)}$r');
    satir();
    satir();
  }

  /// Alt imza
  void alt() {
    satir();
    metin(0, 'Bu çıktı bir ön hesaptır. Oran ve sınırları güncel mevzuattan kontrol edin.', _sNot);
    birlestir('A$r:${_kol(sonKolon)}$r');
    satir();
    metin(0, imzaMetni, _sImza);
    birlestir('A$r:${_kol(sonKolon)}$r');
    satir(yukseklik: 28);
  }

  Uint8List bitir(String sayfaAdi) {
    final cols = StringBuffer('<cols>');
    for (var i = 0; i < genislik.length; i++) {
      cols.write('<col min="${i + 1}" max="${i + 1}" width="${genislik[i]}" customWidth="1"/>');
    }
    cols.write('</cols>');
    final birlesimler = _birlesim.isEmpty ? '' : '<mergeCells count="${_birlesim.length}">${_birlesim.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>';
    final dogr = _dogrulama.isEmpty ? '' : '<dataValidations count="${_dogrulama.length}">${_dogrulama.join()}</dataValidations>';
    final sayfa = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
        '<sheetViews><sheetView showGridLines="0" workbookViewId="0"/></sheetViews>'
        '$cols<sheetData>$_sat</sheetData>$birlesimler$dogr'
        '<pageMargins left="0.5" right="0.5" top="0.8" bottom="0.8" header="0.3" footer="0.3"/>'
        '<pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="0"/>'
        '<headerFooter><oddHeader>&amp;C&amp;"Arial,Bold"&amp;12$imzaMetni</oddHeader><oddFooter>&amp;C&amp;"Arial,Bold"&amp;12$imzaMetni</oddFooter></headerFooter>'
        '</worksheet>';

    const tipler = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>';
    const kok = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';
    final kitap = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${_x(sayfaAdi)}" sheetId="1" r:id="rId1"/></sheets><calcPr fullCalcOnLoad="1"/></workbook>';
    const kitapBag = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';

    const kenar = '<border><left style="thin"><color rgb="FF808080"/></left><right style="thin"><color rgb="FF808080"/></right><top style="thin"><color rgb="FF808080"/></top><bottom style="thin"><color rgb="FF808080"/></bottom><diagonal/></border>';
    String xf(int fmt, int font, int fill, int border, {String? hiza}) =>
        '<xf numFmtId="$fmt" fontId="$font" fillId="$fill" borderId="$border" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"${hiza == null ? '' : ' applyAlignment="1"'}>${hiza ?? ''}</xf>';
    const orta = '<alignment horizontal="center" vertical="center" wrapText="1"/>';
    const solSarma = '<alignment vertical="center" wrapText="1"/>';
    final stiller = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="3"><numFmt numFmtId="164" formatCode="#,##0.00;\\-#,##0.00"/><numFmt numFmtId="165" formatCode="dd\\.mm\\.yyyy"/><numFmt numFmtId="166" formatCode="0.00"/></numFmts>'
        '<fonts count="5"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><name val="Arial"/></font><font><b/><sz val="14"/><name val="Arial"/></font>'
        '<font><b/><sz val="13"/><color rgb="FF1B5E20"/><name val="Arial"/></font><font><i/><sz val="9"/><color rgb="FF595959"/><name val="Arial"/></font></fonts>'
        '<fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFD9D9D9"/></patternFill></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF9C4"/></patternFill></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFC8E6C9"/></patternFill></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFE8F5E9"/></patternFill></fill></fills>'
        '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>$kenar</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="21">'
        '${xf(0, 0, 0, 0)}' // 0 normal
        '${xf(0, 1, 2, 1, hiza: orta)}' // 1 başlık
        '${xf(164, 0, 0, 1)}' // 2 para
        '${xf(0, 2, 0, 0, hiza: orta)}' // 3 büyük başlık
        '${xf(0, 1, 0, 0)}' // 4 kalın
        '${xf(166, 0, 0, 1)}' // 5 oran
        '${xf(164, 1, 3, 1)}' // 6 girdi para
        '${xf(164, 1, 4, 1)}' // 7 sonuç para
        '${xf(165, 1, 3, 1, hiza: orta)}' // 8 girdi tarih
        '${xf(0, 3, 5, 0, hiza: orta)}' // 9 imza
        '${xf(0, 0, 0, 1, hiza: solSarma)}' // 10 metin çerçeveli
        '${xf(1, 1, 3, 1, hiza: orta)}' // 11 girdi tam
        '${xf(166, 1, 3, 1)}' // 12 girdi oran
        '${xf(0, 1, 4, 1, hiza: solSarma)}' // 13 sonuç etiketi
        '${xf(0, 4, 0, 0, hiza: solSarma)}' // 14 not
        '${xf(164, 1, 0, 1)}' // 15 para kalın
        '${xf(165, 0, 0, 1, hiza: orta)}' // 16 tarih
        '${xf(0, 1, 3, 1, hiza: orta)}' // 17 girdi metin
        '${xf(9, 0, 0, 1)}' // 18 yüzde
        '${xf(10, 1, 4, 1)}' // 19 yüzde kalın (0.00%)
        '${xf(1, 0, 0, 1, hiza: orta)}' // 20 tam sayı
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
}

double _k(double v) => kurus(v);

// ====================================================================== Hesaplayıcı Excel çıktıları

/// KDV hesabı (matrah, KDV, toplam, tevkifat). Girdiler sarı hücrelerde, sonuçlar formüllüdür.
Uint8List kdvXlsx({required bool dahil, required double tutar, required double oran, required int tevkifat}) {
  final x = _Xls([46, 22, 14, 22]);
  x.ust('KDV HESABI');
  final rTur = x.r;
  x.metin(0, 'Hesaplama türü', _sMetin);
  x.metin(1, dahil ? 'KDV dahil' : 'KDV hariç', _gMetin);
  x.liste('B$rTur', ['KDV hariç', 'KDV dahil']);
  x.satir();
  final rTutar = x.r;
  x.metin(0, 'Tutar (TL)', _sMetin);
  x.sayi(1, tutar, _gPara);
  x.satir();
  final rOran = x.r;
  x.metin(0, 'KDV oranı (%)', _sMetin);
  x.sayi(1, oran, _gOran);
  x.satir();
  final rTev = x.r;
  x.metin(0, 'Tevkifat payı (x/10, yoksa 0)', _sMetin);
  x.sayi(1, tevkifat.toDouble(), _gTam);
  x.satir();
  x.satir();

  final matrah = _k(dahil ? tutar / (1 + oran / 100) : tutar);
  final kdv = _k(dahil ? tutar - matrah : tutar * oran / 100);
  final tev = _k(kdv * tevkifat / 10);
  final rMatrah = x.r;
  x.metin(0, 'KDV hariç tutar (matrah)', _sMetin);
  x.formul(1, 'ROUND(IF(B$rTur="KDV dahil",B$rTutar/(1+B$rOran/100),B$rTutar),2)', matrah, _sPara);
  x.satir();
  final rKdv = x.r;
  x.metin(0, 'KDV', _sMetin);
  x.formul(1, 'ROUND(IF(B$rTur="KDV dahil",B$rTutar-B$rMatrah,B$rTutar*B$rOran/100),2)', kdv, _sPara);
  x.satir();
  x.metin(0, 'KDV dahil toplam', _sEtiket);
  x.formul(1, 'B$rMatrah+B$rKdv', _k(matrah + kdv), _sSonuc);
  x.satir();
  final rTevKdv = x.r;
  x.metin(0, 'Alıcının sorumlu olduğu KDV (tevkifat)', _sMetin);
  x.formul(1, 'ROUND(B$rKdv*B$rTev/10,2)', tev, _sPara);
  x.satir();
  final rSatici = x.r;
  x.metin(0, 'Satıcının beyan edeceği KDV', _sMetin);
  x.formul(1, 'B$rKdv-B$rTevKdv', _k(kdv - tev), _sPara);
  x.satir();
  x.metin(0, 'Satıcıya ödenecek (matrah + kalan KDV)', _sEtiket);
  x.formul(1, 'B$rMatrah+B$rSatici', _k(matrah + kdv - tev), _sSonuc);
  x.satir();
  x.alt();
  return x.bitir('KDV');
}

/// Aynı fişte iki KDV oranı: genel toplam ve toplam KDV'den her oranın matrahı.
Uint8List ikiOranliKdvXlsx({required double toplam, required double kdv, required double oran1, required double oran2}) {
  final x = _Xls([40, 20, 20, 26]);
  x.ust('İKİ BİLİNMEYENLİ KDV (KARIŞIK ORANLI FİŞ)');
  final rT = x.r;
  x.metin(0, 'Genel toplam, KDV dahil (TL)', _sMetin);
  x.sayi(1, toplam, _gPara);
  x.satir();
  final rK = x.r;
  x.metin(0, 'Toplam KDV tutarı (TL)', _sMetin);
  x.sayi(1, kdv, _gPara);
  x.satir();
  final rO1 = x.r;
  x.metin(0, '1. oran (%)', _sMetin);
  x.sayi(1, oran1, _gOran);
  x.satir();
  final rO2 = x.r;
  x.metin(0, '2. oran (%)', _sMetin);
  x.sayi(1, oran2, _gOran);
  x.satir();
  x.satir();

  final a = oran1 / 100, b = oran2 / 100;
  final m = toplam - kdv;
  final y = oran1 == oran2 ? 0.0 : (kdv - m * a) / (b - a);
  final xm = m - y;
  final rM = x.r;
  x.metin(0, 'Toplam matrah (toplam - KDV)', _sMetin);
  x.formul(1, 'B$rT-B$rK', _k(m), _sPara);
  x.satir();
  final rY = x.r;
  x.metin(0, '2. orandaki matrah', _sMetin);
  x.formul(1, 'ROUND(IF(B$rO2=B$rO1,0,(B$rK-B$rM*B$rO1/100)/((B$rO2-B$rO1)/100)),2)', _k(y), _sPara);
  x.satir();
  final rX = x.r;
  x.metin(0, '1. orandaki matrah', _sMetin);
  x.formul(1, 'ROUND(B$rM-B$rY,2)', _k(xm), _sPara);
  x.satir();
  x.satir();
  for (final (i, h) in ['Oran (%)', 'Matrah', 'KDV', 'Genel toplam (matrah + KDV)'].indexed) {
    x.metin(i, h, _sBaslik);
  }
  x.satir(yukseklik: 30);
  final r1 = x.r;
  x.formul(0, 'B$rO1', oran1, _sOran);
  x.formul(1, 'B$rX', _k(xm), _sPara);
  x.formul(2, 'ROUND(B$r1*A$r1/100,2)', _k(_k(xm) * a), _sPara);
  x.formul(3, 'B$r1+C$r1', _k(_k(xm) + _k(_k(xm) * a)), _sSonuc);
  x.satir();
  final r2 = x.r;
  x.formul(0, 'B$rO2', oran2, _sOran);
  x.formul(1, 'B$rY', _k(y), _sPara);
  x.formul(2, 'ROUND(B$r2*A$r2/100,2)', _k(_k(y) * b), _sPara);
  x.formul(3, 'B$r2+C$r2', _k(_k(y) + _k(_k(y) * b)), _sSonuc);
  x.satir();
  final tm = _k(_k(xm) + _k(y));
  final tk = _k(_k(_k(xm) * a) + _k(_k(y) * b));
  x.metin(0, 'Toplam', _sEtiket);
  x.formul(1, 'B$r1+B$r2', tm, _sParaKalin);
  x.formul(2, 'C$r1+C$r2', tk, _sParaKalin);
  x.formul(3, 'D$r1+D$r2', _k(tm + tk), _sSonuc);
  x.satir();
  x.alt();
  return x.bitir('İki oranlı KDV');
}

/// Matrah (veya toplam) ile KDV tutarından oran bulma.
Uint8List kdvOraniBulXlsx({required bool toplamla, required double tutar, required double kdv}) {
  final x = _Xls([46, 22, 14, 22]);
  x.ust('KDV ORANI BULMA');
  final rTur = x.r;
  x.metin(0, 'Girilen tutarın türü', _sMetin);
  x.metin(1, toplamla ? 'Toplam' : 'Matrah', _gMetin);
  x.liste('B$rTur', ['Matrah', 'Toplam']);
  x.satir();
  final rT = x.r;
  x.metin(0, 'Tutar (TL)', _sMetin);
  x.sayi(1, tutar, _gPara);
  x.satir();
  final rK = x.r;
  x.metin(0, 'KDV tutarı (TL)', _sMetin);
  x.sayi(1, kdv, _gPara);
  x.satir();
  x.satir();
  final m = toplamla ? tutar - kdv : tutar;
  final oran = m == 0 ? 0.0 : kdv / m * 100;
  final rM = x.r;
  x.metin(0, 'KDV hariç tutar (matrah)', _sMetin);
  x.formul(1, 'IF(B$rTur="Toplam",B$rT-B$rK,B$rT)', _k(m), _sPara);
  x.satir();
  final rO = x.r;
  x.metin(0, 'Hesaplanan KDV oranı (%)', _sEtiket);
  x.formul(1, 'IF(B$rM=0,0,B$rK/B$rM*100)', oran, _sSonuc);
  x.satir();
  final yakin = [1.0, 10.0, 20.0].reduce((p, q) => (oran - p).abs() < (oran - q).abs() ? p : q);
  x.metin(0, 'En yakın yasal oran (%)', _sMetin);
  x.formul(1, 'IF(ABS(B$rO-1)<=MIN(ABS(B$rO-10),ABS(B$rO-20)),1,IF(ABS(B$rO-10)<=ABS(B$rO-20),10,20))', yakin, _sTam);
  x.satir();
  x.alt();
  return x.bitir('KDV oranı');
}

/// Dilimli gelir vergisi: her dilimin matrahı ve vergisi formülle hesaplanır.
Uint8List gelirVergisiXlsx({required int yil, required double matrah, required List<(double, double)> dilimler, String tarife = 'ÜCRET TARİFESİ'}) {
  final x = _Xls([14, 18, 18, 10, 20, 20]);
  x.ust('GELİR VERGİSİ HESABI ($yil, $tarife)');
  final rM = x.r;
  x.metin(0, 'Yıllık gelir vergisi matrahı (TL)', _sMetin);
  x.birlestir('A$rM:D$rM');
  x.metin(1, '', _sMetin);
  x.metin(2, '', _sMetin);
  x.metin(3, '', _sMetin);
  x.sayi(4, matrah, _gPara);
  x.satir();
  x.satir();
  for (final (i, h) in ['Dilim', 'Alt sınır', 'Üst sınır', 'Oran', 'Dilimdeki matrah', 'Vergi'].indexed) {
    x.metin(i, h, _sBaslik);
  }
  x.satir(yukseklik: 24);
  final ilk = x.r;
  var alt = 0.0;
  var kalanToplam = 0.0;
  var vergiToplam = 0.0;
  for (final (i, d) in dilimler.indexed) {
    final ust = d.$1 >= 1e17 ? 999999999999.0 : d.$1;
    final dilimde = (matrah < ust ? matrah : ust) - alt;
    final dm = dilimde < 0 ? 0.0 : dilimde;
    final v = _k(dm * d.$2);
    kalanToplam += dm;
    vergiToplam += v;
    x.metin(0, '${i + 1}. dilim', _sMetin);
    x.sayi(1, alt, _sPara);
    x.sayi(2, ust, _sPara);
    x.sayi(3, d.$2, _sYuzde);
    x.formul(4, 'MAX(0,MIN(\$E\$$rM,C${x.r})-B${x.r})', dm, _sPara);
    x.formul(5, 'ROUND(E${x.r}*D${x.r},2)', v, _sPara);
    x.satir();
    alt = ust;
  }
  final son = x.r - 1;
  x.metin(0, 'Toplam', _sEtiket);
  x.metin(1, '', _sEtiket);
  x.metin(2, '', _sEtiket);
  x.metin(3, '', _sEtiket);
  x.formul(4, 'SUM(E$ilk:E$son)', _k(kalanToplam), _sParaKalin);
  x.formul(5, 'SUM(F$ilk:F$son)', _k(vergiToplam), _sSonuc);
  final rT = x.r;
  x.satir();
  x.satir();
  x.metin(0, 'Toplam gelir vergisi', _sEtiket);
  x.birlestir('A${x.r}:E${x.r}');
  for (var i = 1; i < 5; i++) {
    x.metin(i, '', _sEtiket);
  }
  x.formul(5, 'F$rT', _k(vergiToplam), _sSonuc);
  x.satir();
  x.metin(0, 'Ortalama vergi oranı', _sMetin);
  x.birlestir('A${x.r}:E${x.r}');
  for (var i = 1; i < 5; i++) {
    x.metin(i, '', _sMetin);
  }
  x.formul(5, 'IF(E$rM=0,0,F$rT/E$rM)', matrah == 0 ? 0 : vergiToplam / matrah, _sYuzdeKalin);
  x.satir();
  x.metin(0, 'Vergi sonrası kalan', _sMetin);
  x.birlestir('A${x.r}:E${x.r}');
  for (var i = 1; i < 5; i++) {
    x.metin(i, '', _sMetin);
  }
  x.formul(5, 'E$rM-F$rT', _k(matrah - vergiToplam), _sPara);
  x.satir();
  x.alt();
  return x.bitir('Gelir vergisi');
}

/// Damga vergisi: tutar x binde oran.
Uint8List damgaXlsx({required String tur, required double tutar, required double binde}) {
  final x = _Xls([46, 22, 14, 22]);
  x.ust('DAMGA VERGİSİ HESABI');
  x.metin(0, 'Kâğıdın türü', _sMetin);
  x.metin(1, tur, _gMetin);
  x.satir();
  final rT = x.r;
  x.metin(0, 'Kâğıdın parasal tutarı (TL)', _sMetin);
  x.sayi(1, tutar, _gPara);
  x.satir();
  final rO = x.r;
  x.metin(0, 'Oran (binde)', _sMetin);
  x.sayi(1, binde, _gOran);
  x.satir();
  x.satir();
  x.metin(0, 'Damga vergisi', _sEtiket);
  x.formul(1, 'ROUND(B$rT*B$rO/1000,2)', _k(tutar * binde / 1000), _sSonuc);
  x.satir();
  x.alt();
  return x.bitir('Damga vergisi');
}

/// Net-brüt maaş: 12 aylık tablo (değerler bordro hesap motorundan gelir, toplamlar formüllüdür).
Uint8List maasXlsx({required int yil, required bool netGirildi, required double maas, required List<List<double>> aylar}) {
  // aylar: [brüt, sgk+işsizlik, gelir vergisi, damga, net, işveren maliyeti]
  const aylarAd = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  final x = _Xls([16, 18, 18, 18, 16, 18, 20]);
  x.ust('${netGirildi ? 'NET MAAŞTAN BRÜTE' : 'BRÜT MAAŞTAN NETE'} ($yil)');
  x.metin(0, netGirildi ? 'Girilen net maaş (TL)' : 'Girilen brüt maaş (TL)', _sMetin);
  x.birlestir('A${x.r}:C${x.r}');
  x.metin(1, '', _sMetin);
  x.metin(2, '', _sMetin);
  x.sayi(3, maas, _gPara);
  x.satir();
  x.metin(0, 'Aylık değerler bordro hesap motorundan alınmıştır (kümülatif gelir vergisi matrahı, asgari ücret istisnaları). Net maaştan brüte geri hesap formülle yapılamadığı için tablo değerlidir; toplamlar formüllüdür.', _sNot);
  x.birlestir('A${x.r}:G${x.r}');
  x.satir(yukseklik: 30);
  x.satir();
  for (final (i, h) in ['Ay', 'Brüt', 'SGK + İşsizlik', 'Gelir vergisi', 'Damga', 'Net', 'İşveren maliyeti'].indexed) {
    x.metin(i, h, _sBaslik);
  }
  x.satir(yukseklik: 24);
  final ilk = x.r;
  final top = List<double>.filled(6, 0);
  for (var i = 0; i < aylar.length && i < 12; i++) {
    x.metin(0, aylarAd[i], _sMetin);
    for (var j = 0; j < 6; j++) {
      x.sayi(1 + j, aylar[i][j], _sPara);
      top[j] += aylar[i][j];
    }
    x.satir();
  }
  final son = x.r - 1;
  x.metin(0, 'Toplam', _sEtiket);
  for (var j = 0; j < 6; j++) {
    x.formul(1 + j, 'SUM(${_kol(1 + j)}$ilk:${_kol(1 + j)}$son)', _k(top[j]), j == 4 ? _sSonuc : _sParaKalin);
  }
  x.satir();
  x.alt();
  return x.bitir('Net brüt maaş');
}

/// Gecikme veya pişmanlık zammı: ay sayısı ve zam formülle hesaplanır.
Uint8List zamXlsx({required bool pismanlik, required double tutar, required DateTime vade, required DateTime odeme, required double aylikOran}) {
  final x = _Xls([46, 22, 14, 22]);
  x.ust(pismanlik ? 'PİŞMANLIK ZAMMI HESABI' : 'GECİKME ZAMMI HESABI');
  final rT = x.r;
  x.metin(0, pismanlik ? 'Vergi aslı (TL)' : 'Borç tutarı (TL)', _sMetin);
  x.sayi(1, tutar, _gPara);
  x.satir();
  final rV = x.r;
  x.metin(0, 'Vade tarihi', _sMetin);
  x.sayi(1, _serial(vade), _gTarih);
  x.satir();
  final rO = x.r;
  x.metin(0, 'Ödeme tarihi', _sMetin);
  x.sayi(1, _serial(odeme), _gTarih);
  x.satir();
  final rR = x.r;
  x.metin(0, 'Aylık oran (%)', _sMetin);
  x.sayi(1, aylikOran, _gOran);
  x.satir();
  x.satir();
  int ay = 0;
  final v = DateTime(vade.year, vade.month, vade.day);
  final o = DateTime(odeme.year, odeme.month, odeme.day);
  if (o.isAfter(v)) {
    ay = (o.year - v.year) * 12 + o.month - v.month + (o.day > v.day ? 1 : 0);
    if (ay < 1) ay = 1;
  }
  final zam = _k(tutar * aylikOran / 100 * ay);
  final rA = x.r;
  x.metin(0, 'Geçen süre (ay, kesirler tam ay sayılır)', _sMetin);
  x.formul(1, 'IF(B$rO<=B$rV,0,MAX(1,(YEAR(B$rO)-YEAR(B$rV))*12+MONTH(B$rO)-MONTH(B$rV)+IF(DAY(B$rO)>DAY(B$rV),1,0)))', ay.toDouble(), _sTam);
  x.satir();
  final rZ = x.r;
  x.metin(0, pismanlik ? 'Pişmanlık zammı' : 'Gecikme zammı', _sEtiket);
  x.formul(1, 'ROUND(B$rT*B$rR/100*B$rA,2)', zam, _sSonuc);
  x.satir();
  x.metin(0, 'Toplam ödenecek', _sEtiket);
  x.formul(1, 'B$rT+B$rZ', _k(tutar + zam), _sSonuc);
  x.satir();
  x.alt();
  return x.bitir(pismanlik ? 'Pişmanlık zammı' : 'Gecikme zammı');
}
