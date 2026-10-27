import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bordro_hesap.dart';
import 'tazminat.dart';

/// Kıdem tavanı satırlarının kaynak / kontrol bilgisi (başlangıç tarihi -> kaynak).
final Map<DateTime, String> kidemKaynaklari = {};
DateTime? kidemSonKontrol;

String _tarih(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
double? _sayi(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
String _g(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Giriş yapıldıktan sonra çağrılır. Veritabanında değer yoksa koddaki varsayılanlar kullanılır.
Future<void> parametreYukle() async {
  try {
    final db = Supabase.instance.client;
    final yl = await db.from('yil_parametre').select();
    for (final r in yl as List) {
      final yil = r['yil'] as int;
      paramUygula(
        yil,
        YilParam.fromJson(yil, Map<String, dynamic>.from(r['veri'] as Map)),
        ParamKaynak((r['kaynak'] ?? '') as String, (r['notlar'] ?? '') as String,
            r['son_kontrol'] == null ? null : DateTime.parse(r['son_kontrol'] as String)),
      );
    }
    final kt = await db.from('kidem_tavan').select().order('baslangic');
    if ((kt as List).isNotEmpty) {
      tavanlar
        ..clear()
        ..addAll([for (final r in kt) (DateTime.parse(r['baslangic'] as String), (r['tutar'] as num).toDouble())]);
      kidemKaynaklari
        ..clear()
        ..addAll({for (final r in kt) DateTime.parse(r['baslangic'] as String): (r['kaynak'] ?? '') as String});
      DateTime? en;
      for (final r in kt) {
        if (r['son_kontrol'] != null) {
          final d = DateTime.parse(r['son_kontrol'] as String);
          if (en == null || d.isAfter(en)) en = d;
        }
      }
      kidemSonKontrol = en;
    }
  } catch (_) {
    // tablo henüz oluşturulmadıysa varsayılan değerlerle devam edilir
  }
}

/// Eskimiş veya eksik parametreler için uyarı metinleri.
List<String> parametreUyarilari() {
  final u = <String>[];
  final now = DateTime.now();
  if (bordroParam(now.year) == null) {
    u.add('${now.year} yılı bordro parametreleri tanımlı değil.');
  } else {
    final k = paramKaynaklari[now.year];
    if (k == null || k.sonKontrol == null) {
      u.add('${now.year} parametreleri hiç kontrol edildi olarak işaretlenmemiş.');
    } else if (now.difference(k.sonKontrol!).inDays > 90) {
      u.add('${now.year} parametrelerinin son kontrolü ${now.difference(k.sonKontrol!).inDays} gün önce.');
    }
  }
  if (now.month >= 11 && bordroParam(now.year + 1) == null) {
    u.add('${now.year + 1} yılı parametreleri henüz girilmemiş.');
  }
  final sinir = DateTime(now.year, now.month >= 7 ? 7 : 1, 1);
  if (tavanlar.isEmpty || tavanlar.map((e) => e.$1).reduce((a, b) => a.isAfter(b) ? a : b).isBefore(sinir)) {
    u.add('${_tarih(sinir)} sonrası dönem için kıdem tazminatı tavanı girilmemiş.');
  }
  return u;
}

Future<void> _gunluk(String konu, Object? eski, Object? yeni) async {
  final db = Supabase.instance.client;
  try {
    await db.from('parametre_gunluk').insert({
      'kullanici': db.auth.currentUser?.email ?? '',
      'konu': konu,
      'eski': eski,
      'yeni': yeni,
    });
  } catch (_) {}
}

class ParametrelerSayfasi extends StatefulWidget {
  const ParametrelerSayfasi({super.key});
  @override
  State<ParametrelerSayfasi> createState() => _ParametrelerSayfasiState();
}

class _ParametrelerSayfasiState extends State<ParametrelerSayfasi> {
  int? _yil;
  int _sayac = 0; // formu yenilemek için

  List<int> get _yillar => bordroYillari();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    _yil = _yillar.contains(now) ? now : _yillar.last;
  }

  void _yeniYil() {
    final y = _yillar.last + 1;
    final kopya = bordroParam(_yillar.last)!;
    paramUygula(y, kopya.copyWithYil(y), const ParamKaynak('', 'Önceki yıldan kopyalandı, değerleri güncelle.', null));
    setState(() {
      _yil = y;
      _sayac++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uyarilar = parametreUyarilari();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Mevzuat parametreleri', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Bordro, vergi hesaplayıcı ve tazminat hesapları buradaki değerleri kullanır. Bir değeri burada güncelleyince tüm hesaplar yeni değere göre çalışır. '
          'Değerleri resmî kaynaktan kontrol edip girin; sistem kendiliğinden oran öğrenmez.',
        ),
        const SizedBox(height: 12),
        if (uyarilar.isNotEmpty)
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kontrol edilmesi gerekenler', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final m in uyarilar) Text('• $m'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Yıl: '),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _yil,
            items: [for (final y in _yillar) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (v) => setState(() {
              _yil = v;
              _sayac++;
            }),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(onPressed: _yeniYil, icon: const Icon(Icons.add), label: Text('${_yillar.last + 1} yılını ekle')),
        ]),
        const SizedBox(height: 8),
        _YilForm(key: ValueKey('$_yil-$_sayac'), yil: _yil!, onKaydet: () => setState(() {})),
        const SizedBox(height: 24),
        _KidemBolumu(key: ValueKey('kidem-$_sayac'), onDegisti: () => setState(() {})),
        const SizedBox(height: 24),
        const _GunlukBolumu(),
        const SizedBox(height: 12),
        const Text(
          'Not: İşçi SGK payı (%14), işsizlik payı (%1) ve damga vergisi oranı kodda sabittir; değişirse kod güncellemesi gerekir.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class _YilForm extends StatefulWidget {
  final int yil;
  final VoidCallback onKaydet;
  const _YilForm({super.key, required this.yil, required this.onKaydet});
  @override
  State<_YilForm> createState() => _YilFormState();
}

class _YilFormState extends State<_YilForm> {
  late final Map<String, TextEditingController> _c;
  late final TextEditingController _kaynak, _not;
  final List<(TextEditingController, TextEditingController)> _dilim = [];
  DateTime? _sonKontrol;
  bool _kaydediyor = false;

  @override
  void initState() {
    super.initState();
    final p = bordroParam(widget.yil)!;
    final k = paramKaynaklari[widget.yil];
    _c = {
      'sgkTaban': TextEditingController(text: _g(p.sgkTaban)),
      'sgkTavan': TextEditingController(text: _g(p.sgkTavan)),
      'asgariBrut': TextEditingController(text: _g(p.asgariBrut)),
      'damgaIstisna': TextEditingController(text: _g(p.damgaIstisna)),
      'isverenSgk': TextEditingController(text: _g(p.isverenSgk)),
      'isverenIssizlik': TextEditingController(text: _g(p.isverenIssizlik)),
      'varsayilanIndirim': TextEditingController(text: '${p.varsayilanIndirim}'),
    };
    _kaynak = TextEditingController(text: k?.kaynak ?? '');
    _not = TextEditingController(text: k?.notlar ?? '');
    _sonKontrol = k?.sonKontrol;
    for (final (u, o) in p.dilimler) {
      _dilim.add((TextEditingController(text: u >= 1e17 ? '' : _g(u)), TextEditingController(text: _g(o))));
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _kaynak.dispose();
    _not.dispose();
    for (final (a, b) in _dilim) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  Widget _alan(String anahtar, String etiket) => SizedBox(
        width: 260,
        child: TextField(controller: _c[anahtar], decoration: InputDecoration(labelText: etiket, border: const OutlineInputBorder(), isDense: true)),
      );

  YilParam? _oku() {
    double? s(String k) => _sayi(_c[k]!.text);
    final ind = int.tryParse(_c['varsayilanIndirim']!.text.trim());
    final alanlar = [s('sgkTaban'), s('sgkTavan'), s('asgariBrut'), s('damgaIstisna'), s('isverenSgk'), s('isverenIssizlik')];
    if (alanlar.any((e) => e == null) || ind == null) return null;
    final dl = <(double, double)>[];
    for (var i = 0; i < _dilim.length; i++) {
      final ust = _dilim[i].$1.text.trim().isEmpty ? 1e18 : _sayi(_dilim[i].$1.text);
      final oran = _sayi(_dilim[i].$2.text);
      if (ust == null || oran == null) return null;
      if (ust < 1e17 && i == _dilim.length - 1) {
        // son dilim sınırsız olmalı
        dl.add((1e18, oran));
        continue;
      }
      if (dl.isNotEmpty && ust <= dl.last.$1) return null;
      dl.add((ust, oran));
    }
    if (dl.isEmpty) return null;
    return YilParam(
      yil: widget.yil,
      sgkTaban: alanlar[0]!,
      sgkTavan: alanlar[1]!,
      asgariBrut: alanlar[2]!,
      damgaIstisna: alanlar[3]!,
      isverenSgk: alanlar[4]!,
      isverenIssizlik: alanlar[5]!,
      varsayilanIndirim: ind,
      dilimler: dl,
    );
  }

  Future<void> _kaydet({bool kontrolBugun = false}) async {
    final p = _oku();
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Değerlerde eksik veya hatalı alan var. Dilim üst sınırları artan olmalı.')));
      return;
    }
    if (kontrolBugun) _sonKontrol = DateTime.now();
    setState(() => _kaydediyor = true);
    final db = Supabase.instance.client;
    final eski = bordroParam(widget.yil)?.toJson();
    try {
      await db.from('yil_parametre').upsert({
        'yil': widget.yil,
        'veri': p.toJson(),
        'kaynak': _kaynak.text.trim(),
        'notlar': _not.text.trim(),
        'son_kontrol': _sonKontrol == null ? null : _iso(_sonKontrol!),
        'guncelleme': DateTime.now().toUtc().toIso8601String(),
      });
      await _gunluk('${widget.yil} yıl parametreleri', eski, p.toJson());
      paramUygula(widget.yil, p, ParamKaynak(_kaynak.text.trim(), _not.text.trim(), _sonKontrol));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.yil} parametreleri kaydedildi.')));
        widget.onKaydet();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi (supabase_parametre.sql çalıştırıldı mı?): $e')));
      }
    } finally {
      if (mounted) setState(() => _kaydediyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final varsayilan = paramVarsayilanMi(widget.yil);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.yil} yılı parametreleri', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (varsayilan)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Bu yıl henüz veritabanına kaydedilmemiş; koddaki değerler kullanılıyor. Kontrol edip Kaydet\'e basın.', style: TextStyle(color: Colors.orange)),
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _alan('asgariBrut', 'Aylık brüt asgari ücret (TL)'),
              _alan('sgkTaban', 'SGK prime esas kazanç alt sınırı (TL)'),
              _alan('sgkTavan', 'SGK prime esas kazanç üst sınırı (TL)'),
              _alan('damgaIstisna', 'Aylık damga vergisi istisnası (TL)'),
              _alan('isverenSgk', 'İşveren SGK payı (0.2175 = %21,75)'),
              _alan('isverenIssizlik', 'İşveren işsizlik payı (0.02 = %2)'),
              _alan('varsayilanIndirim', 'Varsayılan SGK indirimi (puan)'),
            ]),
            const SizedBox(height: 16),
            const Text('Gelir vergisi tarifesi (üst sınır boşsa sınırsız)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (var i = 0; i < _dilim.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Text('${i + 1}. dilim  '),
                  SizedBox(
                    width: 200,
                    child: TextField(controller: _dilim[i].$1, decoration: const InputDecoration(labelText: 'Üst sınır (TL)', border: OutlineInputBorder(), isDense: true)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: TextField(controller: _dilim[i].$2, decoration: const InputDecoration(labelText: 'Oran (0.15)', border: OutlineInputBorder(), isDense: true)),
                  ),
                  IconButton(
                    tooltip: 'Dilimi sil',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _dilim.length <= 1
                        ? null
                        : () => setState(() {
                              final x = _dilim.removeAt(i);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                x.$1.dispose();
                                x.$2.dispose();
                              });
                            }),
                  ),
                ]),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _dilim.add((TextEditingController(), TextEditingController()))),
              icon: const Icon(Icons.add),
              label: const Text('Dilim ekle'),
            ),
            const Divider(height: 28),
            TextField(controller: _kaynak, decoration: const InputDecoration(labelText: 'Kaynak (Resmî Gazete tarihi/sayısı, tebliğ vb.)', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 12),
            TextField(controller: _not, maxLines: 2, decoration: const InputDecoration(labelText: 'Notlar (özel uygulama, istisna vb.)', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 12),
            Row(children: [
              Text(_sonKontrol == null ? 'Son kontrol: yok' : 'Son kontrol: ${_tarih(_sonKontrol!)}'),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 12, children: [
              FilledButton.icon(
                onPressed: _kaydediyor ? null : () => _kaydet(),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Kaydet'),
              ),
              OutlinedButton.icon(
                onPressed: _kaydediyor ? null : () => _kaydet(kontrolBugun: true),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Kaydet ve bugün kontrol edildi işaretle'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _KidemBolumu extends StatefulWidget {
  final VoidCallback onDegisti;
  const _KidemBolumu({super.key, required this.onDegisti});
  @override
  State<_KidemBolumu> createState() => _KidemBolumuState();
}

class _KidemBolumuState extends State<_KidemBolumu> {
  bool _kaydediyor = false;

  Future<void> _kaydet(List<(DateTime, double)> liste, String konu) async {
    setState(() => _kaydediyor = true);
    final db = Supabase.instance.client;
    final eski = [for (final (d, v) in tavanlar) {'baslangic': _iso(d), 'tutar': v}];
    try {
      await db.from('kidem_tavan').delete().gte('baslangic', '1900-01-01');
      if (liste.isNotEmpty) {
        await db.from('kidem_tavan').insert([
          for (final (d, v) in liste)
            {'baslangic': _iso(d), 'tutar': v, 'kaynak': kidemKaynaklari[d] ?? '', 'son_kontrol': _iso(DateTime.now())},
        ]);
      }
      await _gunluk(konu, eski, [for (final (d, v) in liste) {'baslangic': _iso(d), 'tutar': v}]);
      tavanlar
        ..clear()
        ..addAll(liste);
      kidemSonKontrol = DateTime.now();
      widget.onDegisti();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _kaydediyor = false);
    }
  }

  Future<void> _ekle() async {
    final tarihC = TextEditingController(), tutarC = TextEditingController(), kaynakC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kıdem tazminatı tavanı ekle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: tarihC, decoration: const InputDecoration(labelText: 'Geçerlilik başlangıcı (gg.aa.yyyy)')),
          TextField(controller: tutarC, decoration: const InputDecoration(labelText: 'Tavan tutarı (TL)')),
          TextField(controller: kaynakC, decoration: const InputDecoration(labelText: 'Kaynak')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ekle')),
        ],
      ),
    );
    final ts = tarihC.text.trim().split('.');
    final tutar = _sayi(tutarC.text);
    final kaynak = kaynakC.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tarihC.dispose();
      tutarC.dispose();
      kaynakC.dispose();
    });
    if (ok != true) return;
    if (ts.length != 3 || tutar == null || tutar <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarih (gg.aa.yyyy) ve tutar geçerli olmalı.')));
      return;
    }
    final d = DateTime(int.parse(ts[2]), int.parse(ts[1]), int.parse(ts[0]));
    final yeni = [for (final e in tavanlar) if (e.$1 != d) e, (d, tutar)]..sort((a, b) => a.$1.compareTo(b.$1));
    kidemKaynaklari[d] = kaynak;
    await _kaydet(yeni, 'Kıdem tavanı eklendi/güncellendi');
  }

  @override
  Widget build(BuildContext context) {
    final liste = [...tavanlar]..sort((a, b) => b.$1.compareTo(a.$1));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kıdem tazminatı tavanı', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(kidemSonKontrol == null ? 'Veritabanına kaydedilmemiş; koddaki değerler kullanılıyor.' : 'Son kayıt: ${_tarih(kidemSonKontrol!)}'),
            const SizedBox(height: 8),
            for (final (d, v) in liste)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${_tarih(d)} tarihinden itibaren: ${v.toStringAsFixed(2)} TL'),
                subtitle: (kidemKaynaklari[d] ?? '').isEmpty ? null : Text(kidemKaynaklari[d]!),
                trailing: IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _kaydediyor ? null : () => _kaydet([for (final e in tavanlar) if (e.$1 != d) e], 'Kıdem tavanı silindi'),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 12, children: [
              OutlinedButton.icon(onPressed: _kaydediyor ? null : _ekle, icon: const Icon(Icons.add), label: const Text('Yeni dönem ekle')),
              OutlinedButton.icon(
                onPressed: _kaydediyor ? null : () => _kaydet([...tavanlar], 'Kıdem tavanı kontrol edildi'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Mevcut listeyi kaydet, kontrol edildi'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _GunlukBolumu extends StatefulWidget {
  const _GunlukBolumu();
  @override
  State<_GunlukBolumu> createState() => _GunlukBolumuState();
}

class _GunlukBolumuState extends State<_GunlukBolumu> {
  late Future<List<dynamic>> _f;

  @override
  void initState() {
    super.initState();
    _f = _yukle();
  }

  Future<List<dynamic>> _yukle() async =>
      await Supabase.instance.client.from('parametre_gunluk').select().order('zaman', ascending: false).limit(50) as List<dynamic>;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Değişiklik günlüğü (son 50)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(tooltip: 'Yenile', onPressed: () => setState(() => _f = _yukle()), icon: const Icon(Icons.refresh)),
            ]),
            FutureBuilder<List<dynamic>>(
              future: _f,
              builder: (ctx, s) {
                if (s.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                if (s.hasError) return const Text('Günlük okunamadı.');
                final l = s.data!;
                if (l.isEmpty) return const Text('Henüz değişiklik kaydı yok.');
                return Column(children: [
                  for (final r in l)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r['konu'] as String),
                      subtitle: Text('${(r['kullanici'] ?? '') as String}  ·  ${DateTime.parse(r['zaman'] as String).toLocal().toString().substring(0, 16)}'),
                      onTap: () => showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(r['konu'] as String),
                          content: SingleChildScrollView(child: SelectableText('Eski:\n${r['eski']}\n\nYeni:\n${r['yeni']}')),
                          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}
