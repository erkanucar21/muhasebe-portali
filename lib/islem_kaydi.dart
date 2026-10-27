import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kim, ne zaman, hangi firmada neyi ekledi / değiştirdi / sildi. Sadece yönetici.
class IslemKaydiSekmesi extends StatefulWidget {
  const IslemKaydiSekmesi({super.key});
  @override
  State<IslemKaydiSekmesi> createState() => _IslemKaydiSekmesiState();
}

class _IslemKaydiSekmesiState extends State<IslemKaydiSekmesi> {
  final _db = Supabase.instance.client;
  bool _yukleniyor = true;
  String? _hata;
  final List<Map<String, dynamic>> _kayitlar = [];
  Map<int, String> _firmalar = {};
  int? _firma;
  String? _tablo;
  String? _islem;
  bool _dahaVar = false;
  int _gorunum = 0;
  int _ozetGun = 7;
  bool _ozetYukleniyor = false;
  String? _ozetHata;
  List<Map<String, dynamic>> _ozetKayitlar = [];
  final List<Map<String, dynamic>> _girisler = [];
  String? _girisHata;
  bool _girisYukleniyor = false;
  static const _sayfa = 100;

  static const _tabloAd = {
    'firmalar': 'Firma',
    'personel': 'Personel',
    'beyanname_kontrol': 'Kontrol listesi',
    'belgeler': 'Belge',
    'ucret_takip': 'Ücret takibi',
    'ucret_kalem': 'Ücret kalemi',
    'ucret_ayar': 'Ücret ayarı',
    'ozet_not': 'Not',
    'yedek': 'Yedek',
  };
  static const _islemAd = {'INSERT': 'Ekledi', 'UPDATE': 'Değiştirdi', 'DELETE': 'Sildi', 'GERI_YUKLEME': 'Geri yükledi'};

  @override
  void initState() {
    super.initState();
    _yukle(sifirla: true);
  }

  Future<void> _yukle({bool sifirla = false}) async {
    if (sifirla) {
      _kayitlar.clear();
    }
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      if (_firmalar.isEmpty) {
        final f = await _db.from('firmalar').select('id, unvan').order('unvan');
        _firmalar = {for (final x in f) (x['id'] as num).toInt(): x['unvan'] as String};
      }
      var q = _db.from('islem_kaydi').select();
      if (_firma != null) q = q.eq('firma_id', _firma!);
      if (_tablo != null) q = q.eq('tablo', _tablo!);
      if (_islem != null) q = q.eq('islem', _islem!);
      final r = await q.order('zaman', ascending: false).range(_kayitlar.length, _kayitlar.length + _sayfa - 1);
      final liste = r.cast<Map<String, dynamic>>();
      _kayitlar.addAll(liste);
      _dahaVar = liste.length == _sayfa;
    } catch (e) {
      _hata = 'İşlem kaydı okunamadı: $e\n(supabase_islem_kaydi.sql çalıştırıldı mı?)';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _girisYukle() async {
    setState(() {
      _girisYukleniyor = true;
      _girisHata = null;
    });
    try {
      final r = await _db.rpc('giris_olaylari', params: {'p_limit': 200});
      _girisler
        ..clear()
        ..addAll((r as List).cast<Map<String, dynamic>>());
      _girisler.sort((a, b) => (b['zaman'] as String).compareTo(a['zaman'] as String));
    } catch (e) {
      _girisHata = 'Girişler okunamadı: $e\n(supabase_giris_kaydi.sql çalıştırıldı mı?)';
    }
    if (mounted) setState(() => _girisYukleniyor = false);
  }

  Future<void> _ozetYukle() async {
    setState(() {
      _ozetYukleniyor = true;
      _ozetHata = null;
    });
    try {
      final bas = DateTime.now().subtract(Duration(days: _ozetGun)).toUtc().toIso8601String();
      final tum = <Map<String, dynamic>>[];
      for (var s = 0; s < 10; s++) {
        final r = await _db
            .from('islem_kaydi')
            .select('zaman, kullanici_ad, tablo, islem')
            .gte('zaman', bas)
            .order('zaman', ascending: false)
            .range(s * 1000, s * 1000 + 999);
        tum.addAll(r.cast<Map<String, dynamic>>());
        if (r.length < 1000) break;
      }
      _ozetKayitlar = tum;
    } catch (e) {
      _ozetHata = 'Özet okunamadı: $e';
    }
    if (mounted) setState(() => _ozetYukleniyor = false);
  }

  Widget _ozetListesi() {
    final kul = <String, Map<String, dynamic>>{};
    for (final k in _ozetKayitlar) {
      var ad = (k['kullanici_ad'] as String? ?? '').trim();
      if (ad.isEmpty) ad = 'Sistem / zamanlanmış';
      final m = kul.putIfAbsent(ad, () => {'ekle': 0, 'degis': 0, 'sil': 0, 'son': k['zaman'], 'tablo': <String, int>{}});
      switch (k['islem']) {
        case 'INSERT':
          m['ekle'] = (m['ekle'] as int) + 1;
          break;
        case 'DELETE':
          m['sil'] = (m['sil'] as int) + 1;
          break;
        default:
          m['degis'] = (m['degis'] as int) + 1;
      }
      final t = m['tablo'] as Map<String, int>;
      final ta = _tabloAd[k['tablo']] ?? '${k['tablo']}';
      t[ta] = (t[ta] ?? 0) + 1;
    }
    final adlar = kul.keys.toList()
      ..sort((a, b) {
        int top(String x) => (kul[x]!['ekle'] as int) + (kul[x]!['degis'] as int) + (kul[x]!['sil'] as int);
        return top(b).compareTo(top(a));
      });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 7, label: Text('Son 7 gün')),
          ButtonSegment(value: 30, label: Text('Son 30 gün')),
        ],
        selected: {_ozetGun},
        onSelectionChanged: (v) {
          _ozetGun = v.first;
          _ozetYukle();
        },
      ),
      const SizedBox(height: 10),
      if (_ozetYukleniyor)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_ozetHata != null)
        Text(_ozetHata!, style: const TextStyle(color: Colors.red))
      else if (adlar.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('Bu aralıkta işlem yok.'))
      else
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(children: [
            for (final ad in adlar)
              ListTile(
                title: Text(
                    '$ad • ${(kul[ad]!['ekle'] as int) + (kul[ad]!['degis'] as int) + (kul[ad]!['sil'] as int)} işlem'),
                subtitle: Text(
                    '${kul[ad]!['ekle']} ekleme, ${kul[ad]!['degis']} değişiklik, ${kul[ad]!['sil']} silme\n'
                    '${(((kul[ad]!['tablo'] as Map<String, int>).entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(4)).map((e) => '${e.key}: ${e.value}').join(', ')}\n'
                    'Son işlem: ${_zaman(kul[ad]!['son'] as String)}'),
                isThreeLine: true,
              ),
          ]),
        ),
    ]);
  }

  Widget _girisListesi() {
    if (_girisYukleniyor) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (_girisHata != null) return Text(_girisHata!, style: const TextStyle(color: Colors.red));
    if (_girisler.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('Giriş kaydı yok.'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text(
          'Başarılı girişler sunucunun kaydından, hatalı denemeler uygulamanın giriş ekranından gelir. '
          'Sunucuya doğrudan yapılan hatalı denemeler burada görünmez.',
          style: TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
      Card(
        elevation: 0,
        color: Colors.white,
        child: Column(children: [
          for (final g in _girisler)
            ListTile(
              dense: true,
              leading: Icon(g['basarili'] == true ? Icons.login : Icons.gpp_bad_outlined,
                  color: g['basarili'] == true ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
              title: Text('${g['basarili'] == true ? 'Giriş yaptı' : 'Hatalı deneme'} • ${g['kullanici']}'),
              subtitle: Text('${_zaman(g['zaman'] as String)}${'${g['ip'] ?? ''}'.isEmpty ? '' : ' • IP ${g['ip']}'}'),
            ),
        ]),
      ),
    ]);
  }

  String _zaman(String iso) {
    final t = DateTime.parse(iso).toLocal();
    String i(int n) => n.toString().padLeft(2, '0');
    return '${i(t.day)}.${i(t.month)}.${t.year} ${i(t.hour)}:${i(t.minute)}';
  }

  Color _renk(String islem) {
    switch (islem) {
      case 'INSERT':
        return const Color(0xFF2E7D32);
      case 'DELETE':
        return const Color(0xFFC62828);
      case 'GERI_YUKLEME':
        return const Color(0xFF6A1B9A);
      default:
        return const Color(0xFF1565C0);
    }
  }

  String _fark(Map<String, dynamic> k) {
    final a = k['ayrinti'];
    if (k['islem'] != 'UPDATE' || a is! Map) return '';
    final p = <String>[];
    a.forEach((alan, v) {
      if (v is Map) p.add('$alan: ${v['eski'] ?? '-'} → ${v['yeni'] ?? '-'}');
    });
    return p.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('İşlem kaydı', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Yenile', onPressed: () => _gorunum == 1 ? _girisYukle() : (_gorunum == 2 ? _ozetYukle() : _yukle(sifirla: true)), icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: Text('Veri işlemleri')),
          ButtonSegment(value: 1, label: Text('Girişler')),
          ButtonSegment(value: 2, label: Text('Kullanıcı özeti')),
        ],
        selected: {_gorunum},
        onSelectionChanged: (v) {
          setState(() => _gorunum = v.first);
          if (_gorunum == 1 && _girisler.isEmpty) _girisYukle();
          if (_gorunum == 2) _ozetYukle();
        },
      ),
      const SizedBox(height: 10),
      if (_gorunum == 1) _girisListesi(),
      if (_gorunum == 2) _ozetListesi(),
      if (_gorunum == 0) ...[
      Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<int?>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Firma', isDense: true, border: OutlineInputBorder()),
            initialValue: _firma,
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Tümü')),
              for (final e in _firmalar.entries) DropdownMenuItem<int?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              _firma = v;
              _yukle(sifirla: true);
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Alan', isDense: true, border: OutlineInputBorder()),
            initialValue: _tablo,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Tümü')),
              for (final e in _tabloAd.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              _tablo = v;
              _yukle(sifirla: true);
            },
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'İşlem', isDense: true, border: OutlineInputBorder()),
            initialValue: _islem,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Tümü')),
              for (final e in _islemAd.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              _islem = v;
              _yukle(sifirla: true);
            },
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (_hata != null) Text(_hata!, style: const TextStyle(color: Colors.red)),
      if (_yukleniyor && _kayitlar.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_kayitlar.isEmpty && _hata == null)
        const Padding(padding: EdgeInsets.all(12), child: Text('Kayıt yok. Kayıtlar, SQL çalıştırıldıktan sonraki işlemlerden başlar.'))
      else
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(children: [
            for (final k in _kayitlar)
              ListTile(
                dense: true,
                isThreeLine: _fark(k).isNotEmpty,
                leading: Icon(Icons.circle, size: 12, color: _renk(k['islem'] as String)),
                title: Text(
                    '${_islemAd[k['islem']] ?? k['islem']} • ${_tabloAd[k['tablo']] ?? k['tablo']}'
                    '${(k['ozet'] as String? ?? '').isEmpty ? '' : ' • ${k['ozet']}'}'),
                subtitle: Text(
                    '${_zaman(k['zaman'] as String)} • ${k['kullanici_ad']}'
                    '${k['firma_id'] == null ? '' : ' • ${_firmalar[(k['firma_id'] as num).toInt()] ?? 'Silinmiş firma'}'}'
                    '${_fark(k).isEmpty ? '' : '\n${_fark(k)}'}'),
              ),
          ]),
        ),
      if (_dahaVar)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton(onPressed: _yukleniyor ? null : () => _yukle(), child: const Text('Daha fazla göster')),
        ),
      ],
    ]);
  }
}
