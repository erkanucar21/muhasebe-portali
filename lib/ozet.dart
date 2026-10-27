part of 'beyanname_kontrol.dart';

/// Özet ekranı. Yönetici: bu ayın beyanname durumu, son günü yaklaşanlar, bugün izinde olanlar.
/// Mükellef (firmaId dolu): yeni gelen belgeler ve ödenmemiş tahakkuklar.
class OzetSayfasi extends StatefulWidget {
  final int? firmaId;
  const OzetSayfasi({super.key, this.firmaId});
  @override
  State<OzetSayfasi> createState() => _OzetSayfasiState();
}

class _Dikkat {
  final Firma f;
  final String tur;
  final DateTime tarih;
  _Dikkat(this.f, this.tur, this.tarih);
}

class _OzetSayfasiState extends State<OzetSayfasi> {
  final _db = Supabase.instance.client;
  bool _yukleniyor = true;
  String? _hata;

  // --- yönetici ---
  late int _yil, _ay;
  final List<_Dikkat> _dikkat = [];
  final Map<String, (int, int)> _ilerleme = {}; // tür -> (tamam, toplam)
  final List<(String, String, String)> _izinli = []; // (personel, firma, durum)
  final List<(String, String, DateTime)> _suresiDolan = []; // (firma, belge, bitiş)
  final List<(String, String, String, DateTime)> _personelUyari = []; // (firma, personel, açıklama, tarih)
  final List<Map<String, dynamic>> _notlar = [];
  bool _notHata = false;
  double _ucretBorc = 0; // geçmiş aylardan kalan müşavirlik ücreti borcu
  int _ucretBorcFirma = 0;
  int _akisGecikme = 0; // süresi geçmiş, tamamlanmamış iş akışı adımları
  int _bekleyen = 0, _gecen = 0, _firmaSayisi = 0;

  // --- mükellef ---
  DateTime? _sonGorus;
  final List<Map<String, dynamic>> _belgeler = [];
  int _odenmemis = 0;
  final List<Map<String, dynamic>> _bildirimler = [];

  bool get _yonetici => widget.firmaId == null;

  @override
  void initState() {
    super.initState();
    final simdi = DateTime.now();
    _yil = simdi.month == 1 ? simdi.year - 1 : simdi.year;
    _ay = simdi.month == 1 ? 12 : simdi.month - 1;
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      if (_yonetici) {
        await _yoneticiYukle();
      } else {
        await _musteriYukle();
      }
    } catch (e) {
      _hata = 'Özet yüklenemedi: $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _yoneticiYukle() async {
    await FirmaDeposu.ornek.yukle();
    await _istisnalariYukle();
    await _ozelYukle();
    final firmalar = FirmaDeposu.ornek.liste;
    final satirlar = await _db.from('beyanname_kontrol').select().eq('yil', _yil).eq('ay', _ay);
    final durum = <String, int>{
      for (final s in satirlar) '${s['firma_id']}|${s['beyanname']}': (s['durum'] as num).toInt()
    };
    final ayBas = DateTime(_yil, _ay, 1);
    final aySon = DateTime(_yil, _ay + 1, 0);
    final personel = await _db.from('personel').select('id, ad, firma_id, giris, cikis');
    final personelli = <int>{};
    for (final s in personel) {
      final giris = DateTime.parse(s['giris'] as String);
      final cikis = s['cikis'] == null ? null : DateTime.parse(s['cikis'] as String);
      if (!giris.isAfter(aySon) && (cikis == null || !cikis.isBefore(ayBas))) personelli.add(s['firma_id'] as int);
    }

    _dikkat.clear();
    _ilerleme.clear();
    _bekleyen = 0;
    _gecen = 0;
    _firmaSayisi = firmalar.length;
    for (final t in _tumTurler(_ay)) {
      var tamam = 0, toplam = 0;
      for (final f in firmalar) {
        final gecerli = t == _sgk
            ? personelli.contains(f.id)
            : t == _edefter
                ? f.eDefter
                : t == _gekap
                    ? f.gekap
                    : _ozelBul(t) != null
                        ? (_ozelBul(t)!.tum || _ozelBul(t)!.firmalar.contains(f.id))
                        : true;
        if (!gecerli) continue;
        toplam++;
        final tamamDeger = t == _edefter ? 2 : 1;
        if ((durum['${f.id}|$t'] ?? 0) >= tamamDeger) {
          tamam++;
          continue;
        }
        _bekleyen++;
        final tarihler = t == _edefter ? [_edefterSonGun(f, _yil, _ay).$2] : (_sonTarihler(t, _yil, _ay, firma: f.id).map((e) => e.$2).toList()..sort());
        final yaklasan = tarihler.where((d) => _uyari(d) != null).toList();
        if (yaklasan.isNotEmpty) {
          _dikkat.add(_Dikkat(f, t, yaklasan.first));
          if (_uyari(yaklasan.first)!.$1.contains('geçti')) _gecen++;
        }
      }
      _ilerleme[t] = (tamam, toplam);
    }
    _dikkat.sort((a, b) => a.tarih.compareTo(b.tarih));

    _suresiDolan.clear();
    try {
      final sinir = DateTime.now().add(const Duration(days: 30));
      final sonuc = await _db
          .from('firma_belge')
          .select('firma_id, ad, gecerlilik')
          .not('gecerlilik', 'is', null)
          .lte('gecerlilik', '${sinir.year}-${sinir.month.toString().padLeft(2, '0')}-${sinir.day.toString().padLeft(2, '0')}');
      for (final b in sonuc) {
        final f = FirmaDeposu.ornek.bul(b['firma_id'] as int);
        if (f != null) _suresiDolan.add((f.unvan, b['ad'] as String, DateTime.parse(b['gecerlilik'] as String)));
      }
      _suresiDolan.sort((a, b) => a.$3.compareTo(b.$3));
    } catch (_) {}

    // Personel işlemleri: SGK bildirge son günleri, ihbar süresi, belirli süreli sözleşme bitişi
    _personelUyari.clear();
    final n0 = DateTime.now();
    final bugun0 = DateTime(n0.year, n0.month, n0.day);
    final sozlesmeBitis = <int, DateTime>{};
    try {
      final sz = await _db.from('personel').select('id, sozlesme_bitis').not('sozlesme_bitis', 'is', null);
      for (final r in sz) {
        sozlesmeBitis[r['id'] as int] = DateTime.parse(r['sozlesme_bitis'] as String);
      }
    } catch (_) {}
    for (final s in personel) {
      final giris = DateTime.parse(s['giris'] as String);
      final cikis = s['cikis'] == null ? null : DateTime.parse(s['cikis'] as String);
      final firma = FirmaDeposu.ornek.bul(s['firma_id'] as int)?.unvan ?? '';
      final ad = s['ad'] as String;
      final girisFark = giris.difference(bugun0).inDays;
      if (cikis == null && girisFark >= -3 && girisFark <= 14) {
        _personelUyari.add((firma, ad, 'SGK işe giriş bildirgesi (işe başlamadan önce verilir)', DateTime(giris.year, giris.month, giris.day - 1)));
      }
      if (cikis != null) {
        final cikisFark = cikis.difference(bugun0).inDays;
        if (cikisFark >= -10 && cikisFark <= 14) {
          _personelUyari.add((firma, ad, 'SGK işten çıkış bildirgesi (çıkıştan sonra 10 gün içinde)', DateTime(cikis.year, cikis.month, cikis.day + 10)));
        }
        if (cikisFark >= 0 && cikisFark <= 90) {
          final ay = (cikis.year - giris.year) * 12 + cikis.month - giris.month - (cikis.day < giris.day ? 1 : 0);
          final hafta = ay < 6 ? 2 : (ay < 18 ? 4 : (ay < 36 ? 6 : 8));
          final enGec = DateTime(cikis.year, cikis.month, cikis.day - hafta * 7);
          _personelUyari.add((firma, ad, 'İhbar bildirimi en geç bu tarihte yapılmalı ($hafta hafta, çıkış ${_gunYaz(cikis)})', enGec));
        }
      }
      final bitis = sozlesmeBitis[s['id'] as int];
      if (cikis == null && bitis != null) {
        final f = bitis.difference(bugun0).inDays;
        if (f >= -30 && f <= 45) {
          _personelUyari.add((firma, ad, f < 0 ? 'Belirli süreli sözleşmenin süresi doldu (yenilenmediyse çıkış, devam ediyorsa belirsiz süreli sayılır)' : 'Belirli süreli sözleşme bitiyor', bitis));
        }
      }
    }
    _personelUyari.sort((a, b) => a.$4.compareTo(b.$4));

    await _notlariYukle();
    await _ucretBorcuYukle();
    await _akisGecikmeYukle();

    // Bugün izinde / raporlu / gelmeyen personel
    _izinli.clear();
    final bugun = DateTime.now();
    final kayitlar = await _db.from('izin_kayitlari').select().eq('tarih', _sqlTarihOzet(bugun));
    final ad = {for (final s in personel) s['id'] as int: (s['ad'] as String, s['firma_id'] as int)};
    for (final k in kayitlar) {
      final p = ad[k['personel_id'] as int];
      if (p == null) continue;
      final d = switch (k['durum']) { 'izin' => 'İzinli', 'rapor' => 'Raporlu', 'gelmedi' => 'Gelmedi', _ => '${k['durum']}' };
      _izinli.add((p.$1, FirmaDeposu.ornek.bul(p.$2)?.unvan ?? '', d));
    }
  }

  /// Geçmiş aylardan (bu ay hariç) kalan ücret borcunu hesaplar. Ücret takibi tabloları yoksa veya izin yoksa sessizce atlanır.
  Future<void> _akisGecikmeYukle() async {
    _akisGecikme = 0;
    try {
      final b = DateTime.now();
      final r = await _db
          .from('is_akisi_adim')
          .select('id, is_akisi!inner(kapandi)')
          .eq('tamam', false)
          .lt('hedef', _sqlTarihOzet(DateTime(b.year, b.month, b.day)))
          .eq('is_akisi.kapandi', false);
      _akisGecikme = r.length;
    } catch (_) {
      _akisGecikme = 0; // tablo yoksa (supabase_is_akisi.sql çalıştırılmadıysa) gösterilmez
    }
  }

  Future<void> _ucretBorcuYukle() async {
    _ucretBorc = 0;
    _ucretBorcFirma = 0;
    try {
      final ayar = await _db.from('ucret_ayar').select();
      final takip = await _db.from('ucret_takip').select();
      final kalem = await _db.from('ucret_kalem').select();
      final ayarlar = <int, List<(int, double)>>{};
      for (final a in ayar) {
        final d = DateTime.parse(a['gecerli'] as String);
        (ayarlar[a['firma_id'] as int] ??= []).add((d.year * 12 + d.month - 1, (a['aylik'] as num).toDouble()));
      }
      for (final l in ayarlar.values) {
        l.sort((a, b) => a.$1.compareTo(b.$1));
      }
      final tak = <String, Map<String, dynamic>>{};
      for (final t in takip) {
        tak['${t['firma_id']}|${t['yil']}|${t['ay']}'] = Map<String, dynamic>.from(t);
      }
      final kal = <String, double>{};
      for (final k in kalem) {
        final key = '${k['firma_id']}|${k['yil']}|${k['ay']}';
        kal[key] = (kal[key] ?? 0) + (k['tutar'] as num).toDouble();
      }
      final n = DateTime.now();
      final simdi = n.year * 12 + n.month - 1;
      for (final e in ayarlar.entries) {
        if (FirmaDeposu.ornek.bul(e.key) == null) continue;
        var toplam = 0.0;
        for (var i = e.value.first.$1; i < simdi; i++) {
          final y = i ~/ 12, a = i % 12 + 1;
          final key = '${e.key}|$y|$a';
          double? efektif;
          for (final (gi, u) in e.value) {
            if (gi <= i) efektif = u;
          }
          final tutar = kal[key] ?? (tak[key]?['tutar'] as num?)?.toDouble() ?? efektif ?? 0;
          toplam += tutar - ((tak[key]?['tahsil'] ?? 0) as num).toDouble();
        }
        if (toplam > 0.5) {
          _ucretBorc += toplam;
          _ucretBorcFirma++;
        }
      }
    } catch (_) {
      _ucretBorc = 0;
      _ucretBorcFirma = 0;
    }
  }

  Future<void> _notlariYukle() async {
    try {
      final r = await _db.from('ozet_not').select().order('id');
      _notlar
        ..clear()
        ..addAll(r.cast<Map<String, dynamic>>());
      _notHata = false;
    } catch (_) {
      _notHata = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _notTamam(Map<String, dynamic> n, bool tamam) async {
    try {
      await _db.from('ozet_not').update({'tamam': tamam}).eq('id', n['id']);
      n['tamam'] = tamam;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Güncellenemedi: $e')));
    }
  }

  Future<void> _notForm([Map<String, dynamic>? m]) async {
    final metin = TextEditingController(text: (m?['metin'] ?? '') as String);
    DateTime? tarih = m?['hatirlatma'] == null ? null : DateTime.parse(m!['hatirlatma'] as String);
    int? firma = m?['firma_id'] as int?;
    final sonuc = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(m == null ? 'Not ekle' : 'Notu düzenle'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: metin,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Not', hintText: 'Örn. SGK dilekçesini ver, evrakı iste'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: c,
                        initialDate: tarih ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        locale: const Locale('tr', 'TR'),
                      );
                      if (d != null) setD(() => tarih = d);
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(tarih == null ? 'Hatırlatma tarihi (isteğe bağlı)' : 'Hatırlatma: ${_gunYaz(tarih!)}'),
                  ),
                ),
                if (tarih != null) IconButton(tooltip: 'Tarihi kaldır', icon: const Icon(Icons.close), onPressed: () => setD(() => tarih = null)),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: firma,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Firma (isteğe bağlı)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Firma yok')),
                  for (final f in FirmaDeposu.ornek.liste) DropdownMenuItem<int?>(value: f.id, child: Text(f.unvan, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setD(() => firma = v),
              ),
            ]),
          ),
          actions: [
            if (m != null) TextButton(onPressed: () => Navigator.pop(c, 'sil'), child: const Text('Sil', style: TextStyle(color: Colors.red))),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, 'kaydet'), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (sonuc == null) return;
    try {
      if (sonuc == 'sil') {
        await _db.from('ozet_not').delete().eq('id', m!['id']);
      } else {
        final t = metin.text.trim();
        if (t.isEmpty) return;
        final kayit = {'metin': t, 'hatirlatma': tarih == null ? null : _sqlTarihOzet(tarih!), 'firma_id': firma};
        if (m == null) {
          await _db.from('ozet_not').insert(kayit);
        } else {
          await _db.from('ozet_not').update(kayit).eq('id', m['id']);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
    await _notlariYukle();
  }

  Widget _notSatiri(Map<String, dynamic> n) {
    const kirmizi = Color(0xFFB3261E);
    const turuncu = Color(0xFFEF6C00);
    final bitti = n['tamam'] == true;
    final h = n['hatirlatma'] == null ? null : DateTime.parse(n['hatirlatma'] as String);
    final simdi = DateTime.now();
    final fark = h == null ? 0 : h.difference(DateTime(simdi.year, simdi.month, simdi.day)).inDays;
    final renk = h == null || bitti ? Colors.black87 : (fark < 0 ? kirmizi : (fark <= 3 ? turuncu : Colors.black87));
    final durum = h == null ? '' : (fark < 0 ? '${-fark} gün geçti' : (fark == 0 ? 'Bugün' : '$fark gün kaldı'));
    final firma = n['firma_id'] == null ? null : FirmaDeposu.ornek.bul(n['firma_id'] as int)?.unvan;
    return ListTile(
      dense: true,
      onTap: () => _notForm(n),
      leading: Checkbox(value: bitti, onChanged: (v) => _notTamam(n, v ?? false)),
      title: Text(n['metin'] as String, style: TextStyle(decoration: bitti ? TextDecoration.lineThrough : null, color: bitti ? Colors.black87 : null)),
      subtitle: firma == null ? null : Text(firma, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: h == null
          ? null
          : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_gunYaz(h), style: TextStyle(fontWeight: FontWeight.w700, color: renk)),
              if (!bitti) Text(durum, style: TextStyle(fontSize: 12, color: renk)),
            ]),
    );
  }

  Widget _notBolumu() {
    final acik = _notlar.where((n) => n['tamam'] != true).toList()
      ..sort((a, b) {
        final x = a['hatirlatma'] as String?, y = b['hatirlatma'] as String?;
        if (x == null && y == null) return (a['id'] as int).compareTo(b['id'] as int);
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      });
    final bitenler = _notlar.where((n) => n['tamam'] == true).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _baslik('Notlar ve hatırlatmalar')),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: FilledButton.tonalIcon(onPressed: () => _notForm(), icon: const Icon(Icons.add, size: 18), label: const Text('Not ekle')),
        ),
      ]),
      Card(
        elevation: 0,
        color: Colors.white,
        child: _notHata
            ? const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Notlar için supabase_ozet_not.sql dosyasını bir kez çalıştırman gerekiyor.'),
              )
            : Column(children: [
                if (acik.isEmpty)
                  const ListTile(dense: true, leading: Icon(Icons.edit_note), title: Text('Açık not yok. Hatırlatma tarihi verirsen son tarih gibi öne çıkar.'))
                else
                  for (final n in acik) _notSatiri(n),
                if (bitenler.isNotEmpty)
                  ExpansionTile(
                    dense: true,
                    title: Text('Tamamlananlar (${bitenler.length})', style: const TextStyle(fontSize: 13)),
                    children: [for (final n in bitenler) _notSatiri(n)],
                  ),
              ]),
      ),
    ]);
  }

  String _sqlTarihOzet(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _musteriYukle() async {
    try {
      final uid = _db.auth.currentUser?.id;
      final p = await _db.from('profiller').select('son_belge_gorus').eq('user_id', uid ?? '').maybeSingle();
      final s = p?['son_belge_gorus'];
      _sonGorus = s == null ? null : DateTime.parse(s as String).toLocal();
    } catch (_) {
      _sonGorus = null; // sütun henüz yoksa
    }
    final rows = await _db
        .from('belgeler')
        .select()
        .eq('firma_id', widget.firmaId!)
        .order('yuklenme', ascending: false)
        .limit(40);
    _belgeler
      ..clear()
      ..addAll(rows.cast<Map<String, dynamic>>());
    _odenmemis = _belgeler.where((b) => b['tur'] == 'tahakkuk' && b['odendi'] != true).length;
    _bildirimler.clear();
    try {
      final b = await _db
          .from('bildirim')
          .select()
          .eq('firma_id', widget.firmaId!)
          .order('olusturma', ascending: false)
          .limit(10);
      _bildirimler.addAll(b.cast<Map<String, dynamic>>());
    } catch (_) {
      // tablo yoksa (supabase_bildirim_kilit.sql çalıştırılmadıysa) bildirim gösterilmez
    }
  }

  Future<void> _bildirimOkundu() async {
    try {
      await _db.from('bildirim').update({'okundu': true}).eq('firma_id', widget.firmaId!).eq('okundu', false);
      for (final b in _bildirimler) {
        b['okundu'] = true;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _bildirimTarih(String iso) {
    final t = DateTime.parse(iso).toLocal();
    String i(int n) => n.toString().padLeft(2, '0');
    return '${i(t.day)}.${i(t.month)}.${t.year}';
  }

  bool _yeniMi(Map<String, dynamic> b) {
    final y = DateTime.parse(b['yuklenme'] as String).toLocal();
    final esik = _sonGorus ?? DateTime.now().subtract(const Duration(days: 14));
    return y.isAfter(esik);
  }

  Future<void> _gordum() async {
    try {
      await _db.rpc('belge_gordum');
      _sonGorus = DateTime.now();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İşaretlenemedi: $e')));
    }
  }

  static const _turAdlari = {
    'kdvBeyannamesi': 'KDV Beyannamesi',
    'muhtasarBeyannamesi': 'Muhtasar ve Prim Hizmet Beyannamesi',
    'gelirVergisi': 'Gelir Vergisi Beyannamesi',
    'kurumlarVergisi': 'Kurumlar Vergisi Beyannamesi',
    'geciciVergi': 'Geçici Vergi Beyannamesi',
    'sgkHizmet': 'SGK Hizmet Dökümü',
    'tahakkuk': 'Tahakkuk Fişi',
  };

  Widget _kart(IconData ikon, String sayi, String etiket, Color renk, {VoidCallback? onTap}) => SizedBox(
        width: 200,
        child: Card(
          elevation: 0,
          color: Colors.white,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                CircleAvatar(backgroundColor: renk.withValues(alpha: 0.14), child: Icon(ikon, color: renk)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sayi, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: renk)),
                    Text(etiket, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _baslik(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _yoneticiGorunumu() {
    const kirmizi = Color(0xFFB3261E);
    const yesil = Color(0xFF2E7D32);
    const turuncu = Color(0xFFEF6C00);
    final izinSayisi = _izinli.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_aylar[_ay - 1]} $_yil dönemi beyannameleri',
          style: const TextStyle(fontSize: 13, color: Colors.black87)),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _kart(Icons.business_outlined, '$_firmaSayisi', 'Mükellef firma', Theme.of(context).colorScheme.primary,
            onTap: () => bolumIstegi.value = 'Firmalar'),
        _kart(Icons.hourglass_empty, '$_bekleyen', 'Bekleyen işlem', turuncu,
            onTap: () => bolumIstegi.value = 'Kontrol listesi'),
        _kart(Icons.warning_amber_rounded, '${_dikkat.length}', 'Son günü yaklaşan / geçen', kirmizi,
            onTap: () => bolumIstegi.value = 'Kontrol listesi'),
        _kart(Icons.event_busy_outlined, '$izinSayisi', 'Bugün izin/rapor/gelmedi', yesil,
            onTap: () => bolumIstegi.value = 'Personel'),
        if (_ucretBorcFirma > 0)
          _kart(Icons.payments_outlined, '${tl(_ucretBorc).split(',').first} ₺', '$_ucretBorcFirma firmanın geçmiş ücret borcu', turuncu,
              onTap: () => bolumIstegi.value = 'Ücret takibi'),
        if (_akisGecikme > 0)
          _kart(Icons.checklist_outlined, '$_akisGecikme', 'Geciken iş akışı adımı', kirmizi,
              onTap: () => bolumIstegi.value = 'İş akışları'),
      ]),
      _notBolumu(),
      _baslik('Dikkat: son günü yaklaşan veya geçen'),
      if (_dikkat.isEmpty)
        const Card(
          elevation: 0,
          color: Colors.white,
          child: ListTile(leading: Icon(Icons.check_circle, color: yesil), title: Text('Acil bir iş görünmüyor.')),
        )
      else
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(children: [
            for (final d in _dikkat.take(15))
              ListTile(
                dense: true,
                onTap: () => bolumIstegi.value = 'Kontrol listesi',
                leading: Icon(Icons.warning_amber_rounded, color: _uyari(d.tarih)!.$2),
                title: Text(d.f.unvan, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${_sutunAdi(d.tur)} • son gün ${_gunYaz(d.tarih)}'),
                trailing: Text(_uyari(d.tarih)!.$1,
                    style: TextStyle(fontWeight: FontWeight.w700, color: _uyari(d.tarih)!.$2)),
              ),
            if (_dikkat.length > 15)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text('… ve ${_dikkat.length - 15} kayıt daha (Kontrol listesinde).',
                    style: const TextStyle(color: Colors.black87)),
              ),
          ]),
        ),
      if (_suresiDolan.isNotEmpty) ...[
        _baslik('Arşiv belgelerinde süresi dolan veya dolmak üzere olan'),
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(children: [
            for (final d in _suresiDolan.take(10))
              ListTile(
                dense: true,
                leading: Icon(Icons.folder_off_outlined, color: d.$3.isBefore(DateTime.now()) ? kirmizi : turuncu),
                title: Text(d.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(d.$2),
                trailing: Text(_gunYaz(d.$3), style: TextStyle(fontWeight: FontWeight.w700, color: d.$3.isBefore(DateTime.now()) ? kirmizi : turuncu)),
              ),
            if (_suresiDolan.length > 10)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text('… ve ${_suresiDolan.length - 10} belge daha.', style: const TextStyle(color: Colors.black87)),
              ),
          ]),
        ),
      ],
      if (_personelUyari.isNotEmpty) ...[
        _baslik('Personel işlemleri'),
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(children: [
            for (final d in _personelUyari.take(12))
              ListTile(
                dense: true,
                onTap: () => bolumIstegi.value = 'Personel',
                leading: Icon(Icons.badge_outlined, color: d.$4.isBefore(DateTime.now().subtract(const Duration(days: 1))) ? kirmizi : turuncu),
                title: Text('${d.$2}  •  ${d.$1}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(d.$3),
                trailing: Text(_gunYaz(d.$4),
                    style: TextStyle(fontWeight: FontWeight.w700, color: d.$4.isBefore(DateTime.now().subtract(const Duration(days: 1))) ? kirmizi : turuncu)),
              ),
            if (_personelUyari.length > 12)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text('… ve ${_personelUyari.length - 12} kayıt daha.', style: const TextStyle(color: Colors.black87)),
              ),
          ]),
        ),
      ],
      _baslik('Bu ayın ilerlemesi'),
      Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            for (final t in _tumTurler(_ay))
              if ((_ilerleme[t]?.$2 ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 90, child: Text(_sutunAdi(t), style: const TextStyle(fontSize: 13))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: _ilerleme[t]!.$1 / _ilerleme[t]!.$2,
                          backgroundColor: const Color(0xFFF3D4D4),
                          color: yesil,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text('${_ilerleme[t]!.$1}/${_ilerleme[t]!.$2}',
                          textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
          ]),
        ),
      ),
      _baslik('Bugün izinde / raporlu / gelmeyen personel'),
      Card(
        elevation: 0,
        color: Colors.white,
        child: _izinli.isEmpty
            ? const ListTile(dense: true, title: Text('Bugün kayıtlı izin, rapor veya devamsızlık yok.'))
            : Column(children: [
                for (final i in _izinli)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(i.$1),
                    subtitle: Text(i.$2),
                    trailing: Text(i.$3, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
      ),
    ]);
  }

  Widget _musteriGorunumu() {
    const turuncu = Color(0xFFEF6C00);
    final yeniler = _belgeler.where(_yeniMi).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _kart(Icons.mark_email_unread_outlined, '${yeniler.length}', 'Yeni belge', Theme.of(context).colorScheme.primary,
            onTap: () => bolumIstegi.value = 'Beyannameler'),
        _kart(Icons.payments_outlined, '$_odenmemis', 'Ödenmemiş tahakkuk', turuncu,
            onTap: () => bolumIstegi.value = 'Beyannameler'),
      ]),
      if (_bildirimler.isNotEmpty) ...[
        _baslik('Bildirimler'),
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(children: [
            for (final b in _bildirimler.take(6))
              ListTile(
                dense: true,
                leading: Icon(b['okundu'] == true ? Icons.check_circle_outline : Icons.check_circle, color: const Color(0xFF2E7D32)),
                title: Text('${b['baslik']}', style: TextStyle(fontWeight: b['okundu'] == true ? FontWeight.normal : FontWeight.w700)),
                subtitle: Text('${b['metin']}'),
                trailing: Text(_bildirimTarih(b['olusturma'] as String), style: const TextStyle(fontSize: 12, color: Colors.black87)),
              ),
            if (_bildirimler.any((b) => b['okundu'] != true))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _bildirimOkundu, child: const Text('Okundu say')),
              ),
          ]),
        ),
      ],
      if (yeniler.isNotEmpty) ...[
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          color: const Color(0xFFFFF4D6),
          child: ListTile(
            leading: const Icon(Icons.notifications_active_outlined, color: turuncu),
            title: Text('${yeniler.length} yeni belgeniz var'),
            subtitle: const Text('Müşavirinizin yüklediği belgeler aşağıda.'),
            trailing: TextButton(onPressed: _gordum, child: const Text('Gördüm')),
          ),
        ),
      ],
      _baslik('Son belgeler'),
      Card(
        elevation: 0,
        color: Colors.white,
        child: _belgeler.isEmpty
            ? const ListTile(title: Text('Henüz belge yok.'))
            : Column(children: [
                for (final b in _belgeler.take(8))
                  ListTile(
                    dense: true,
                    onTap: () => bolumIstegi.value = 'Beyannameler',
                    leading: const Icon(Icons.description_outlined),
                    title: Text(_turAdlari['${b['tur']}'] ?? '${b['tur']}'),
                    subtitle: Text([
                      if ('${b['beyanname'] ?? ''}'.isNotEmpty) '${b['beyanname']}',
                      '${b['donem']} ${b['yil']}',
                    ].join(' • ')),
                    trailing: _yeniMi(b)
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: turuncu, borderRadius: BorderRadius.circular(10)),
                            child: const Text('YENİ',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          )
                        : (b['tur'] == 'tahakkuk' && b['odendi'] != true
                            ? const Text('Ödenmedi', style: TextStyle(color: turuncu, fontSize: 12))
                            : null),
                  ),
              ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Text('Genel durum', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
                  IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh)),
                ]),
                if (_hata != null) Text(_hata!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                _yonetici ? _yoneticiGorunumu() : _musteriGorunumu(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
