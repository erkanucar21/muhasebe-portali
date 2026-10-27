import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart' show bordroKaydet;

/// Büronun kurumsal kimliği: PDF antetleri, portal başlığı ve e-posta imzası buradan gelir.
class Marka {
  String ad, unvan, adres, tel, eposta, web, renk1, renk2, epostaImza;
  String? logo, kase; // base64 (PNG/JPG)
  Marka({
    required this.ad,
    required this.unvan,
    required this.adres,
    required this.tel,
    required this.eposta,
    required this.web,
    required this.renk1,
    required this.renk2,
    required this.epostaImza,
    this.logo,
    this.kase,
  });

  factory Marka.varsayilan() => Marka(
        ad: 'ERKAN UÇAR',
        unvan: 'Serbest Muhasebeci Mali Müşavir',
        adres: '',
        tel: '',
        eposta: '',
        web: '',
        renk1: '#41408E',
        renk2: '#3B7BD4',
        epostaImza: 'Saygılarımla,\nSMMM Erkan Uçar',
      );

  Map<String, dynamic> toJson() => {
        'ad': ad,
        'unvan': unvan,
        'adres': adres,
        'tel': tel,
        'eposta': eposta,
        'web': web,
        'renk1': renk1,
        'renk2': renk2,
        'epostaImza': epostaImza,
        'logo': logo,
        'kase': kase,
      };

  factory Marka.fromJson(Map<String, dynamic> m) {
    final v = Marka.varsayilan();
    String s(String k, String yedek) => ((m[k] ?? yedek) as String);
    return Marka(
      ad: s('ad', v.ad),
      unvan: s('unvan', v.unvan),
      adres: s('adres', ''),
      tel: s('tel', ''),
      eposta: s('eposta', ''),
      web: s('web', ''),
      renk1: s('renk1', v.renk1),
      renk2: s('renk2', v.renk2),
      epostaImza: s('epostaImza', v.epostaImza),
      logo: m['logo'] as String?,
      kase: m['kase'] as String?,
    );
  }

  Uint8List? get logoBayt => (logo == null || logo!.isEmpty) ? null : base64Decode(logo!);
  Uint8List? get kaseBayt => (kase == null || kase!.isEmpty) ? null : base64Decode(kase!);
}

Marka marka = Marka.varsayilan();

/// Giriş yapıldıktan sonra çağrılır. Kayıt yoksa varsayılan kimlik kullanılır.
Future<void> markaYukle() async {
  try {
    final r = await Supabase.instance.client.from('buro_marka').select().eq('id', 1).maybeSingle();
    if (r != null) marka = Marka.fromJson(Map<String, dynamic>.from(r['veri'] as Map));
  } catch (_) {}
}

Color _hex(String s, Color yedek) {
  final t = s.trim().replaceAll('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return yedek;
  return Color(0xFF000000 | int.parse(t, radix: 16));
}

Color get markaRenk1 => _hex(marka.renk1, const Color(0xFF41408E));
Color get markaRenk2 => _hex(marka.renk2, const Color(0xFF3B7BD4));

PdfColor _pdfRenk(String s, String yedek) {
  final t = s.trim().replaceAll('#', '');
  return PdfColor.fromHex(RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t) ? t : yedek);
}

// ------------------------------------------------------------------ PDF parçaları
pw.Widget markaPdfLogo(double boyut) {
  final b = marka.logoBayt;
  if (b != null) {
    try {
      return pw.SizedBox(width: boyut, height: boyut, child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.contain));
    } catch (_) {}
  }
  return pw.Container(
    width: boyut,
    height: boyut,
    color: _pdfRenk(marka.renk1, '41408E'),
    child: pw.Stack(children: [
      pw.Center(child: pw.Text('M', style: pw.TextStyle(color: PdfColors.white, fontSize: boyut * 0.62, fontWeight: pw.FontWeight.bold))),
      pw.Positioned(top: boyut * 0.04, right: boyut * 0.1, child: pw.Text('m', style: pw.TextStyle(color: PdfColors.white, fontSize: boyut * 0.28, fontWeight: pw.FontWeight.bold))),
    ]),
  );
}

/// Sayfa üst bilgisi (antet).
pw.Widget markaUst() {
  final r1 = _pdfRenk(marka.renk1, '41408E'), r2 = _pdfRenk(marka.renk2, '3B7BD4');
  final iletisim = [
    if (marka.tel.trim().isNotEmpty) marka.tel.trim(),
    if (marka.eposta.trim().isNotEmpty) marka.eposta.trim(),
    if (marka.web.trim().isNotEmpty) marka.web.trim(),
  ];
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Column(children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        markaPdfLogo(34),
        pw.SizedBox(width: 9),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(marka.ad, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: r1)),
          if (marka.unvan.trim().isNotEmpty) pw.Text(marka.unvan, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ]),
        pw.Spacer(),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          for (final s in iletisim) pw.Text(s, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ]),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        pw.Expanded(flex: 3, child: pw.Container(height: 2, color: r1)),
        pw.Expanded(flex: 1, child: pw.Container(height: 2, color: r2)),
      ]),
    ]),
  );
}

/// Sayfa alt bilgisi: adres ve sayfa numarası.
pw.Widget markaAlt(pw.Context c) {
  final satir = [if (marka.adres.trim().isNotEmpty) marka.adres.trim(), if (marka.web.trim().isNotEmpty) marka.web.trim()].join('   |   ');
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 8),
    child: pw.Column(children: [
      pw.Container(height: 0.6, color: PdfColors.grey500),
      pw.SizedBox(height: 3),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Expanded(child: pw.Text(satir, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700))),
        pw.Text('Sayfa ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ]),
    ]),
  );
}

/// Yüklenmişse kaşe/imza görseli.
pw.Widget markaKase({double yukseklik = 60}) {
  final b = marka.kaseBayt;
  if (b == null) return pw.SizedBox();
  try {
    return pw.SizedBox(height: yukseklik, child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.contain));
  } catch (_) {
    return pw.SizedBox();
  }
}

// ------------------------------------------------------------------ ekran logosu
class MarkaLogo extends StatelessWidget {
  final double boyut;
  const MarkaLogo({super.key, this.boyut = 32});

  @override
  Widget build(BuildContext context) {
    final b = marka.logoBayt;
    if (b != null) return SizedBox(width: boyut, height: boyut, child: Image.memory(b, fit: BoxFit.contain));
    return Container(
      width: boyut,
      height: boyut,
      color: markaRenk1,
      child: Stack(children: [
        Center(child: Text('M', style: TextStyle(color: Colors.white, fontSize: boyut * 0.62, fontWeight: FontWeight.w800, height: 1))),
        Positioned(top: boyut * 0.04, right: boyut * 0.1, child: Text('m', style: TextStyle(color: Colors.white, fontSize: boyut * 0.28, fontWeight: FontWeight.w800, height: 1))),
      ]),
    );
  }
}

// ------------------------------------------------------------------ ayar sayfası
class MarkaSayfasi extends StatefulWidget {
  const MarkaSayfasi({super.key});
  @override
  State<MarkaSayfasi> createState() => _MarkaSayfasiState();
}

class _MarkaSayfasiState extends State<MarkaSayfasi> {
  late final Map<String, TextEditingController> _c;
  bool _kaydediyor = false;

  @override
  void initState() {
    super.initState();
    _c = {
      'ad': TextEditingController(text: marka.ad),
      'unvan': TextEditingController(text: marka.unvan),
      'adres': TextEditingController(text: marka.adres),
      'tel': TextEditingController(text: marka.tel),
      'eposta': TextEditingController(text: marka.eposta),
      'web': TextEditingController(text: marka.web),
      'renk1': TextEditingController(text: marka.renk1),
      'renk2': TextEditingController(text: marka.renk2),
      'imza': TextEditingController(text: marka.epostaImza),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _uygula() {
    marka
      ..ad = _c['ad']!.text.trim()
      ..unvan = _c['unvan']!.text.trim()
      ..adres = _c['adres']!.text.trim()
      ..tel = _c['tel']!.text.trim()
      ..eposta = _c['eposta']!.text.trim()
      ..web = _c['web']!.text.trim()
      ..renk1 = _c['renk1']!.text.trim()
      ..renk2 = _c['renk2']!.text.trim()
      ..epostaImza = _c['imza']!.text;
  }

  Future<void> _gorsel(bool logo) async {
    final r = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final b = r.files.first.bytes!;
    if (b.length > 400 * 1024) {
      _mesaj('Görsel çok büyük (${(b.length / 1024).round()} KB). 400 KB altında bir PNG/JPG kullanın.');
      return;
    }
    setState(() {
      if (logo) {
        marka.logo = base64Encode(b);
      } else {
        marka.kase = base64Encode(b);
      }
    });
  }

  Future<void> _kaydet() async {
    _uygula();
    setState(() => _kaydediyor = true);
    try {
      await Supabase.instance.client.from('buro_marka').upsert({'id': 1, 'veri': marka.toJson(), 'guncelleme': DateTime.now().toUtc().toIso8601String()});
      _mesaj('Büro kimliği kaydedildi.');
    } catch (e) {
      _mesaj('Kaydedilemedi (supabase_marka.sql çalıştırıldı mı?): $e');
    }
    if (mounted) setState(() => _kaydediyor = false);
  }

  Future<void> _ornekPdf() async {
    _uygula();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      header: (c) => markaUst(),
      footer: markaAlt,
      build: (c) => [
        pw.Text('Örnek belge', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Text('Bu sayfa, kaydettiğiniz büro kimliğinin PDF çıktılarında nasıl görüneceğini gösterir. Antet; bordro özeti, hesaplayıcı çıktıları, firma durum özeti, tazminat cetveli, mizan analizi ve personel maliyet raporunda kullanılır.'),
        pw.SizedBox(height: 30),
        pw.Align(alignment: pw.Alignment.centerRight, child: markaKase()),
      ],
    ));
    await bordroKaydet('buro_kimligi_ornek', Uint8List.fromList(await doc.save()), 'pdf');
  }

  Widget _alan(String k, String etiket, {int satir = 1, double genislik = 300}) => SizedBox(
        width: genislik,
        child: TextField(controller: _c[k], maxLines: satir, onChanged: (_) => setState(_uygula), decoration: InputDecoration(labelText: etiket, border: const OutlineInputBorder(), isDense: true)),
      );

  Widget _gorselKart(String baslik, bool logo) {
    final b = logo ? marka.logoBayt : marka.kaseBayt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (logo) MarkaLogo(boyut: 56) else (b == null ? const Text('Yüklenmedi') : SizedBox(height: 56, child: Image.memory(b))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _gorsel(logo), icon: const Icon(Icons.upload_file), label: const Text('Görsel yükle')),
            if (b != null)
              TextButton(
                onPressed: () => setState(() {
                  if (logo) {
                    marka.logo = null;
                  } else {
                    marka.kase = null;
                  }
                }),
                child: Text(logo ? 'Varsayılan logoya dön' : 'Kaldır'),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Büro kimliği', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Logo, antet bilgileri ve renkler PDF raporlarında, portal başlığında ve e-posta imzasında kullanılır. Dilekçe ve işveren belgeleri (ibraname, sözleşme vb.) mükellef adına düzenlendiği için antetsiz kalır.'),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const MarkaLogo(boyut: 40),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(marka.ad, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: markaRenk1)),
              Text(marka.unvan, style: const TextStyle(fontSize: 12)),
            ]),
            const Spacer(),
            Container(width: 60, height: 6, color: markaRenk1),
            Container(width: 20, height: 6, color: markaRenk2),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _alan('ad', 'Büro / kişi adı'),
        _alan('unvan', 'Unvan (örn. Serbest Muhasebeci Mali Müşavir)', genislik: 380),
        _alan('adres', 'Adres', genislik: 380),
        _alan('tel', 'Telefon'),
        _alan('eposta', 'E-posta'),
        _alan('web', 'Web sitesi'),
        _alan('renk1', 'Ana renk (#RRGGBB)', genislik: 180),
        _alan('renk2', 'İkinci renk (#RRGGBB)', genislik: 180),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [_gorselKart('Logo', true), _gorselKart('Kaşe / imza görseli', false)]),
      const SizedBox(height: 12),
      _alan('imza', 'E-posta imzası (bordro e-postalarının sonuna eklenir)', satir: 4, genislik: 520),
      const SizedBox(height: 16),
      Wrap(spacing: 10, children: [
        FilledButton.icon(onPressed: _kaydediyor ? null : _kaydet, icon: const Icon(Icons.save_outlined), label: const Text('Kaydet')),
        OutlinedButton.icon(onPressed: _ornekPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Örnek PDF')),
      ]),
    ]);
  }
}
