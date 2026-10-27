import 'marka.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bordro_cikti.dart' show bordroKaydet;
import 'mizan_hesap.dart';

class MizanAnaliziSayfasi extends StatefulWidget {
  const MizanAnaliziSayfasi({super.key});
  @override
  State<MizanAnaliziSayfasi> createState() => _MizanAnaliziSayfasiState();
}

class _Kayit {
  final int id;
  final Mizan mizan;
  final DateTime yukleme;
  _Kayit(this.id, this.mizan, this.yukleme);
}

class _MizanAnaliziSayfasiState extends State<MizanAnaliziSayfasi> {
  SupabaseClient get _db => Supabase.instance.client;
  Mizan? _mizan;
  MizanOzet? _ozet;
  String? _hata;
  List<Map<String, dynamic>> _firmalar = [];
  int? _firmaId;
  List<_Kayit> _kayitlar = [];
  _Kayit? _onceki;
  bool _mesgul = false;
  final _gun = TextEditingController();
  final _yorum = TextEditingController();
  final _eCari = TextEditingController(), _eAsit = TextEditingController(), _eBorc = TextEditingController(), _eAlacak = TextEditingController(), _eDegisim = TextEditingController();

  @override
  void initState() {
    super.initState();
    _db.from('firmalar').select('id, unvan').order('unvan').then((r) {
      if (mounted) setState(() => _firmalar = List<Map<String, dynamic>>.from(r));
    });
  }

  @override
  void dispose() {
    for (final c in [_gun, _yorum, _eCari, _eAsit, _eBorc, _eAlacak, _eDegisim]) {
      c.dispose();
    }
    super.dispose();
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int get _gunSayisi => int.tryParse(_gun.text.trim()) ?? (_mizan?.gun ?? 365);

  double? _esik(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Set<String> _kelimeler(String s) {
    const m = {'İ': 'I', 'ı': 'I', 'i': 'I', 'Ş': 'S', 'ş': 'S', 'Ğ': 'G', 'ğ': 'G', 'Ü': 'U', 'ü': 'U', 'Ö': 'O', 'ö': 'O', 'Ç': 'C', 'ç': 'C'};
    final sb = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final x = m[ch] ?? ch.toUpperCase();
      sb.write(RegExp(r'^[A-Z0-9]$').hasMatch(x) ? x : ' ');
    }
    return sb.toString().split(' ').where((e) => e.length > 2 && !const {'LTD', 'STI', 'TIC', 'SAN', 'VE'}.contains(e)).toSet();
  }

  int? _eslestir(String unvan) {
    final k = _kelimeler(unvan);
    int? en;
    var enSkor = 0;
    for (final f in _firmalar) {
      final s = _kelimeler(f['unvan'] as String).intersection(k).length;
      if (s > enSkor) {
        enSkor = s;
        en = f['id'] as int;
      }
    }
    return enSkor >= 2 ? en : null;
  }

  Future<void> _sec() async {
    final r = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    try {
      final m = mizanOku(r.files.first.bytes!);
      final o = mizanOzetle(m);
      setState(() {
        _hata = null;
        _mizan = m;
        _ozet = o;
        _onceki = null;
        _gun.text = '${m.gun}';
        _firmaId = _eslestir(m.unvan);
      });
      await _kayitlariYukle();
      _yorumla();
    } catch (e) {
      setState(() {
        _hata = '$e';
        _mizan = null;
        _ozet = null;
      });
    }
  }

  Future<void> _kayitlariYukle() async {
    _kayitlar = [];
    if (_firmaId != null) {
      try {
        final r = await _db.from('mizan_kayit').select().eq('firma_id', _firmaId!).order('son', ascending: false);
        _kayitlar = [
          for (final x in r as List) _Kayit(x['id'] as int, Mizan.fromJson(Map<String, dynamic>.from(x['veri'] as Map)), DateTime.parse(x['yukleme'] as String)),
        ];
      } catch (e) {
        _mesaj('Kayıtlı mizanlar okunamadı (supabase_mizan.sql çalıştırıldı mı?): $e');
      }
    }
    if (mounted) setState(() {});
  }

  void _yorumla() {
    if (_mizan == null || _ozet == null) return;
    final on = _onceki;
    _yorum.text = mizanYorumlari(_mizan!, _ozet!, _gunSayisi, onceki: on?.mizan, oncekiOzet: on == null ? null : mizanOzetle(on.mizan)).join('\n');
    setState(() {});
  }

  Future<void> _kaydet() async {
    final m = _mizan;
    if (m == null || _firmaId == null) {
      _mesaj('Önce firmayı seçin.');
      return;
    }
    setState(() => _mesgul = true);
    try {
      String? d(DateTime? t) => t == null ? null : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      if (m.son != null) {
        await _db.from('mizan_kayit').delete().eq('firma_id', _firmaId!).eq('son', d(m.son)!);
      }
      await _db.from('mizan_kayit').insert({'firma_id': _firmaId, 'bas': d(m.bas), 'son': d(m.son), 'veri': m.toJson()});
      await _kayitlariYukle();
      _mesaj('Mizan kaydedildi.');
    } catch (e) {
      _mesaj('Kaydedilemedi: $e');
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _sil(_Kayit k) async {
    try {
      await _db.from('mizan_kayit').delete().eq('id', k.id);
      if (_onceki?.id == k.id) _onceki = null;
      await _kayitlariYukle();
    } catch (e) {
      _mesaj('Silinemedi: $e');
    }
  }

  List<String> _uyarilar() {
    final o = _ozet;
    if (o == null) return [];
    final g = {for (final x in mizanGostergeleri(o, _gunSayisi)) x.anahtar: x.deger};
    final u = <String>[];
    final cari = _esik(_eCari), asit = _esik(_eAsit), borc = _esik(_eBorc), alacak = _esik(_eAlacak);
    if (cari != null && g['cari'] != null && g['cari']! < cari) u.add('Cari oran ${mizanTl(g['cari']!)} (belirlediğiniz alt sınır ${mizanTl(cari)}).');
    if (asit != null && g['asit'] != null && g['asit']! < asit) u.add('Asit-test oranı ${mizanTl(g['asit']!)} (alt sınır ${mizanTl(asit)}).');
    if (borc != null && g['borcluluk'] != null && g['borcluluk']! > borc) u.add('Borçluluk oranı %${mizanTl(g['borcluluk']!, ondalik: 1)} (üst sınır %${mizanTl(borc, ondalik: 1)}).');
    if (alacak != null && g['alacakGun'] != null && g['alacakGun']! > alacak) u.add('Alacak tahsil süresi ${mizanTl(g['alacakGun']!, ondalik: 0)} gün (üst sınır ${mizanTl(alacak, ondalik: 0)} gün).');
    final on = _onceki, dg = _esik(_eDegisim);
    if (on != null && dg != null) {
      final onO = mizanOzetle(on.mizan);
      final now = mizanDegerleri(o, _gunSayisi), prev = mizanDegerleri(onO, on.mizan.gun);
      const adlar = {'aktif': 'Toplam varlıklar', 'hazir': 'Hazır değerler', 'ticariAlacak': 'Ticari alacaklar', 'stok': 'Stoklar', 'kv': 'Kısa vadeli yabancı kaynaklar', 'ozk': 'Özkaynaklar'};
      for (final e in adlar.entries) {
        final a = now[e.key], b = prev[e.key];
        if (a != null && b != null && b.abs() > 0.01) {
          final p = (a - b) / b.abs() * 100;
          if (p.abs() > dg) u.add('${e.value} önceki mizana göre %${mizanTl(p.abs(), ondalik: 1)} ${p >= 0 ? 'arttı' : 'azaldı'}.');
        }
      }
    }
    if (o.denge.abs() > 1) u.add('Aktif ve pasif toplamı arasında ${mizanTl(o.denge.abs())} TL fark var; mizan eksik veya hesap kodları farklı olabilir.');
    return u;
  }

  // ------------------------------------------------------------------ PDF
  Future<void> _pdf() async {
    final m = _mizan, o = _ozet;
    if (m == null || o == null) return;
    final gun = _gunSayisi;
    final g = mizanGostergeleri(o, gun);
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()));

    pw.Widget h(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 12, bottom: 5), child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)));
    pw.Widget hucre(String t, {bool kalin = false, bool sag = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(t, textAlign: sag ? pw.TextAlign.right : pw.TextAlign.left, style: pw.TextStyle(fontSize: 9, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );
    pw.Widget tablo(List<List<String>> satirlar, {List<int> genislik = const [3, 2], bool baslikSatiri = false, Set<int> sagKolon = const {1}}) => pw.Table(
          border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey600),
          columnWidths: {for (var i = 0; i < genislik.length; i++) i: pw.FlexColumnWidth(genislik[i].toDouble())},
          children: [
            for (var i = 0; i < satirlar.length; i++)
              pw.TableRow(
                decoration: (baslikSatiri && i == 0) ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
                children: [for (var j = 0; j < satirlar[i].length; j++) hucre(satirlar[i][j], kalin: baslikSatiri && i == 0, sag: sagKolon.contains(j))],
              ),
          ],
        );
    pw.Widget bar(List<(String, double, PdfColor)> d) {
      final t = d.fold<double>(0, (a, e) => a + (e.$2 > 0 ? e.$2 : 0));
      if (t <= 0) return pw.SizedBox();
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          for (final e in d)
            if (e.$2 > 0) pw.Expanded(flex: (e.$2 / t * 1000).round().clamp(1, 1000).toInt(), child: pw.Container(height: 14, color: e.$3)),
        ]),
        pw.SizedBox(height: 3),
        pw.Wrap(spacing: 12, children: [
          for (final e in d)
            if (e.$2 > 0) pw.Text('${e.$1}: %${mizanTl(e.$2 / t * 100, ondalik: 1)}', style: const pw.TextStyle(fontSize: 8.5)),
        ]),
      ]);
    }

    final uyar = _uyarilar();
    final on = _onceki;
    List<pw.Widget> karsilastirma() {
      if (on == null) return [];
      final oo = mizanOzetle(on.mizan);
      final a = mizanDegerleri(o, gun), b = mizanDegerleri(oo, on.mizan.gun);
      final satirlar = <List<String>>[
        ['Kalem', 'Önceki (${on.mizan.aralik.isEmpty ? on.mizan.donem : on.mizan.aralik})', 'Şimdiki', 'Değişim'],
      ];
      for (final e in const {'aktif': 'Toplam varlıklar', 'hazir': 'Hazır değerler', 'ticariAlacak': 'Ticari alacaklar', 'stok': 'Stoklar', 'kv': 'Kısa vadeli yabancı kaynaklar', 'ozk': 'Özkaynaklar'}.entries) {
        final x = a[e.key] ?? 0, y = b[e.key] ?? 0;
        satirlar.add([e.value, mizanTl(y), mizanTl(x), y.abs() > 0.01 ? '%${mizanTl((x - y) / y.abs() * 100, ondalik: 1)}' : '-']);
      }
      for (final gs in g) {
        if (const {'cari', 'asit', 'borcluluk', 'alacakGun', 'stokGun'}.contains(gs.anahtar)) {
          final eski = mizanGostergeleri(oo, on.mizan.gun).firstWhere((e) => e.anahtar == gs.anahtar);
          satirlar.add([gs.ad, gostergeMetni(eski), gostergeMetni(gs), '']);
        }
      }
      final farkli = (gun - on.mizan.gun).abs() > gun * 0.1;
      return [
        h('Önceki mizanla karşılaştırma'),
        tablo(satirlar, genislik: [3, 3, 3, 2], baslikSatiri: true, sagKolon: {1, 2, 3}),
        if (farkli) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('Not: Dönem uzunlukları farklıdır (${on.mizan.gun} ve $gun gün). Satış ve kâr gibi dönem akış kalemleri doğrudan karşılaştırılamaz.', style: const pw.TextStyle(fontSize: 8.5))),
      ];
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
      header: (c) => markaUst(),
      footer: (c) => markaAlt(c),
      build: (c) => [
        pw.Text('Finansal Analiz Raporu', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(m.unvan.isEmpty ? '' : m.unvan, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text('Dönem: ${m.aralik.isNotEmpty ? m.aralik : m.donem}  ($gun gün)', style: const pw.TextStyle(fontSize: 10)),
        h('Varlık ve kaynak yapısı'),
        bar([('Dönen varlıklar', o.donen, PdfColors.blueGrey700), ('Duran varlıklar', o.duran, PdfColors.blueGrey300)]),
        pw.SizedBox(height: 8),
        bar([('Kısa vadeli yabancı kaynak', o.kv, PdfColors.orange700), ('Uzun vadeli yabancı kaynak', o.uv, PdfColors.orange300), ('Özkaynak', o.ozk, PdfColors.teal600)]),
        h('Bilanço özeti (TL)'),
        tablo([
          ['Dönen varlıklar', mizanTl(o.donen)],
          ['  Hazır değerler', mizanTl(o.hazir)],
          ['  Ticari alacaklar', mizanTl(o.ticariAlacak)],
          ['  Stoklar', mizanTl(o.stok)],
          ['Duran varlıklar', mizanTl(o.duran)],
          ['TOPLAM VARLIKLAR', mizanTl(o.aktif)],
          ['Kısa vadeli yabancı kaynaklar', mizanTl(o.kv)],
          ['Uzun vadeli yabancı kaynaklar', mizanTl(o.uv)],
          ['Özkaynaklar (dönem sonucu dahil)', mizanTl(o.ozk)],
          ['TOPLAM KAYNAKLAR', mizanTl(o.kv + o.uv + o.ozk)],
        ]),
        h('Gelir tablosu özeti (TL)'),
        tablo([
          ['Brüt satışlar', mizanTl(o.brutSatis)],
          ['Satış indirimleri', mizanTl(o.indirim)],
          ['Net satışlar', mizanTl(o.netSatis)],
          ['Satışların maliyeti', mizanTl(o.smm)],
          ['Brüt kâr', mizanTl(o.brutKar)],
          ['Faaliyet giderleri', mizanTl(o.faalGider)],
          ['Faaliyet kârı', mizanTl(o.faalKar)],
          ['Diğer gelir ve giderler (net)', mizanTl(o.diger)],
          ['DÖNEM SONUCU', mizanTl(o.sonuc)],
        ]),
        h('Oranlar ve süreler'),
        tablo([
          ['Gösterge', 'Değer', 'Hesaplama'],
          for (final x in g) [x.ad, gostergeMetni(x), x.aciklama],
        ], genislik: [3, 2, 6], baslikSatiri: true),
        ...karsilastirma(),
        if (uyar.isNotEmpty) ...[
          h('Dikkat edilecek noktalar'),
          for (final u in uyar) pw.Text('- $u', style: const pw.TextStyle(fontSize: 9.5)),
        ],
        h('Değerlendirme'),
        for (final s in _yorum.text.split('\n').where((e) => e.trim().isNotEmpty)) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: pw.Text('- $s', style: const pw.TextStyle(fontSize: 10))),
        pw.SizedBox(height: 14),
        pw.Text(
          'Bu rapor, yüklenen mizandaki bakiyelere dayanır; sürelerde dönem sonu bakiyeleri ve dönem gün sayısı kullanılmıştır, bu nedenle değerler yaklaşıktır. Vergi hesabı veya hukuki görüş niteliği taşımaz.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ));
    final ad = (m.unvan.isEmpty ? 'mizan' : m.unvan).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    await bordroKaydet('finansal_analiz_$ad', Uint8List.fromList(await doc.save()), 'pdf');
  }

  // ------------------------------------------------------------------ ekran
  Widget _satirTablo(List<List<String>> satirlar, {bool kalinSon = false}) => Table(
        columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
        border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade300)),
        children: [
          for (var i = 0; i < satirlar.length; i++)
            TableRow(children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6), child: Text(satirlar[i][0], style: TextStyle(fontWeight: (kalinSon && i == satirlar.length - 1) || satirlar[i][0] == satirlar[i][0].toUpperCase() ? FontWeight.bold : FontWeight.normal))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6), child: Text(satirlar[i][1], textAlign: TextAlign.right)),
            ]),
        ],
      );

  Widget _kart(String baslik, Widget icerik) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            icerik,
          ]),
        ),
      );

  Widget _esikAlan(String etiket, TextEditingController c) => SizedBox(
        width: 210,
        child: TextField(controller: c, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: etiket, border: const OutlineInputBorder(), isDense: true)),
      );

  @override
  Widget build(BuildContext context) {
    final m = _mizan, o = _ozet;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Mizan ve finansal analiz', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Muhasebe programından aldığınız mizanı (Excel .xlsx veya CSV) yükleyin; oranlar, süreler ve PDF analiz raporu hazırlanır. Dosya yalnızca tarayıcıda okunur, kaydetmezseniz hiçbir yere gönderilmez.'),
      const SizedBox(height: 12),
      Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(onPressed: _sec, icon: const Icon(Icons.upload_file), label: const Text('Mizan dosyası seç')),
        if (m != null) Text('${m.unvan.isEmpty ? 'Mizan' : m.unvan}  ·  ${m.aralik.isNotEmpty ? m.aralik : m.donem}  ·  ${m.satirlar.length} ana hesap'),
      ]),
      if (_hata != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_hata!, style: const TextStyle(color: Colors.red))),
      if (m != null && o != null) ...[
        const SizedBox(height: 12),
        _kart(
          'Firma ve kayıt',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<int?>(
                  value: _firmaId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Firma (karşılaştırma için)', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Seçilmedi')),
                    for (final f in _firmalar) DropdownMenuItem<int?>(value: f['id'] as int, child: Text(f['unvan'] as String, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) async {
                    setState(() {
                      _firmaId = v;
                      _onceki = null;
                    });
                    await _kayitlariYukle();
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(controller: _gun, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Dönem gün sayısı', border: OutlineInputBorder(), isDense: true)),
              ),
              OutlinedButton.icon(onPressed: _mesgul ? null : _kaydet, icon: const Icon(Icons.save_outlined), label: const Text('Mizanı kaydet')),
            ]),
            if (_kayitlar.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Bu firmanın kayıtlı mizanları', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final k in _kayitlar)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  selected: _onceki?.id == k.id,
                  title: Text(k.mizan.aralik.isNotEmpty ? k.mizan.aralik : k.mizan.donem),
                  subtitle: Text('Yükleme: ${k.yukleme.toLocal().toString().substring(0, 16)}'),
                  trailing: Wrap(children: [
                    TextButton(
                      onPressed: () {
                        setState(() => _onceki = _onceki?.id == k.id ? null : k);
                        _yorumla();
                      },
                      child: Text(_onceki?.id == k.id ? 'Karşılaştırmayı kaldır' : 'Bununla karşılaştır'),
                    ),
                    IconButton(tooltip: 'Sil', onPressed: () => _sil(k), icon: const Icon(Icons.delete_outline)),
                  ]),
                ),
            ],
          ]),
        ),
        if (o.denge.abs() > 1)
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Dikkat: Aktif ve pasif toplamı arasında ${mizanTl(o.denge.abs())} TL fark var. Mizanda eksik hesap olabilir veya hesap kodları standart tek düzen planından farklı olabilir; rakamları kontrol edin.'),
            ),
          ),
        _kart(
          'Bilanço özeti (TL)',
          _satirTablo([
            ['Dönen varlıklar', mizanTl(o.donen)],
            ['  Hazır değerler', mizanTl(o.hazir)],
            ['  Ticari alacaklar', mizanTl(o.ticariAlacak)],
            ['  Stoklar', mizanTl(o.stok)],
            ['Duran varlıklar', mizanTl(o.duran)],
            ['TOPLAM VARLIKLAR', mizanTl(o.aktif)],
            ['Kısa vadeli yabancı kaynaklar', mizanTl(o.kv)],
            ['Uzun vadeli yabancı kaynaklar', mizanTl(o.uv)],
            ['Özkaynaklar (dönem sonucu dahil)', mizanTl(o.ozk)],
            ['TOPLAM KAYNAKLAR', mizanTl(o.kv + o.uv + o.ozk)],
          ]),
        ),
        _kart(
          'Gelir tablosu özeti (TL)',
          _satirTablo([
            ['Brüt satışlar', mizanTl(o.brutSatis)],
            ['Satış indirimleri', mizanTl(o.indirim)],
            ['Net satışlar', mizanTl(o.netSatis)],
            ['Satışların maliyeti', mizanTl(o.smm)],
            ['Brüt kâr', mizanTl(o.brutKar)],
            ['Faaliyet giderleri', mizanTl(o.faalGider)],
            ['Faaliyet kârı', mizanTl(o.faalKar)],
            ['Diğer gelir ve giderler (net)', mizanTl(o.diger)],
            ['DÖNEM SONUCU', mizanTl(o.sonuc)],
          ]),
        ),
        _kart(
          'Oranlar ve süreler',
          Column(children: [
            for (final x in mizanGostergeleri(o, _gunSayisi))
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(x.ad), subtitle: Text(x.aciklama, style: const TextStyle(fontSize: 11)), trailing: Text(gostergeMetni(x), style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
        ),
        _kart(
          'Uyarı eşikleri (boş bırakılanlar kontrol edilmez)',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sınırları kendi değerlendirmenize göre girin; sistem kendiliğinden "iyi/kötü" sınırı koymaz.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _esikAlan('Cari oran alt sınırı', _eCari),
              _esikAlan('Asit-test alt sınırı', _eAsit),
              _esikAlan('Borçluluk üst sınırı (%)', _eBorc),
              _esikAlan('Alacak süresi üst sınırı (gün)', _eAlacak),
              _esikAlan('Önceki mizana göre değişim (%)', _eDegisim),
            ]),
            const SizedBox(height: 8),
            for (final u in _uyarilar()) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $u', style: TextStyle(color: Colors.orange.shade900))),
          ]),
        ),
        _kart(
          'Değerlendirme metni (PDF raporuna girer, düzenleyebilirsiniz)',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _yorum, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              OutlinedButton.icon(onPressed: _yorumla, icon: const Icon(Icons.refresh), label: const Text('Metni yeniden oluştur')),
              FilledButton.icon(onPressed: _pdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF rapor indir')),
            ]),
          ]),
        ),
      ],
    ]);
  }
}
