import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ekip yönetimi: portföy atama, iş devri, onay talepleri ve ekip panosu.
/// Not: Portföy düzeni bir iş organizasyonu aracıdır; veri erişim yetkisi yine
/// Kullanıcılar bölümündeki bölüm izinleriyle belirlenir.
class EkipSayfasi extends StatelessWidget {
  final bool yonetici;
  const EkipSayfasi({super.key, required this.yonetici});

  @override
  Widget build(BuildContext context) {
    final sekmeler = yonetici ? ['Portföy', 'Onay talepleri', 'Ekip panosu', 'Günlük'] : ['Portföyüm', 'Onaya gönder', 'Taleplerim'];
    return DefaultTabController(
      length: sekmeler.length,
      child: Column(children: [
        TabBar(isScrollable: true, tabs: [for (final s in sekmeler) Tab(text: s)]),
        Expanded(
          child: TabBarView(
            children: yonetici
                ? const [_PortfoyYonet(), _TalepYonet(), _Pano(), _Gunluk()]
                : const [_PortfoyBenim(), _TalepGonder(), _TalepBenim()],
          ),
        ),
      ]),
    );
  }
}

SupabaseClient get _db => Supabase.instance.client;

Future<void> _gunlugeYaz(String konu) async {
  try {
    await _db.from('ekip_gunluk').insert({'kullanici': _db.auth.currentUser?.email ?? '', 'konu': konu});
  } catch (_) {}
}

String _zaman(String iso) => DateTime.parse(iso).toLocal().toString().substring(0, 16);

Widget _hata(String m) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(m)));

// ---------------------------------------------------------------- yönetici: portföy
class _PortfoyYonet extends StatefulWidget {
  const _PortfoyYonet();
  @override
  State<_PortfoyYonet> createState() => _PortfoyYonetState();
}

class _PortfoyYonetState extends State<_PortfoyYonet> {
  List<Map<String, dynamic>> _firmalar = [], _kullanicilar = [];
  final Map<int, String> _atama = {}; // firma -> kullanıcı id
  bool _yukleniyor = true;
  String? _hataMetni;
  String _ara = '';
  bool? _zorunlu; // null: portfoy_ayar tablosu yok (supabase_portfoy_sinir.sql çalıştırılmadı)

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      _firmalar = List<Map<String, dynamic>>.from(await _db.from('firmalar').select('id, unvan').order('unvan'));
      _kullanicilar = List<Map<String, dynamic>>.from(await _db.from('profiller').select('user_id, gorunen_ad, giris_adi').eq('rol', 'yardimci').eq('aktif', true));
      final p = await _db.from('portfoy').select('firma_id, kullanici_id');
      _atama
        ..clear()
        ..addAll({for (final r in p as List) r['firma_id'] as int: r['kullanici_id'] as String});
      try {
        final a = await _db.from('portfoy_ayar').select('zorunlu').eq('id', 1).maybeSingle();
        _zorunlu = a == null ? false : (a['zorunlu'] as bool? ?? false);
      } catch (_) {
        _zorunlu = null;
      }
      _hataMetni = null;
    } catch (e) {
      _hataMetni = 'Yüklenemedi (supabase_ekip.sql çalıştırıldı mı?): $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _sinirDegistir(bool v) async {
    final atanmamis = _firmalar.length - _atama.length;
    if (v) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Portföy sınırını aç'),
          content: Text('Açtığınızda yardımcılar yalnızca kendilerine atanan mükellefleri görür ve değiştirir.\n'
              '${atanmamis > 0 ? '\nŞu an $atanmamis mükellef kimseye atanmamış; yardımcılar bu mükellefleri göremez.' : ''}'
              '\n\nBeklenmedik bir durum olursa bu anahtarı kapatarak hemen eski haline dönebilirsiniz.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aç')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _db.from('portfoy_ayar').upsert({'id': 1, 'zorunlu': v});
      _zorunlu = v;
      await _gunlugeYaz('Portföy erişim sınırı ${v ? 'açıldı' : 'kapatıldı'}');
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Değiştirilemedi: $e')));
    }
  }

  String _ad(String id) {
    for (final k in _kullanicilar) {
      if (k['user_id'] == id) return ((k['gorunen_ad'] as String).isNotEmpty ? k['gorunen_ad'] : k['giris_adi']) as String;
    }
    return 'Bilinmeyen';
  }

  Future<void> _ata(Map<String, dynamic> f, String? kid) async {
    final id = f['id'] as int;
    try {
      if (kid == null) {
        await _db.from('portfoy').delete().eq('firma_id', id);
        _atama.remove(id);
        await _gunlugeYaz('${f['unvan']}: sorumlu kaldırıldı');
      } else {
        await _db.from('portfoy').upsert({'firma_id': id, 'kullanici_id': kid, 'atama': DateTime.now().toUtc().toIso8601String()});
        _atama[id] = kid;
        await _gunlugeYaz('${f['unvan']}: sorumlu ${_ad(kid)} yapıldı');
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Future<void> _devir() async {
    if (_kullanicilar.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Devir için en az iki yardımcı kullanıcı gerekir.')));
      return;
    }
    String? kimden, kime;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('İş devri'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Portföyü devreden'),
              items: [for (final k in _kullanicilar) DropdownMenuItem(value: k['user_id'] as String, child: Text(_ad(k['user_id'] as String)))],
              onChanged: (v) => setD(() => kimden = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Devralan'),
              items: [for (final k in _kullanicilar) DropdownMenuItem(value: k['user_id'] as String, child: Text(_ad(k['user_id'] as String)))],
              onChanged: (v) => setD(() => kime = v),
            ),
            const SizedBox(height: 8),
            const Text('Geri almak için aynı işlemi ters yönde yaparsınız.', style: TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: kimden != null && kime != null && kimden != kime ? () => Navigator.pop(ctx, true) : null, child: const Text('Devret')),
          ],
        ),
      ),
    );
    if (ok != true || kimden == null || kime == null) return;
    try {
      final n = _atama.values.where((v) => v == kimden).length;
      await _db.from('portfoy').update({'kullanici_id': kime, 'atama': DateTime.now().toUtc().toIso8601String()}).eq('kullanici_id', kimden!);
      await _gunlugeYaz('İş devri: ${_ad(kimden!)} -> ${_ad(kime!)} ($n mükellef)');
      await _yukle();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Devir yapılamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    if (_hataMetni != null) return _hata(_hataMetni!);
    final liste = _firmalar.where((f) => (f['unvan'] as String).toLowerCase().contains(_ara.toLowerCase())).toList();
    return Column(children: [
      if (_zorunlu == null)
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Text('Portföy erişim sınırı için supabase_portfoy_sinir.sql dosyasını çalıştırın.', style: TextStyle(color: Colors.black87)),
        )
      else
        SwitchListTile(
          dense: true,
          value: _zorunlu!,
          onChanged: _sinirDegistir,
          title: const Text('Portföy erişim sınırı'),
          subtitle: Text(_zorunlu!
              ? 'Açık: yardımcılar yalnızca kendilerine atanan mükellefleri görür.'
              : 'Kapalı: yardımcılar izni olan bölümlerde tüm mükellefleri görür.'),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Mükellef ara', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => setState(() => _ara = v),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: _devir, icon: const Icon(Icons.swap_horiz), label: const Text('İş devri')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('${_atama.length} / ${_firmalar.length} mükellefin sorumlusu atanmış.'),
        ),
      ),
      Expanded(
        child: ListView(children: [
          for (final f in liste)
            ListTile(
              title: Text(f['unvan'] as String),
              trailing: SizedBox(
                width: 220,
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _atama[f['id'] as int],
                  hint: const Text('Atanmamış'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Atanmamış')),
                    for (final k in _kullanicilar) DropdownMenuItem<String?>(value: k['user_id'] as String, child: Text(_ad(k['user_id'] as String))),
                  ],
                  onChanged: (v) => _ata(f, v),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- yönetici: onay talepleri
class _TalepYonet extends StatefulWidget {
  const _TalepYonet();
  @override
  State<_TalepYonet> createState() => _TalepYonetState();
}

class _TalepYonetState extends State<_TalepYonet> {
  List<Map<String, dynamic>> _talepler = [];
  final Map<String, String> _adlar = {};
  final Map<int, String> _firmaAd = {};
  bool _yukleniyor = true;
  String? _hataMetni;
  bool _sadeceBekleyen = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      _talepler = List<Map<String, dynamic>>.from(await _db.from('onay_talep').select().order('zaman', ascending: false).limit(200));
      final k = await _db.from('profiller').select('user_id, gorunen_ad, giris_adi').eq('rol', 'yardimci');
      _adlar
        ..clear()
        ..addAll({for (final r in k as List) r['user_id'] as String: ((r['gorunen_ad'] as String).isNotEmpty ? r['gorunen_ad'] : r['giris_adi']) as String});
      final f = await _db.from('firmalar').select('id, unvan');
      _firmaAd
        ..clear()
        ..addAll({for (final r in f as List) r['id'] as int: r['unvan'] as String});
      _hataMetni = null;
    } catch (e) {
      _hataMetni = 'Yüklenemedi (supabase_ekip.sql çalıştırıldı mı?): $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _karar(Map<String, dynamic> t, bool onay) async {
    final not = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(onay ? 'Onayla' : 'Reddet'),
        content: TextField(controller: not, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(onay ? 'Onayla' : 'Reddet')),
        ],
      ),
    );
    final metin = not.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => not.dispose());
    if (ok != true) return;
    try {
      await _db.from('onay_talep').update({
        'durum': onay ? 'onaylandi' : 'reddedildi',
        'karar_notu': metin,
        'karar_zamani': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', t['id'] as int);
      await _gunlugeYaz('Talep ${onay ? 'onaylandı' : 'reddedildi'}: ${t['konu']}');
      await _yukle();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    if (_hataMetni != null) return _hata(_hataMetni!);
    final liste = _talepler.where((t) => !_sadeceBekleyen || t['durum'] == 'bekliyor').toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      SwitchListTile(title: const Text('Yalnız bekleyenleri göster'), value: _sadeceBekleyen, onChanged: (v) => setState(() => _sadeceBekleyen = v)),
      if (liste.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Gösterilecek talep yok.')),
      for (final t in liste)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['konu'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${_firmaAd[t['firma_id']] ?? 'Genel'}  ·  ${_adlar[t['isteyen']] ?? 'Kullanıcı'}  ·  ${_zaman(t['zaman'] as String)}'),
              if ((t['ayrinti'] as String).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t['ayrinti'] as String)),
              const SizedBox(height: 8),
              if (t['durum'] == 'bekliyor')
                Wrap(spacing: 8, children: [
                  FilledButton(onPressed: () => _karar(t, true), child: const Text('Onayla')),
                  OutlinedButton(onPressed: () => _karar(t, false), child: const Text('Reddet')),
                ])
              else
                Text(
                  '${t['durum'] == 'onaylandi' ? 'Onaylandı' : 'Reddedildi'}${(t['karar_notu'] as String).isEmpty ? '' : ': ${t['karar_notu']}'}',
                  style: TextStyle(color: t['durum'] == 'onaylandi' ? Colors.green.shade700 : Colors.red.shade700),
                ),
            ]),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- yönetici: pano
class _Pano extends StatefulWidget {
  const _Pano();
  @override
  State<_Pano> createState() => _PanoState();
}

class _PanoState extends State<_Pano> {
  List<Map<String, dynamic>> _kullanicilar = [];
  final Map<String, int> _firmaSayisi = {}, _bekleyen = {}, _onay = {}, _red = {};
  int _atanmamis = 0;
  bool _yukleniyor = true;
  String? _hataMetni;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      _kullanicilar = List<Map<String, dynamic>>.from(await _db.from('profiller').select('user_id, gorunen_ad, giris_adi').eq('rol', 'yardimci').eq('aktif', true));
      final f = await _db.from('firmalar').select('id');
      final p = await _db.from('portfoy').select('firma_id, kullanici_id');
      _firmaSayisi.clear();
      for (final r in p as List) {
        _firmaSayisi.update(r['kullanici_id'] as String, (v) => v + 1, ifAbsent: () => 1);
      }
      _atanmamis = (f as List).length - p.length;
      final sinir = DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
      final t = await _db.from('onay_talep').select('isteyen, durum, zaman').gte('zaman', sinir);
      _bekleyen.clear();
      _onay.clear();
      _red.clear();
      for (final r in t as List) {
        final m = r['durum'] == 'bekliyor' ? _bekleyen : (r['durum'] == 'onaylandi' ? _onay : _red);
        m.update(r['isteyen'] as String, (v) => v + 1, ifAbsent: () => 1);
      }
      _hataMetni = null;
    } catch (e) {
      _hataMetni = 'Yüklenemedi (supabase_ekip.sql çalıştırıldı mı?): $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    if (_hataMetni != null) return _hata(_hataMetni!);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Atanmamış mükellef: $_atanmamis', style: TextStyle(color: _atanmamis > 0 ? Colors.orange.shade800 : null)),
      const SizedBox(height: 8),
      if (_kullanicilar.isEmpty) const Text('Henüz yardımcı kullanıcı yok.'),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final k in _kullanicilar)
          SizedBox(
            width: 260,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(((k['gorunen_ad'] as String).isNotEmpty ? k['gorunen_ad'] : k['giris_adi']) as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Mükellef sayısı: ${_firmaSayisi[k['user_id']] ?? 0}'),
                  Text('Onay bekleyen talep: ${_bekleyen[k['user_id']] ?? 0}'),
                  const Divider(),
                  const Text('Son 30 gün', style: TextStyle(fontSize: 12)),
                  Text('Onaylanan: ${_onay[k['user_id']] ?? 0}  ·  Reddedilen: ${_red[k['user_id']] ?? 0}'),
                ]),
              ),
            ),
          ),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- yönetici: günlük
class _Gunluk extends StatelessWidget {
  const _Gunluk();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _db.from('ekip_gunluk').select().order('zaman', ascending: false).limit(100),
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _hata('Günlük okunamadı: ${s.error}');
        final l = s.data as List;
        if (l.isEmpty) return const Center(child: Text('Henüz kayıt yok.'));
        return ListView(children: [
          for (final r in l) ListTile(dense: true, title: Text(r['konu'] as String), subtitle: Text('${r['kullanici']}  ·  ${_zaman(r['zaman'] as String)}')),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- yardımcı
class _PortfoyBenim extends StatelessWidget {
  const _PortfoyBenim();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _db.from('portfoy').select('firma_id, atama, firmalar(unvan)').eq('kullanici_id', _db.auth.currentUser!.id),
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _hata('Okunamadı: ${s.error}');
        final l = [...(s.data as List)]..sort((a, b) => ((a['firmalar']?['unvan'] ?? '') as String).compareTo((b['firmalar']?['unvan'] ?? '') as String));
        if (l.isEmpty) return const Center(child: Text('Size atanmış mükellef yok.'));
        return ListView(children: [
          Padding(padding: const EdgeInsets.all(12), child: Text('${l.length} mükellef sizin sorumluluğunuzda.')),
          for (final r in l) ListTile(dense: true, leading: const Icon(Icons.business_outlined), title: Text((r['firmalar']?['unvan'] ?? 'Mükellef') as String)),
        ]);
      },
    );
  }
}

class _TalepGonder extends StatefulWidget {
  const _TalepGonder();
  @override
  State<_TalepGonder> createState() => _TalepGonderState();
}

class _TalepGonderState extends State<_TalepGonder> {
  final _konu = TextEditingController(), _ayrinti = TextEditingController();
  List<Map<String, dynamic>> _firmalar = [];
  int? _firma;
  bool _gonderiyor = false;
  String? _mesaj;

  @override
  void initState() {
    super.initState();
    _db.from('firmalar').select('id, unvan').order('unvan').then((r) {
      if (mounted) setState(() => _firmalar = List<Map<String, dynamic>>.from(r));
    });
  }

  @override
  void dispose() {
    _konu.dispose();
    _ayrinti.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    if (_konu.text.trim().isEmpty) {
      setState(() => _mesaj = 'Konu yazın.');
      return;
    }
    setState(() {
      _gonderiyor = true;
      _mesaj = null;
    });
    try {
      await _db.from('onay_talep').insert({'firma_id': _firma, 'konu': _konu.text.trim(), 'ayrinti': _ayrinti.text.trim()});
      _konu.clear();
      _ayrinti.clear();
      _mesaj = 'Onaya gönderildi.';
    } catch (e) {
      _mesaj = 'Gönderilemedi: $e';
    }
    if (mounted) setState(() => _gonderiyor = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Yönetici onayı gereken bir işi (hazırlanan beyanname, dilekçe, bordro vb.) buradan bildirin.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<int?>(
        decoration: const InputDecoration(labelText: 'Mükellef (isteğe bağlı)', border: OutlineInputBorder()),
        value: _firma,
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Genel')),
          for (final f in _firmalar) DropdownMenuItem<int?>(value: f['id'] as int, child: Text(f['unvan'] as String)),
        ],
        onChanged: (v) => setState(() => _firma = v),
      ),
      const SizedBox(height: 12),
      TextField(controller: _konu, decoration: const InputDecoration(labelText: 'Konu (örn. Mart KDV beyannamesi hazır)', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _ayrinti, maxLines: 4, decoration: const InputDecoration(labelText: 'Ayrıntı / dikkat edilecekler', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: FilledButton(onPressed: _gonderiyor ? null : _gonder, child: const Text('Onaya gönder'))),
      if (_mesaj != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_mesaj!)),
    ]);
  }
}

class _TalepBenim extends StatelessWidget {
  const _TalepBenim();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _db.from('onay_talep').select().eq('isteyen', _db.auth.currentUser!.id).order('zaman', ascending: false).limit(100),
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _hata('Okunamadı: ${s.error}');
        final l = s.data as List;
        if (l.isEmpty) return const Center(child: Text('Henüz talebiniz yok.'));
        return ListView(children: [
          for (final t in l)
            ListTile(
              title: Text(t['konu'] as String),
              subtitle: Text('${_zaman(t['zaman'] as String)}${(t['karar_notu'] as String).isEmpty ? '' : '\nYönetici notu: ${t['karar_notu']}'}'),
              isThreeLine: (t['karar_notu'] as String).isNotEmpty,
              trailing: Text(
                t['durum'] == 'bekliyor' ? 'Bekliyor' : (t['durum'] == 'onaylandi' ? 'Onaylandı' : 'Reddedildi'),
                style: TextStyle(color: t['durum'] == 'onaylandi' ? Colors.green.shade700 : (t['durum'] == 'reddedildi' ? Colors.red.shade700 : null)),
              ),
            ),
        ]);
      },
    );
  }
}
