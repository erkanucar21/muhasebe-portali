import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'bordro_cikti.dart' show bordroKaydet, tl, bordroAylar;
import 'bordro_cikti.dart' show PersonelBordro, bordroPdf;
import 'cikis_tazminat.dart';
import 'tazminat.dart' show tazminatCetveliPdf;
import 'firmalar.dart';
import 'is_sozlesmesi.dart';
import 'personel_takip.dart';

enum CikisBelgesi { istifa, ibraname, calisma }

String _t(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _buyuk(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

String _dosyaAdi(String s) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosuCGIOSU';
  var r = s;
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
}

const _alacaklar = [
  'Ücret',
  'Fazla mesai ücreti',
  'Hafta tatili ve genel tatil ücreti',
  'Yıllık izin ücreti',
  'İkramiye / prim',
  'Kıdem tazminatı',
  'İhbar tazminatı',
];

pw.Widget _par(String m, {double boyut = 11.5, double alt = 10, bool kalin = false, pw.TextAlign hiza = pw.TextAlign.justify}) => pw.Padding(
      padding: pw.EdgeInsets.only(bottom: alt),
      child: pw.Text(m, textAlign: hiza, style: pw.TextStyle(fontSize: boyut, lineSpacing: 3, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

Future<void> _pdfYaz(String dosya, List<pw.Widget> icerik) async => bordroKaydet(dosya, await _pdfBayt(icerik), 'pdf');

Future<Uint8List> _pdfBayt(List<pw.Widget> icerik) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()),
  );
  doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.fromLTRB(56, 56, 56, 48), build: (c) => icerik));
  return doc.save();
}

pw.Widget _imzaKutusu(String baslik, String ad, {String? alt}) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(baslik, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      if (ad.isNotEmpty) pw.Text(ad, style: const pw.TextStyle(fontSize: 11)),
      if (alt != null) pw.Text(alt, style: const pw.TextStyle(fontSize: 9.5)),
      pw.SizedBox(height: 8),
      pw.Text('İmza:', style: const pw.TextStyle(fontSize: 11)),
    ]);

List<pw.Widget> _ibranameIcerik({required String firmaAd, required String sicil, required String g0, required String c0, required String isGorev, required String liste, required String tutar, required String ad, required String tc}) => [
                            _par('İBRANAME', kalin: true, boyut: 14, hiza: pw.TextAlign.center, alt: 20),
                            _par('$firmaAd${sicil.isEmpty ? '' : ' (SGK sicil no: $sicil)'} işyerinde $g0 - $c0 tarihleri arasında $isGorev olarak çalıştım. İş sözleşmem $c0 tarihinde sona ermiştir.'),
                            _par('Sözleşmenin sona ermesi nedeniyle${liste.isEmpty ? '' : ' $liste'} ile ilgili tüm hak ve alacaklarım${tutar.isEmpty ? '' : ' toplam net $tutar TL tutarında'} tarafıma eksiksiz olarak ödenmiştir.'),
                            _par('Bu ödemeler dışında işverenden ve işyeri yetkililerinden ücret, fazla mesai, hafta tatili, ulusal bayram ve genel tatil ücreti, yıllık izin ücreti, ikramiye, prim, kıdem ve ihbar tazminatı veya başka bir ad altında hiçbir alacağım kalmamıştır.'),
                            _par('Bu nedenle işvereni ve işyeri yetkililerini, varsa hak ve alacaklarımdan ibra ediyorum. İşbu ibranameyi hiçbir baskı altında kalmaksızın, serbest irademle okuyarak imzaladım.', alt: 30),
                            _par('Tarih: ....../....../........', alt: 28),
                            pw.Align(alignment: pw.Alignment.centerRight, child: _imzaKutusu('İŞÇİ', ad, alt: 'T.C. Kimlik No: $tc')),
                          ];

List<pw.Widget> _calismaIcerik({required String firmaAd, required String sicil, required String g0, required String c0, required String isGorev, required String ad, required String tc}) => [
                            _par('ÇALIŞMA BELGESİ', kalin: true, boyut: 14, hiza: pw.TextAlign.center, alt: 24),
                            _par('Tarih: ${_t(DateTime.now())}', hiza: pw.TextAlign.right, alt: 20),
                            _par('$ad (T.C. Kimlik No: $tc), işyerimizde $g0 - $c0 tarihleri arasında $isGorev olarak çalışmıştır.'),
                            _par('İş sözleşmesi $c0 tarihinde sona ermiştir.'),
                            _par('İşbu belge, 4857 sayılı İş Kanunu m.28 uyarınca işçinin talebi üzerine düzenlenmiştir.', alt: 36),
                            pw.Align(
                              alignment: pw.Alignment.centerRight,
                              child: _imzaKutusu('İŞVEREN / VEKİL', firmaAd, alt: sicil.isEmpty ? null : 'İşyeri SGK sicil no: $sicil\nKaşe / İmza'),
                            ),
                          ];

/// Personelin yanındaki "Belgeler" menüsü: iş sözleşmesi, istifa dilekçesi, ibraname, çalışma belgesi.
Widget personelBelgeMenusu(BuildContext context, Personel p) => PopupMenuButton<String>(
      tooltip: 'Belgeler (iş sözleşmesi, istifa, ibraname...)',
      icon: const Icon(Icons.description_outlined),
      onSelected: (v) {
        switch (v) {
          case 'sozlesme':
            sozlesmeIndir(context, p);
          case 'istifa':
            cikisBelgesiIndir(context, p, CikisBelgesi.istifa);
          case 'ibraname':
            cikisBelgesiIndir(context, p, CikisBelgesi.ibraname);
          case 'calisma':
            cikisBelgesiIndir(context, p, CikisBelgesi.calisma);
          case 'paket':
            ayrilisPaketiIndir(context, p);
        }
      },
      itemBuilder: (c) => const [
        PopupMenuItem(value: 'sozlesme', child: Text('İş sözleşmesi')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'istifa', child: Text('İstifa dilekçesi')),
        PopupMenuItem(value: 'ibraname', child: Text('İbraname')),
        PopupMenuItem(value: 'calisma', child: Text('Çalışma belgesi')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'paket', child: Text('Ayrılış paketi (ZIP)')),
      ],
    );

Future<void> cikisBelgesiIndir(BuildContext context, Personel p, CikisBelgesi tur) async {
  final mesaj = ScaffoldMessenger.of(context);
  final firma = FirmaDeposu.ornek.bul(p.firmaId);
  final meslekAd = p.meslek.contains(' - ') ? p.meslek.substring(p.meslek.indexOf(' - ') + 3) : p.meslek;
  final baslik = switch (tur) { CikisBelgesi.istifa => 'İstifa dilekçesi', CikisBelgesi.ibraname => 'İbraname', CikisBelgesi.calisma => 'Çalışma belgesi' };
  final gorev = TextEditingController(text: meslekAd);
  final toplam = TextEditingController();
  var cikis = p.cikis ?? DateTime.now();
  var ihbarUy = true;
  final secili = <String>{'Ücret', 'Fazla mesai ücreti', 'Hafta tatili ve genel tatil ücreti', 'Yıllık izin ücreti'};
  String? hata;
  var mesgul = false;
  var yansit = false;
  var elle = false;
  var hesaplaniyor = false;
  CikisHesabi? hesap;
  String? hesapNot;

  Future<void> doldur(void Function(void Function()) setD) async {
    if (tur != CikisBelgesi.ibraname) return;
    setD(() => hesaplaniyor = true);
    try {
      final h = await cikisHesapla(p, cikis, kidem: secili.contains('Kıdem tazminatı'), ihbar: secili.contains('İhbar tazminatı'));
      setD(() {
        hesap = h;
        hesapNot = h.not;
        if (h.maasNet > 0 && !elle) toplam.text = h.toplamNet.toStringAsFixed(2).replaceAll('.', ',');
      });
    } catch (e) {
      setD(() => hesapNot = 'Bordro hesaplanamadı: $e');
    }
    setD(() => hesaplaniyor = false);
  }

  var ilkDoldur = true;

  final tamam = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (c, setD) {
        if (ilkDoldur) {
          ilkDoldur = false;
          Future.microtask(() => doldur(setD));
        }
        return AlertDialog(
        title: Text('$baslik: ${p.ad}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: c, initialDate: cikis, firstDate: DateTime(1990), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                  if (d != null) {
                    setD(() => cikis = d);
                    doldur(setD);
                  }
                },
                icon: const Icon(Icons.logout, size: 18),
                label: Text('İşten çıkış tarihi: ${_t(cikis)}'),
              ),
              const SizedBox(height: 8),
              TextField(controller: gorev, decoration: const InputDecoration(labelText: 'Görevi')),
              if (tur == CikisBelgesi.istifa)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: ihbarUy,
                  onChanged: (v) => setD(() => ihbarUy = v ?? true),
                  title: const Text('İhbar süresine uyduğunu belirt'),
                ),
              if (tur == CikisBelgesi.ibraname) ...[
                const SizedBox(height: 8),
                const Text('Ödenen alacaklar', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final a in _alacaklar)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: secili.contains(a),
                    onChanged: (v) {
                      setD(() => v == true ? secili.add(a) : secili.remove(a));
                      if (a == 'Kıdem tazminatı' || a == 'İhbar tazminatı') doldur(setD);
                    },
                    title: Text(a),
                  ),
                TextField(
                  controller: toplam,
                  onChanged: (_) => elle = true,
                  decoration: InputDecoration(
                    labelText: 'Toplam net ödenen tutar (TL, boşsa yazılmaz)',
                    suffixIcon: hesaplaniyor
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton(
                            tooltip: 'Çıkış ayı bordrosundan yeniden getir',
                            icon: const Icon(Icons.refresh),
                            onPressed: () {
                              elle = false;
                              doldur(setD);
                            },
                          ),
                  ),
                ),
                if (hesap != null && hesap!.maasNet > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${bordroAylar[cikis.month - 1]} ${cikis.year} bordrosu net: ${tl(hesap!.maasNet)} TL'
                      '${hesap!.kidemBrut > 0 ? '\nKıdem tazminatı: brüt ${tl(hesap!.kidemBrut)}, damga ${tl(hesap!.kidemDamga)}, net ${tl(hesap!.kidemNet)} TL' : ''}'
                      '${hesap!.ihbarBrut > 0 ? '\nİhbar tazminatı (${hesap!.ihbarHafta} hafta): brüt ${tl(hesap!.ihbarBrut)}, GV ${tl(hesap!.ihbarGv)}, damga ${tl(hesap!.ihbarDamga)}, net ${tl(hesap!.ihbarNet)} TL' : ''}'
                      '\nToplam net: ${tl(hesap!.toplamNet)} TL (yıllık izin ve fazla mesai ücreti dahil değildir, varsa elle ekle)',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                if (hesapNot != null) Text(hesapNot!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
                if (secili.contains('Kıdem tazminatı') || secili.contains('İhbar tazminatı'))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: yansit,
                    onChanged: (v) => setD(() => yansit = v ?? false),
                    title: const Text('Kıdem ve ihbar tazminatını çıkış ayı bordrosuna yansıt'),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Dikkat: İbraname, ödeme gerçekten yapılmadan ve çoğu zaman iş sözleşmesinin bitiminden en az bir ay geçmeden geçerli sayılmaz (TBK m.420). '
                  'Ödemenin banka yoluyla yapılması tavsiye edilir. İmza tarihi boş bırakılır, imzalanırken yazılır.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
              if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: mesgul
                ? null
                : () async {
                    setD(() {
                      mesgul = true;
                      hata = null;
                    });
                    try {
                      final firmaAd = _buyuk(firma?.unvan ?? '');
                      final ad = _buyuk(p.ad);
                      final isGorev = gorev.text.trim().isEmpty ? '...........................' : gorev.text.trim();
                      final tc = p.tc.isEmpty ? '...........................' : p.tc;
                      final sicil = firma?.sgkSicilNo ?? '';
                      final c0 = _t(cikis), g0 = _t(p.giris);
                      final dosya = '${_dosyaAdi(baslik.toLowerCase())}_${_dosyaAdi(p.ad)}';
                      switch (tur) {
                        case CikisBelgesi.istifa:
                          await _pdfYaz(dosya, [
                            _par(firmaAd, kalin: true, hiza: pw.TextAlign.center, alt: 2),
                            _par('YÖNETİMİNE', kalin: true, hiza: pw.TextAlign.center, alt: 24),
                            _par('Tarih: ....../....../........', hiza: pw.TextAlign.right, alt: 24),
                            _par('İşyerinizde $g0 tarihinden bu yana $isGorev olarak çalışmaktayım. Kendi isteğimle, $c0 tarihi itibarıyla işyerinizdeki görevimden ayrılıyorum.'),
                            if (ihbarUy) _par('Bu tarihe kadar iş sözleşmemden doğan ihbar süresine uyacağımı ve devir teslim işlemlerini eksiksiz yapacağımı bildiririm.'),
                            _par('Çalıştığım süreye ait ücretimin ve varsa kullanmadığım yıllık izin ücretimin hesaplanarak ödenmesini, işten ayrılış bildirgemin SGK\'ya verilmesini saygılarımla arz ederim.', alt: 36),
                            pw.Align(alignment: pw.Alignment.centerRight, child: _imzaKutusu(ad, 'T.C. Kimlik No: $tc')),
                          ]);
                        case CikisBelgesi.ibraname:
                          if (yansit && hesap != null && hesap!.maasNet > 0 && (hesap!.kidemBrut > 0 || hesap!.ihbarBrut > 0)) {
                            await cikisBordroyaYansit(p, cikis, hesap!);
                          }
                          await _pdfYaz(dosya, _ibranameIcerik(firmaAd: firmaAd, sicil: sicil, g0: g0, c0: c0, isGorev: isGorev, liste: _alacaklar.where(secili.contains).join(', '), tutar: toplam.text.trim(), ad: ad, tc: tc));
                        case CikisBelgesi.calisma:
                          await _pdfYaz(dosya, _calismaIcerik(firmaAd: firmaAd, sicil: sicil, g0: g0, c0: c0, isGorev: isGorev, ad: ad, tc: tc));
                      }
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      setD(() {
                        mesgul = false;
                        hata = 'PDF oluşturulamadı: $e';
                      });
                    }
                  },
            child: Text(mesgul ? 'Hazırlanıyor...' : 'PDF indir'),
          ),
        ],
      );
      },
    ),
  );
  if (tamam == true) mesaj.showSnackBar(SnackBar(content: Text('$baslik indirildi.')));
}

/// Çıkış verilen personel için tek ZIP: ibraname, çalışma belgesi, ücret pusulası ve (varsa) tazminat cetveli.
Future<void> ayrilisPaketiIndir(BuildContext context, Personel p) async {
  final mesaj = ScaffoldMessenger.of(context);
  final firma = FirmaDeposu.ornek.bul(p.firmaId);
  final meslekAd = p.meslek.contains(' - ') ? p.meslek.substring(p.meslek.indexOf(' - ') + 3) : p.meslek;
  final gorev = TextEditingController(text: meslekAd);
  var cikis = p.cikis ?? DateTime.now();
  var kidem = false, ihbar = false, yansit = false, mesgul = false;
  String? hata;

  final tamam = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: Text('Ayrılış paketi: ${p.ad}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'ZIP içinde: ibraname, çalışma belgesi, çıkış ayı ücret pusulası ve seçersen tazminat hesap cetveli. '
                'İbranamedeki toplam net rakam çıkış ayı bordrosundan gelir.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: c, initialDate: cikis, firstDate: DateTime(1990), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                  if (d != null) setD(() => cikis = d);
                },
                icon: const Icon(Icons.logout, size: 18),
                label: Text('İşten çıkış tarihi: ${_t(cikis)}'),
              ),
              const SizedBox(height: 8),
              TextField(controller: gorev, decoration: const InputDecoration(labelText: 'Görevi')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: kidem,
                onChanged: (v) => setD(() => kidem = v ?? false),
                title: const Text('Kıdem tazminatı hesapla'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: ihbar,
                onChanged: (v) => setD(() => ihbar = v ?? false),
                title: const Text('İhbar tazminatı hesapla'),
              ),
              if (kidem || ihbar)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: yansit,
                  onChanged: (v) => setD(() => yansit = v ?? false),
                  title: const Text('Tazminatı çıkış ayı bordrosuna yansıt'),
                ),
              if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: mesgul
                ? null
                : () async {
                    setD(() {
                      mesgul = true;
                      hata = null;
                    });
                    try {
                      final h = await cikisHesapla(p, cikis, kidem: kidem, ihbar: ihbar);
                      final firmaAd = _buyuk(firma?.unvan ?? '');
                      final ad = _buyuk(p.ad);
                      final isGorev = gorev.text.trim().isEmpty ? '...........................' : gorev.text.trim();
                      final tc = p.tc.isEmpty ? '...........................' : p.tc;
                      final sicil = firma?.sgkSicilNo ?? '';
                      final c0 = _t(cikis), g0 = _t(p.giris);
                      final kisi = _dosyaAdi(p.ad);
                      final alacak = [..._alacaklar.take(5), if (h.kidemBrut > 0) 'Kıdem tazminatı', if (h.ihbarBrut > 0) 'İhbar tazminatı'];
                      final dosyalar = <String, Uint8List>{};
                      dosyalar['ibraname_$kisi.pdf'] = await _pdfBayt(_ibranameIcerik(
                        firmaAd: firmaAd,
                        sicil: sicil,
                        g0: g0,
                        c0: c0,
                        isGorev: isGorev,
                        liste: alacak.join(', '),
                        tutar: h.maasNet > 0 ? h.toplamNet.toStringAsFixed(2).replaceAll('.', ',') : '',
                        ad: ad,
                        tc: tc,
                      ));
                      dosyalar['calisma_belgesi_$kisi.pdf'] = await _pdfBayt(_calismaIcerik(firmaAd: firmaAd, sicil: sicil, g0: g0, c0: c0, isGorev: isGorev, ad: ad, tc: tc));
                      final b = h.bordro;
                      if (b != null) {
                        final pb = PersonelBordro(
                          ad: p.ad,
                          tc: p.tc,
                          meslek: p.meslek,
                          sgkSicil: p.sgkSicil,
                          gelmedi: h.gelmediGun,
                          giris: p.giris,
                          cikis: cikis,
                          asgari: p.asgari,
                          netMaas: p.maasTuru != 'brut',
                          kayitliMaas: p.ucret,
                          b: b,
                          tazBrut: h.kidemBrut + h.ihbarBrut,
                          tazKesinti: h.kidemDamga + h.ihbarGv + h.ihbarDamga,
                        );
                        dosyalar['ucret_pusulasi_$kisi.pdf'] = await bordroPdf([pb], firma: firma?.unvan ?? '', yil: cikis.year, ay: cikis.month);
                      }
                      if (h.kidemBrut > 0 || h.ihbarBrut > 0) {
                        dosyalar['tazminat_cetveli_$kisi.pdf'] = await tazminatCetveliPdf(
                          kapsam: h.kidemBrut > 0 && h.ihbarBrut > 0 ? 'ikisi' : (h.kidemBrut > 0 ? 'kidem' : 'ihbar'),
                          firma: firma?.unvan ?? '',
                          kisi: p.ad,
                          giris: p.giris,
                          cikis: cikis,
                          sure: h.sure,
                          giydirilmis: h.brut,
                          tavan: h.tavan,
                          esas: h.esas,
                          kidemVar: h.kidemVar,
                          kidemHak: kidem,
                          kidemBrut: h.kidemBrut,
                          kidemDamga: h.kidemDamga,
                          ihbarHak: ihbar,
                          hafta: h.ihbarHafta,
                          ihbarBrut: h.ihbarBrut,
                          ihbarGv: h.ihbarGv,
                          ihbarDamga: h.ihbarDamga,
                        );
                        if (yansit && h.maasNet > 0) await cikisBordroyaYansit(p, cikis, h);
                      }
                      final arsiv = Archive();
                      dosyalar.forEach((ad, veri) => arsiv.addFile(ArchiveFile(ad, veri.length, veri)));
                      await bordroKaydet('ayrilis_paketi_$kisi', Uint8List.fromList(ZipEncoder().encode(arsiv)!), 'zip');
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      setD(() {
                        mesgul = false;
                        hata = 'Paket oluşturulamadı: $e';
                      });
                    }
                  },
            child: Text(mesgul ? 'Hazırlanıyor...' : 'ZIP indir'),
          ),
        ],
      ),
    ),
  );
  if (tamam == true) mesaj.showSnackBar(const SnackBar(content: Text('Ayrılış paketi indirildi.')));
}
