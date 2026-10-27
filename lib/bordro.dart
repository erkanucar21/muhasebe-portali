import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart';
import 'bordro_eposta.dart';
import 'bordro_hesap.dart';
import 'firmalar.dart';
import 'maliyet_raporu.dart';
import 'personel_takip.dart';
import 'secili_firma.dart';

/// Seçili firmanın personeli için aylık bordro: tek tek ve toplu.
/// Yalnızca yönetici (müşavir) görür.
class BordroSayfasi extends StatefulWidget {
  const BordroSayfasi({super.key});
  @override
  State<BordroSayfasi> createState() => _BordroSayfasiState();
}

int? _sonBordroYil, _sonBordroAy;

class _BordroSayfasiState extends State<BordroSayfasi> {
  SupabaseClient get _db => Supabase.instance.client;
  int? _firmaId;
  late int _yil;
  late int _ay;
  int? _indirim; // null: yılın varsayılanı
  bool _yukleniyor = true;
  String? _hata;
  List<Personel> _personel = [];
  // personel id -> ay -> işe gelmediği gün sayısı (seçili yılın başından seçili aya kadar)
  final Map<int, Map<int, int>> _gelmedi = {};
  // personel id -> seçili aya yansıtılan tazminat: [brüt, kesinti]
  final Map<int, List<double>> _taz = {};

  @override
  void initState() {
    super.initState();
    final su = DateTime.now();
    _yil = _sonBordroYil ?? su.year;
    _ay = _sonBordroAy ?? su.month;
    _firmaId = seciliFirmaId.value;
    seciliFirmaId.addListener(_firmaDegisti);
    _yukle();
  }

  @override
  void dispose() {
    seciliFirmaId.removeListener(_firmaDegisti);
    super.dispose();
  }

  void _firmaDegisti() {
    if (seciliFirmaId.value == _firmaId) return;
    _firmaId = seciliFirmaId.value;
    _yukle();
  }

  Future<void> _yukle() async {
    final id = _firmaId;
    if (id == null) {
      setState(() {
        _personel = [];
        _yukleniyor = false;
      });
      return;
    }
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final r = await _db.from('personel').select().eq('firma_id', id);
      _personel = [for (final m in r as List) Personel.fromMap(m as Map<String, dynamic>)];
      await _gelmediYukle();
      await _tazYukle();
    } catch (e) {
      _hata = 'Personel yüklenemedi: $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  /// Yılbaşından seçili ayın sonuna kadar "Gelmedi" işaretli günleri personel ve aya göre sayar.
  /// Önceki aylar da gerekir: kümülatif gelir vergisi matrahı onlara bağlıdır.
  Future<void> _gelmediYukle() async {
    _gelmedi.clear();
    if (_personel.isEmpty) return;
    final ids = [for (final p in _personel) p.id];
    final bas = '$_yil-01-01';
    final bit = DateTime(_yil, _ay + 1, 0);
    final son = '$_yil-${_ay.toString().padLeft(2, '0')}-${bit.day.toString().padLeft(2, '0')}';
    for (var ofset = 0;; ofset += 1000) {
      final parca = await _db
          .from('izin_kayitlari')
          .select('personel_id, tarih')
          .eq('durum', 'gelmedi')
          .inFilter('personel_id', ids)
          .gte('tarih', bas)
          .lte('tarih', son)
          .order('tarih')
          .order('personel_id')
          .range(ofset, ofset + 999);
      for (final m in parca) {
        final id = m['personel_id'] as int;
        final t = DateTime.parse(m['tarih'] as String);
        final ay = _gelmedi.putIfAbsent(id, () => {});
        ay[t.month] = (ay[t.month] ?? 0) + 1;
      }
      if (parca.length < 1000) break;
    }
  }

  Future<void> _tazYukle() async {
    _taz.clear();
    if (_personel.isEmpty) return;
    try {
      final r = await _db
          .from('bordro_tazminat')
          .select()
          .eq('yil', _yil)
          .eq('ay', _ay)
          .inFilter('personel_id', [for (final p in _personel) p.id]);
      for (final m in r as List) {
        double n(String k) => ((m[k] ?? 0) as num).toDouble();
        _taz[m['personel_id'] as int] = [
          n('kidem_brut') + n('ihbar_brut'),
          n('kidem_damga') + n('ihbar_gv') + n('ihbar_damga'),
        ];
      }
    } catch (_) {}
  }

  void _ayDegistir(int d) {
    var a = _ay + d, y = _yil;
    while (a > 12) {
      a -= 12;
      y++;
    }
    while (a < 1) {
      a += 12;
      y--;
    }
    setState(() {
      _ay = a;
      _yil = y;
      _indirim = null;
      _sonBordroYil = y;
      _sonBordroAy = a;
    });
    _yukle();
  }

  String get _firmaAdi => FirmaDeposu.ornek.bul(_firmaId ?? -1)?.unvan ?? '';

  FirmaBilgi get _firmaBilgi {
    final f = FirmaDeposu.ornek.bul(_firmaId ?? -1);
    if (f == null) return FirmaBilgi(ad: _firmaAdi);
    return FirmaBilgi(
      ad: f.unvan,
      adres: f.adres,
      sgkSicil: f.sgkSicilNo,
      sgkSube: f.sgkSubesi,
      vergiDairesi: f.vergiDairesi,
      vergiNo: f.vergiNo.isNotEmpty ? f.vergiNo : f.tcNo,
      mersis: f.mersisNo,
      ticaretSicil: f.ticaretSicilNo,
    );
  }

  /// Seçili ay için çalışan herkesin bordrosu (Türkçe ada göre sıralı)
  List<PersonelBordro> _hesapla(YilParam p) {
    final sonuc = <PersonelBordro>[];
    for (final k in _personel) {
      if (calisilanGun(k.giris, k.cikis, _yil, _ay) == 0) continue;
      final dizi = yillikBordro(
        p,
        BordroGirdi(ucret: k.ucret, net: k.maasTuru != 'brut', asgari: k.asgari, giris: k.giris, cikis: k.cikis),
        _ay,
        indirimPuan: _indirim,
        gelmedi: _gelmedi[k.id],
      );
      final b = dizi.last;
      sonuc.add(PersonelBordro(
        ad: k.ad,
        tc: k.tc,
        meslek: k.meslek,
        sgkSicil: k.sgkSicil,
        gelmedi: _gelmedi[k.id]?[_ay] ?? 0,
        giris: k.giris,
        cikis: k.cikis,
        asgari: k.asgari,
        netMaas: k.maasTuru != 'brut',
        kayitliMaas: k.ucret,
        b: b,
        tazBrut: k.cikis == null ? 0 : (_taz[k.id]?[0] ?? 0),
        tazKesinti: k.cikis == null ? 0 : (_taz[k.id]?[1] ?? 0),
      ));
    }
    sonuc.sort((a, b) => trKarsilastir(a.ad, b.ad));
    return sonuc;
  }

  Future<void> _indir(Future<void> Function() is_) async {
    try {
      await is_();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dosya oluşturulamadı: $e')));
    }
  }

  String _dosyaAdi(String on) {
    final f = _firmaAdi.replaceAll(RegExp(r'[^A-Za-z0-9ÇĞİÖŞÜçğıöşü]+'), '_');
    return '${on}_${f}_$_yil-${_ay.toString().padLeft(2, '0')}';
  }

  Widget _ustSerit(YilParam? p) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          IconButton(onPressed: () => _ayDegistir(-1), icon: const Icon(Icons.chevron_left)),
          Text('${bordroAylar[_ay - 1]} $_yil', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          IconButton(onPressed: () => _ayDegistir(1), icon: const Icon(Icons.chevron_right)),
          if (p != null) ...[
            const Text('İşveren SGK indirimi:'),
            DropdownButton<int>(
              value: _indirim ?? p.varsayilanIndirim,
              items: [
                for (final v in const [0, 2, 5]) DropdownMenuItem(value: v, child: Text(v == 0 ? 'Yok' : '$v puan')),
              ],
              onChanged: (v) => setState(() => _indirim = v),
            ),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = bordroParam(_yil);
    Widget govde;
    if (_firmaId == null) {
      govde = const Center(child: Text('Üstten bir firma seç.'));
    } else if (_yukleniyor) {
      govde = const Center(child: CircularProgressIndicator());
    } else if (_hata != null) {
      govde = Center(child: Text(_hata!, style: const TextStyle(color: Color(0xFFB3261E))));
    } else if (p == null) {
      govde = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$_yil için bordro parametreleri tanımlı değil. Tanımlı yıllar: ${bordroYillari().join(', ')}.',
              textAlign: TextAlign.center),
        ),
      );
    } else {
      final liste = _hesapla(p);
      final top = BordroToplam(liste);
      final tazVar = liste.any((e) => e.tazBrut > 0);
      if (liste.isEmpty) {
        govde = Center(child: Text('${bordroAylar[_ay - 1]} $_yil için çalışan personel yok.'));
      } else {
        govde = Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(spacing: 10, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _indir(() async => bordroKaydet(
                    _dosyaAdi('bordro'),
                    await bordroListePdf(liste, firma: _firmaBilgi, yil: _yil, ay: _ay),
                    'pdf')),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text('Toplu bordro PDF (${liste.length} kişi)'),
              ),
              OutlinedButton.icon(
                onPressed: () => _indir(() async => bordroKaydet(
                    _dosyaAdi('bordro'), bordroListeXlsx(liste, firma: _firmaBilgi, yil: _yil, ay: _ay), 'xlsx')),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Excel indir'),
              ),
              OutlinedButton.icon(
                onPressed: () => bordroEpostaDialog(context, _yil, _ay),
                icon: const Icon(Icons.forward_to_inbox_outlined),
                label: const Text('Mükelleflere e-postayla gönder'),
              ),
              OutlinedButton.icon(
                onPressed: () => _indir(() async => bordroKaydet(
                    _dosyaAdi('maliyet'),
                    await maliyetRaporuPdf(
                        firma: _firmaAdi, personel: _personel, param: p, yil: _yil, sonAy: _ay, gelmedi: _gelmedi, indirimPuan: _indirim),
                    'pdf')),
                icon: const Icon(Icons.summarize_outlined),
                label: Text('Maliyet raporu (Ocak-${bordroAylar[_ay - 1]})'),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: LayoutBuilder(
                builder: (c, k) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: k.maxWidth),
                    child: DataTable(
                      showCheckboxColumn: false,
                      columnSpacing: 18,
                      horizontalMargin: 12,
                      headingRowColor: WidgetStatePropertyAll(Colors.grey.shade200),
                      columns: [
                        DataColumn(label: Text('No')),
                        DataColumn(label: Text('Ad soyad')),
                        DataColumn(label: Text('Gün'), numeric: true),
                        DataColumn(label: Text('Gelmedi'), numeric: true),
                        DataColumn(label: Text('Brüt'), numeric: true),
                        DataColumn(label: Text('SGK + İşsizlik'), numeric: true),
                        DataColumn(label: Text('Gelir vergisi'), numeric: true),
                        DataColumn(label: Text('Damga'), numeric: true),
                        DataColumn(label: Text('Net ödenecek'), numeric: true),
                        if (tazVar) DataColumn(label: Text('Tazminat (net)'), numeric: true),
                        if (tazVar) DataColumn(label: Text('Toplam ödenen'), numeric: true),
                        DataColumn(label: Text('İşveren payı'), numeric: true),
                        DataColumn(label: Text('Maliyet'), numeric: true),
                      ],
                      rows: [
                        for (var i = 0; i < liste.length; i++)
                          DataRow(
                            color: WidgetStateProperty.resolveWith<Color?>((d) {
                              if (d.contains(WidgetState.hovered)) return const Color(0xFFFFE680);
                              return i.isEven ? Colors.white : const Color(0xFFE6E6E6);
                            }),
                            onSelectChanged: (_) => _detay(liste[i]),
                            cells: [
                              DataCell(Text('${i + 1}')),
                              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(liste[i].ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (liste[i].asgari)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Tooltip(message: 'Asgari ücretli', child: Icon(Icons.verified_outlined, size: 15)),
                                  ),
                              ])),
                              DataCell(Text('${liste[i].b.gun}')),
                              DataCell(Text(liste[i].gelmedi == 0 ? '-' : '${liste[i].gelmedi}',
                                  style: TextStyle(color: liste[i].gelmedi == 0 ? null : const Color(0xFFB3261E)))),
                              DataCell(Text(tl(liste[i].b.brut))),
                              DataCell(Text(tl(liste[i].b.sgkIsci + liste[i].b.issizlikIsci))),
                              DataCell(Text(tl(liste[i].b.gelirVergisi))),
                              DataCell(Text(tl(liste[i].b.damga))),
                              DataCell(Text(tl(liste[i].b.net), style: const TextStyle(fontWeight: FontWeight.w700))),
                              if (tazVar) DataCell(Text(liste[i].tazBrut > 0 ? tl(liste[i].tazNet) : '-')),
                              if (tazVar) DataCell(Text(tl(liste[i].b.net + liste[i].tazNet), style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text(tl(liste[i].b.isverenPayi))),
                              DataCell(Text(tl(liste[i].b.maliyet))),
                            ],
                          ),
                        DataRow(
                          color: WidgetStatePropertyAll(Colors.grey.shade300),
                          cells: [
                            const DataCell(Text('')),
                            const DataCell(Text('TOPLAM', style: TextStyle(fontWeight: FontWeight.w800))),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            DataCell(Text(tl(top.brut), style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(tl(top.sgk + top.iss), style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(tl(top.gv), style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(tl(top.damga), style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(tl(top.net), style: const TextStyle(fontWeight: FontWeight.w800))),
                            if (tazVar) DataCell(Text(tl(liste.fold<double>(0, (a, e) => a + e.tazNet)), style: const TextStyle(fontWeight: FontWeight.w800))),
                            if (tazVar) DataCell(Text(tl(top.net + liste.fold<double>(0, (a, e) => a + e.tazNet)), style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(tl(top.isvSgk + top.isvIss), style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(tl(top.maliyet), style: const TextStyle(fontWeight: FontWeight.w800))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      }
    }
    return Column(children: [
      _ustSerit(p),
      Expanded(child: govde),
    ]);
  }

  void _detay(PersonelBordro k) {
    final b = k.b;
    Widget satir(String e, String d, {bool kalin = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(e, style: TextStyle(fontWeight: kalin ? FontWeight.w700 : FontWeight.w400))),
            Text(d, style: TextStyle(fontWeight: kalin ? FontWeight.w700 : FontWeight.w400)),
          ]),
        );
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${k.ad}\n${bordroAylar[_ay - 1]} $_yil'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                k.asgari
                    ? 'Asgari ücretli'
                    : 'Kayıtlı maaş: ${tl(k.kayitliMaas)} TL (${k.netMaas ? 'net' : 'brüt'})',
                style: const TextStyle(color: Colors.black87),
              ),
              Text('Ücret ödenen gün: ${b.gun} / 30', style: const TextStyle(color: Colors.black87)),
              if (k.gelmedi > 0)
                Text('Gelmedi: ${k.gelmedi} gün (maaştan düşüldü, günlük ücret = maaş / 30)',
                    style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
              const Divider(),
              satir('Brüt ücret', tl(b.brut), kalin: true),
              satir('SGK matrahı', tl(b.sgkMatrah)),
              satir('SGK işçi payı (%14)', tl(b.sgkIsci)),
              satir('İşsizlik işçi payı (%1)', tl(b.issizlikIsci)),
              satir('Gelir vergisi matrahı', tl(b.gvMatrah)),
              satir('Kümülatif matrah', tl(b.kumMatrah)),
              satir('Hesaplanan gelir vergisi', tl(b.gvHesap)),
              satir('Asgari ücret GV istisnası', '-${tl(b.gvIstisna)}'),
              satir('Ödenecek gelir vergisi', tl(b.gelirVergisi), kalin: true),
              satir('Hesaplanan damga vergisi', tl(b.damgaHesap)),
              satir('Asgari ücret damga istisnası', '-${tl(b.damgaIstisna)}'),
              satir('Ödenecek damga vergisi', tl(b.damga), kalin: true),
              const Divider(),
              satir('Toplam kesinti', tl(b.isciKesinti)),
              satir('NET ÖDENECEK', tl(b.net), kalin: true),
              if (k.tazBrut > 0) ...[
                satir('Kıdem / ihbar tazminatı (brüt)', tl(k.tazBrut)),
                satir('Tazminat vergi kesintileri', '-${tl(k.tazKesinti)}'),
                satir('TOPLAM ÖDENECEK (maaş + tazminat)', tl(b.net + k.tazNet), kalin: true),
              ],
              const Divider(),
              satir('İşveren SGK payı', tl(b.isverenSgk)),
              satir('İşveren işsizlik payı', tl(b.isverenIssizlik)),
              satir('Toplam işveren maliyeti', tl(b.maliyet), kalin: true),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
          OutlinedButton.icon(
            onPressed: () => _indir(() async => bordroKaydet(
                _dosyaAdi('ucret_pusulasi_${k.ad.replaceAll(' ', '_')}'),
                await bordroPdf([k], firma: _firmaAdi, yil: _yil, ay: _ay),
                'pdf')),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Ücret pusulası'),
          ),
          FilledButton.icon(
            onPressed: () => _indir(() async => bordroKaydet(
                _dosyaAdi('bordro_${k.ad.replaceAll(' ', '_')}'),
                await bordroListePdf([k], firma: _firmaBilgi, yil: _yil, ay: _ay),
                'pdf')),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Bordro PDF'),
          ),
        ],
      ),
    );
  }
}
