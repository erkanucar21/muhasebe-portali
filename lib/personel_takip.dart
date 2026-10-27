import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firmalar.dart';
import 'izin_formu.dart';
import 'cikis_belgeleri.dart';
import 'meslek_kodlari.dart';
import 'secili_firma.dart';
import 'maas_alani.dart';
import 'tarih_alani.dart';
import 'tatiller.dart';
import 'dogrulama.dart';

enum Durum {
  izin('İzin', Color(0xFF1E6FB8)),
  gelmedi('Gelmedi', Color(0xFFC0392B)),
  rapor('Raporlu', Color(0xFFD9822B));

  final String ad;
  final Color renk;
  const Durum(this.ad, this.renk);
}

class Personel {
  final int id;
  final int firmaId; // personelin bağlı olduğu firma
  String ad;
  String tc;
  String meslek; // meslek kodu ve adı
  double ucret; // aylık maaş (TL)
  String sgkSicil; // personelin SGK sicil no (bordroda görünür)
  String maasTuru; // 'net' veya 'brut': maaş alanındaki rakamın türü (bordro için)
  bool asgari; // asgari ücretli: maaş her ay/yıl o dönemin asgari ücretine göre alınır
  DateTime giris; // işe giriş tarihi
  DateTime? cikis; // işten çıkış tarihi (boşsa hâlâ çalışıyor)
  Personel(this.id, this.ad, this.giris,
      {required this.firmaId, this.cikis, this.tc = '', this.meslek = '', this.ucret = 0, this.asgari = false, this.maasTuru = 'net', this.sgkSicil = ''});

  factory Personel.fromMap(Map<String, dynamic> m) => Personel(
        m['id'] as int,
        m['ad'] as String,
        DateTime.parse(m['giris'] as String),
        firmaId: m['firma_id'] as int,
        cikis: m['cikis'] == null ? null : DateTime.parse(m['cikis'] as String),
        tc: (m['tc'] ?? '') as String,
        meslek: (m['meslek'] ?? '') as String,
        ucret: ((m['ucret'] ?? 0) as num).toDouble(),
        asgari: (m['asgari_ucretli'] ?? false) as bool,
        maasTuru: (m['maas_turu'] ?? 'net') as String,
        sgkSicil: (m['sgk_sicil_no'] ?? '') as String,
      );
}

String _sqlTarih(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Aylık net asgari ücret (TL). 2022 ve 2023'te yıl içinde iki kez değişti.
/// Kaynak: Çalışma Bakanlığı / Asgari Ücret Tespit Komisyonu duyuruları. Tanımsız yıl için null.
double? _asgariUcret(int yil, int ay) => switch (yil) {
      2022 => ay < 7 ? 4253.40 : 5500.35,
      2023 => ay < 7 ? 8506.80 : 11402.32,
      2024 => 17002.12,
      2025 => 22104.67,
      2026 => 28075.50,
      _ => null,
    };

/// 28075.5 -> "28.075,50" (TL eki olmadan, forma yazmak için)
String _paraSade(double v) {
  final p = v.toStringAsFixed(2).split('.');
  final bin = p[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '$bin,${p[1]}';
}

String _paraYaz(double v) {
  final p = v.toStringAsFixed(2).split('.');
  final bin = p[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '$bin,${p[1]} TL';
}

String _tarihYaz(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

DateTime? _tarihCoz(String s) {
  final p = s.trim().split('.');
  if (p.length != 3) return null;
  final g = int.tryParse(p[0]), a = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (g == null || a == null || y == null || y < 2000) return null;
  final d = DateTime(y, a, g);
  return (d.day == g && d.month == a) ? d : null;
}

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

int _ayNo(DateTime d) => d.year * 12 + d.month;

DateTime _yilDonumu(DateTime giris, int n) => DateTime(giris.year + n, giris.month, giris.day);

/// Verilen tarihi içine alan hizmet yılı: işe giriş yıl dönümünden, bir sonraki yıl dönümünün bir gün öncesine kadar.
/// Üçüncü değer, o hizmet yılı başlarken tamamlanmış hizmet yılı sayısıdır.
(DateTime, DateTime, int) _hizmetYiliAraligi(DateTime giris, DateTime ref) {
  final g = DateTime(giris.year, giris.month, giris.day);
  var n = ref.year - g.year;
  if (n < 0) n = 0;
  if (n > 0 && _yilDonumu(g, n).isAfter(ref)) n--;
  final sonraki = _yilDonumu(g, n + 1);
  return (_yilDonumu(g, n), DateTime(sonraki.year, sonraki.month, sonraki.day - 1), n);
}

/// İş Kanunu m.53: tamamlanan her hizmet yılı için yıllık ücretli izin hakkı.
/// 1-5 yıl (5 dahil) 14 gün, 5 yıldan fazla ve 15 yıldan az 20 gün, 15 yıl ve fazlası 26 gün.
int _yillikHak(int tamamlananYil) {
  if (tamamlananYil < 1) return 0;
  if (tamamlananYil <= 5) return 14;
  if (tamamlananYil < 15) return 20;
  return 26;
}

class IzinOzeti {
  final DateTime bas, son;
  final int hizmetYili; // bu hizmet yılı başlarken tamamlanmış yıl sayısı
  final int yeniHak, devreden, kullanilan;
  const IzinOzeti(this.bas, this.son, this.hizmetYili, this.yeniHak, this.devreden, this.kullanilan);
  int get toplamHak => yeniHak + devreden;
  int get kalan => toplamHak - kullanilan;
}

/// firmaId doluysa (firma kullanıcısı) yalnızca o firma görünür; boşsa (yönetici) firma seçilebilir.
class PersonelTakipSayfasi extends StatefulWidget {
  final int? firmaId;
  const PersonelTakipSayfasi({super.key, this.firmaId});
  @override
  State<PersonelTakipSayfasi> createState() => _PersonelTakipSayfasiState();
}

// Başka bölüme gidip dönünce kaldığın firmadan ve aydan devam etmek için (uygulama açık kaldığı sürece).
int? _sonPersonelFirmaId;
double? _sonMaas; // en son kaydedilen maaş (Enter ile tekrar yazılır)
int? _sonPersonelAy;

class _PersonelTakipSayfasiState extends State<PersonelTakipSayfasi> {
  late int _ay;
  final List<Personel> _personel = [];
  final Map<String, Durum> _kayit = {};
  bool _yukleniyor = true;
  final Map<int, IzinOzeti> _izinOzet = {}; // personel no -> hizmet yılı izin özeti
  int? _firmaId;
  Personel? _secPersonel; // gün seçimi yapılan personel
  final Set<int> _secGunler = {}; // seçili günler

  SupabaseClient get _db => Supabase.instance.client;
  bool get _yazabilir => widget.firmaId == null; // firma kullanıcısı yalnızca görür

  @override
  void initState() {
    super.initState();
    _ay = _sonPersonelAy ?? _ayNo(DateTime.now());
    final liste = FirmaDeposu.ornek.liste;
    final sonVar = _sonPersonelFirmaId != null && liste.any((f) => f.id == _sonPersonelFirmaId);
    _firmaId = widget.firmaId ?? seciliFirmaId.value ?? (sonVar ? _sonPersonelFirmaId : (liste.isEmpty ? null : liste.first.id));
    seciliFirmaId.addListener(_firmaDegisti);
    _baslat();
  }

  @override
  void dispose() {
    seciliFirmaId.removeListener(_firmaDegisti);
    super.dispose();
  }

  /// Üst çubuktan başka firma seçilince yeniden yükler.
  void _firmaDegisti() {
    if (widget.firmaId != null) return;
    final v = seciliFirmaId.value;
    if (v == _firmaId) return;
    setState(() {
      _firmaId = v;
      _secimiTemizle();
    });
    _yukle();
  }

  /// Firma listesi henüz yüklenmediyse (uygulama doğrudan bu bölümle açıldıysa) önce yükler.
  Future<void> _baslat() async {
    if (widget.firmaId == null && _firmaId == null) {
      try {
        await FirmaDeposu.ornek.yukle();
      } catch (_) {}
      final liste = FirmaDeposu.ornek.liste;
      if (mounted && liste.isNotEmpty) {
        final sonVar = _sonPersonelFirmaId != null && liste.any((f) => f.id == _sonPersonelFirmaId);
        _firmaId = sonVar ? _sonPersonelFirmaId : liste.first.id;
      }
    }
    if (mounted) await _yukle();
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Seçili firmanın personelini ve görünen ayın izin kayıtlarını veritabanından alır.
  Future<void> _yukle() async {
    final firma = _firmaId;
    if (widget.firmaId == null) {
      _sonPersonelFirmaId = firma;
      _sonPersonelAy = _ay;
    }
    if (firma == null) {
      setState(() {
        _personel.clear();
        _kayit.clear();
        _yukleniyor = false;
      });
      return;
    }
    setState(() => _yukleniyor = true);
    try {
      final rows = await _db.from('personel').select().eq('firma_id', firma).order('ad');
      _personel
        ..clear()
        ..addAll([for (final m in rows) Personel.fromMap(m)]);
      await _kayitlariYukle(guncelle: false);
    } catch (e) {
      if (mounted) _mesaj('Personel yüklenemedi: $e');
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _kayitlariYukle({bool guncelle = true}) async {
    _kayit.clear();
    final ids = [for (final p in _personel) p.id];
    if (ids.isNotEmpty) {
      final rows = await _db
          .from('izin_kayitlari')
          .select()
          .inFilter('personel_id', ids)
          .gte('tarih', _sqlTarih(DateTime(_yil, _ayNum, 1)))
          .lte('tarih', _sqlTarih(DateTime(_yil, _ayNum, _gunSayisi)));
      for (final m in rows) {
        final t = DateTime.parse(m['tarih'] as String);
        final d = Durum.values.where((x) => x.name == m['durum']).firstOrNull;
        if (d != null) _kayit['${m['personel_id']}-$_ay-${t.day}'] = d;
      }
    }
    await _yillikIzinleriYukle();
    if (guncelle && mounted) setState(() {});
  }

  /// Her personelin, görünen aya denk gelen hizmet yılı için izin hakkını, devreden günleri
  /// ve kullanılan izin günlerini hesaplar. Kullanılmayan izin sonraki yılın hakkına eklenir.
  Future<void> _yillikIzinleriYukle() async {
    _izinOzet.clear();
    if (_personel.isEmpty) return;
    final bugun = DateTime.now();
    final bugunTarih = DateTime(bugun.year, bugun.month, bugun.day);
    final ref = (_ay == _ayNo(bugun)) ? bugunTarih : DateTime(_yil, _ayNum, _gunSayisi);
    final pencere = <int, (DateTime, DateTime, int)>{};
    DateTime? enGec;
    for (final p in _personel) {
      final g = DateTime(p.giris.year, p.giris.month, p.giris.day);
      final a = _hizmetYiliAraligi(p.giris, ref.isBefore(g) ? g : ref);
      pencere[p.id] = a;
      if (enGec == null || a.$2.isAfter(enGec)) enGec = a.$2;
    }
    final tum = <Map<String, dynamic>>[];
    for (var bas = 0;; bas += 1000) {
      final parca = await _db
          .from('izin_kayitlari')
          .select('personel_id, tarih')
          .eq('durum', 'izin')
          .inFilter('personel_id', [for (final p in _personel) p.id])
          .lte('tarih', _sqlTarih(enGec!))
          .order('tarih')
          .order('personel_id')
          .range(bas, bas + 999);
      tum.addAll(parca);
      if (parca.length < 1000) break;
    }
    final once = <int, int>{};
    final icinde = <int, int>{};
    for (final m in tum) {
      final id = m['personel_id'] as int;
      final t = DateTime.parse(m['tarih'] as String);
      if (izneSayilmaz(t)) continue;
      final a = pencere[id];
      if (a == null) continue;
      if (t.isBefore(a.$1)) {
        once[id] = (once[id] ?? 0) + 1;
      } else if (!t.isAfter(a.$2)) {
        icinde[id] = (icinde[id] ?? 0) + 1;
      }
    }
    pencere.forEach((id, a) {
      var onceki = 0;
      for (var j = 1; j < a.$3; j++) {
        onceki += _yillikHak(j);
      }
      _izinOzet[id] = IzinOzeti(a.$1, a.$2, a.$3, _yillikHak(a.$3), onceki - (once[id] ?? 0), icinde[id] ?? 0);
    });
  }

  Future<void> _ayDegistir(int fark) async {
    setState(() {
      _ay += fark;
      if (widget.firmaId == null) _sonPersonelAy = _ay;
      _secimiTemizle();
    });
    try {
      await _kayitlariYukle();
    } catch (e) {
      if (mounted) _mesaj('Kayıtlar yüklenemedi: $e');
    }
  }

  int get _yil => (_ay - 1) ~/ 12;
  int get _ayNum => (_ay - 1) % 12 + 1;
  int get _gunSayisi => DateTime(_yil, _ayNum + 1, 0).day;
  String _anahtar(Personel p, int gun) => '${p.id}-$_ay-$gun';

  /// Seçili ay için personelin maaşı: asgari ücretliyse o dönemin asgari ücreti, değilse kayıtlı maaş
  double _maas(Personel p) => p.asgari ? (_asgariUcret(_yil, _ayNum) ?? p.ucret) : p.ucret;

  List<Personel> get _firmaPersonel => _personel.where((p) => p.firmaId == _firmaId).toList();

  List<Personel> get _gorunen =>
      (_firmaPersonel.where((p) => _ayNo(p.giris) <= _ay && (p.cikis == null || _ayNo(p.cikis!) >= _ay)).toList())
        ..sort((a, b) => trKarsilastir(a.ad, b.ad));

  Future<void> _personelForm({Personel? mevcut, Personel? kopya}) async {
    if (!_yazabilir) return;
    if (mevcut == null && _firmaId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Önce Firmalar bölümünden bir firma ekle.')));
      return;
    }
    // kopya: aynı kişinin yeniden işe girişi. Kimlik, meslek ve maaş bilgisi gelir; giriş tarihi boş başlar.
    final kaynak = mevcut ?? kopya;
    final ad = TextEditingController(text: kaynak?.ad ?? '');
    final tc = TextEditingController(text: kaynak?.tc ?? '');
    final meslek = TextEditingController(text: kaynak?.meslek ?? '');
    final sgkSicil = TextEditingController(text: kaynak?.sgkSicil ?? '');
    final ucret = TextEditingController(
        text: (kaynak == null || kaynak.ucret == 0) ? '' : _paraSade(kaynak.ucret));
    // Öneri: bu oturumda en son kaydedilen maaş, yoksa firmadaki en son personelin maaşı
    final oneriMaas = _sonMaas ??
        (_firmaPersonel.where((p) => p.ucret > 0).isEmpty ? null : _firmaPersonel.where((p) => p.ucret > 0).last.ucret);
    final oneri = oneriMaas == null ? null : _paraSade(oneriMaas);
    final giris = TextEditingController(text: _tarihYaz(mevcut?.giris ?? DateTime(_yil, _ayNum, 1)));
    final cikis = TextEditingController(text: mevcut?.cikis == null ? '' : _tarihYaz(mevcut!.cikis!));
    final asgariDeger = _asgariUcret(_yil, _ayNum);
    // Kayıtlı maaş o yılın asgari ücretine eşitse kutu işaretli açılır
    var asgari = kaynak != null && (kaynak.asgari || (asgariDeger != null && (kaynak.ucret - asgariDeger).abs() < 0.01));
    if (asgari && asgariDeger != null) ucret.text = _paraSade(asgariDeger);
    var maasTuru = kaynak?.maasTuru ?? 'net';
    String? hata;
    var mesgul = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(mevcut != null ? 'Personel bilgileri' : (kopya != null ? 'Personeli kopyala (yeniden işe giriş)' : 'Personel ekle')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: ad,
                autofocus: mevcut == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Ad soyad'),
              ),
              TextField(
                controller: tc,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: const InputDecoration(labelText: 'TC kimlik no', counterText: ''),
              ),
              MeslekAlani(controller: meslek),
              TextField(controller: sgkSicil, decoration: const InputDecoration(labelText: 'SGK sicil no (isteğe bağlı)')),
              MaasAlani(controller: ucret, oneri: oneri, kilitli: asgari),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Row(children: [
                  const Text('Girilen maaş:'),
                  const SizedBox(width: 10),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'net', label: Text('Net')),
                      ButtonSegment(value: 'brut', label: Text('Brüt')),
                    ],
                    selected: {maasTuru},
                    onSelectionChanged: asgari ? null : (v) => setD(() => maasTuru = v.first),
                  ),
                ]),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: asgari,
                title: Text(asgariDeger == null
                    ? 'Asgari ücretli ($_yil için asgari ücret tanımlı değil)'
                    : 'Asgari ücretli ($_yil: ${_paraSade(asgariDeger)} TL)'),
                onChanged: asgariDeger == null
                    ? null
                    : (v) => setD(() {
                          asgari = v ?? false;
                          if (asgari) ucret.text = _paraSade(asgariDeger);
                        }),
              ),
              TarihAlani(controller: giris, etiket: 'İşe giriş tarihi'),
              TarihAlani(controller: cikis, etiket: 'İşten çıkış tarihi', ipucu: 'çalışıyorsa boş bırak'),
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(hata!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            if (mevcut != null)
              TextButton(
                onPressed: mesgul
                    ? null
                    : () async {
                        final onay = await showDialog<bool>(
                          context: c,
                          builder: (d) => AlertDialog(
                            title: Text('${mevcut.ad} silinsin mi?'),
                            content: const Text('Personel tüm aylardan ve kayıtlarıyla birlikte kalkar.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sil')),
                            ],
                          ),
                        );
                        if (onay != true) return;
                        try {
                          await _db.from('personel').delete().eq('id', mevcut.id);
                          _secimiTemizle();
                          await _yukle();
                          if (c.mounted) Navigator.pop(c);
                        } catch (e) {
                          setD(() => hata = 'Silinemedi: $e');
                        }
                      },
                child: Text('Sil', style: TextStyle(color: Colors.red.shade700)),
              ),
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: mesgul
                  ? null
                  : () async {
                      final g = _tarihCoz(giris.text);
                      final cMetin = cikis.text.trim();
                      final cTarih = cMetin.isEmpty ? null : _tarihCoz(cMetin);
                      final t = tc.text.trim();
                      final u = ucret.text.trim().isEmpty
                          ? 0.0
                          : double.tryParse(ucret.text.trim().replaceAll('.', '').replaceAll(',', '.'));
                      String? h;
                      if (ad.text.trim().isEmpty) {
                        h = 'Ad soyad boş olamaz';
                      } else if (t.isNotEmpty && t.length != 11) {
                        h = 'TC kimlik no 11 haneli olmalı';
                      } else if (t.isNotEmpty && !tcGecerli(t)) {
                        h = 'TC kimlik no geçerli değil (kontrol hanesi tutmuyor), tekrar kontrol et';
                      } else if (u == null) {
                        h = 'Maaş sayı olmalı, örnek: 28075,50';
                      } else if (g == null) {
                        h = 'İşe giriş tarihi geçersiz (gg.aa.yyyy)';
                      } else if (cMetin.isNotEmpty && cTarih == null) {
                        h = 'Çıkış tarihi geçersiz (gg.aa.yyyy)';
                      } else if (cTarih != null && cTarih.isBefore(g)) {
                        h = 'Çıkış tarihi giriş tarihinden önce olamaz';
                      }
                      if (h != null) {
                        setD(() => hata = h);
                        return;
                      }
                      setD(() {
                        hata = null;
                        mesgul = true;
                      });
                      try {
                        final kayit = {
                          'ad': ad.text.trim(),
                          'tc': t,
                          'meslek': meslek.text.trim(),
                          'ucret': u,
                          'asgari_ucretli': asgari,
                          'maas_turu': maasTuru,
                          'sgk_sicil_no': sgkSicil.text.trim(),
                          'giris': _sqlTarih(g!),
                          'cikis': cTarih == null ? null : _sqlTarih(cTarih),
                        };
                        if (u != null && u > 0) _sonMaas = u;
                        if (mevcut == null) {
                          await _db.from('personel').insert({...kayit, 'firma_id': _firmaId});
                          _ay = _ayNo(g);
                          _sonPersonelAy = _ay;
                        } else {
                          await _db.from('personel').update(kayit).eq('id', mevcut.id);
                          try {
                            var sil = _db.from('bordro_tazminat').delete().eq('personel_id', mevcut.id);
                            if (cTarih != null) sil = sil.or('yil.neq.${cTarih.year},ay.neq.${cTarih.month}');
                            await sil;
                          } catch (_) {}
                        }
                        _secimiTemizle();
                        await _yukle();
                        if (c.mounted) Navigator.pop(c);
                      } catch (e) {
                        setD(() {
                          hata = 'Kaydedilemedi: $e';
                          mesgul = false;
                        });
                      }
                    },
              child: Text(mesgul ? 'Kaydediliyor...' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  /// Güne dokununca günü seçer / seçimden çıkarır (aynı anda tek personel).
  void _gunSec(Personel p, int gun) {
    if (!_yazabilir) return;
    setState(() {
      if (_secPersonel != p) {
        _secGunler.clear();
        _secPersonel = p;
      }
      if (!_secGunler.remove(gun)) _secGunler.add(gun);
      if (_secGunler.isEmpty) _secPersonel = null;
    });
  }

  void _secimiTemizle() {
    _secGunler.clear();
    _secPersonel = null;
  }

  /// Seçili günlere durumu uygular. durum == null ise kayıtları siler.
  Future<void> _secimeUygula(Durum? durum) async {
    final p = _secPersonel;
    if (p == null || !_yazabilir) return;
    var gunler = _secGunler.toList()..sort();
    var atlanan = 0;
    if (durum == Durum.izin) {
      final sayilan = [for (final g in gunler) if (!izneSayilmaz(DateTime(_yil, _ayNum, g))) g];
      atlanan = gunler.length - sayilan.length;
      gunler = sayilan;
      if (gunler.isEmpty) {
        _mesaj('Seçilen günler Pazar veya resmî tatil. Yıllık izne sayılmadığı için izin yazılmadı.');
        return;
      }
    }
    final tarihler = [for (final g in gunler) _sqlTarih(DateTime(_yil, _ayNum, g))];
    try {
      if (durum == null) {
        await _db.from('izin_kayitlari').delete().eq('personel_id', p.id).inFilter('tarih', tarihler);
      } else {
        await _db.from('izin_kayitlari').upsert(
          [for (final t in tarihler) {'personel_id': p.id, 'tarih': t, 'durum': durum.name}],
          onConflict: 'personel_id,tarih',
        );
      }
      for (final g in gunler) {
        if (durum == null) {
          _kayit.remove(_anahtar(p, g));
        } else {
          _kayit[_anahtar(p, g)] = durum;
        }
      }
      await _yillikIzinleriYukle();
      setState(_secimiTemizle);
      if (atlanan > 0) _mesaj('$atlanan gün (Pazar / resmî tatil) yıllık izne sayılmadığı için atlandı.');
    } catch (e) {
      _mesaj('Kaydedilemedi: $e');
    }
  }

  Widget _secimCubugu() {
    final p = _secPersonel!;
    final gunler = _secGunler.toList()..sort();
    final metin = gunler.length <= 6 ? gunler.join(', ') : '${gunler.length} gün';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Material(
        elevation: 6,
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text('${p.ad}: ${_aylar[_ayNum - 1]} $metin seçili',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Seçimi iptal et',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_secimiTemizle),
              ),
            ]),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final d in Durum.values)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: d.renk),
                  onPressed: () => _secimeUygula(d),
                  child: Text(d.ad),
                ),
              OutlinedButton(onPressed: () => _secimeUygula(null), child: const Text('Kaydı sil')),
            ]),
          ]),
        ),
      ),
    );
  }

  /// Ay içindeki ardışık izin günlerini (başlangıç, bitiş) çiftleri olarak verir.
  List<(int, int)> _izinGruplari(Personel p) => _durumGruplari(p, Durum.izin);

  List<(int, int)> _durumGruplari(Personel p, Durum durum) {
    final liste = <(int, int)>[];
    int? bas;
    int? son;
    for (var g = 1; g <= _gunSayisi; g++) {
      if (_kayit[_anahtar(p, g)] == durum) {
        bas ??= g;
        son = g;
      } else if (bas != null) {
        // yıllık izinde Pazar ve resmî tatil günleri izni bölmez
        if (durum == Durum.izin && izneSayilmaz(DateTime(_yil, _ayNum, g))) continue;
        liste.add((bas, son!));
        bas = null;
      }
    }
    if (bas != null) liste.add((bas, son!));
    return liste;
  }

  /// Yıllık izinde Pazar ve resmî tatil günleri sayılmaz; ücretsiz izinde takvim günü sayılır.
  int _formGun(int bas, int son, bool ucretsiz) =>
      ucretsiz ? son - bas + 1 : izinGunSayisi(DateTime(_yil, _ayNum, bas), DateTime(_yil, _ayNum, son));

  String _aralikYaz(int bas, int son) => '$bas${bas == son ? '' : '-$son'} ${_aylar[_ayNum - 1]}';

  void _formSec(Personel p, int bas, int son, {bool ucretsiz = false}) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${p.ad}\n${_aralikYaz(bas, son)} $_yil  (${_formGun(bas, son, ucretsiz)} günlük ${ucretsiz ? 'ücretsiz izin dilekçesi' : 'yıllık izin formu'})',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          for (final (tur, baslik, ikon) in [
            ('pdf', 'PDF olarak indir', Icons.picture_as_pdf_outlined),
            ('docx', 'Word olarak indir', Icons.article_outlined),
            ('xlsx', 'Excel olarak indir', Icons.table_chart_outlined),
          ])
            ListTile(
              leading: Icon(ikon),
              title: Text(baslik),
              onTap: () {
                Navigator.pop(c);
                _formIndir(p, bas, son, tur, ucretsiz: ucretsiz);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _formIndir(Personel p, int bas, int son, String tur, {bool ucretsiz = false}) async {
    final parcalar = p.ad.trim().split(RegExp(r'\s+'));
    final soyad = parcalar.length > 1 ? parcalar.last : '';
    final ad = parcalar.length > 1 ? parcalar.sublist(0, parcalar.length - 1).join(' ') : p.ad;
    final bolum = p.meslek.contains(' - ') ? p.meslek.substring(p.meslek.indexOf(' - ') + 3) : p.meslek;
    final form = IzinFormu(
      ad: ad,
      soyad: soyad,
      tc: p.tc,
      bolum: bolum,
      giris: p.giris,
      baslangic: DateTime(_yil, _ayNum, bas),
      bitis: DateTime(_yil, _ayNum, son),
      gun: _formGun(bas, son, ucretsiz),
    );
    final mesaj = ScaffoldMessenger.of(context);
    try {
      if (ucretsiz) {
        await ucretsizIzinIndir(UcretsizIzinDilekcesi.formdan(form, FirmaDeposu.ornek.bul(p.firmaId)?.unvan ?? ''), tur);
      } else {
        await izinFormuIndir(form, tur);
      }
      mesaj.showSnackBar(const SnackBar(content: Text('İzin formu indirildi.')));
    } catch (e) {
      mesaj.showSnackBar(SnackBar(content: Text('Form oluşturulamadı: $e')));
    }
  }

  Map<Durum, int> _say(Personel p) {
    final s = {for (final d in Durum.values) d: 0};
    for (var g = 1; g <= _gunSayisi; g++) {
      final d = _kayit[_anahtar(p, g)];
      if (d == Durum.izin && izneSayilmaz(DateTime(_yil, _ayNum, g))) continue;
      if (d != null) s[d] = s[d]! + 1;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme.primary;
    final liste = _gorunen;
    final toplam = {for (final d in Durum.values) d: 0};
    for (final p in liste) {
      _say(p).forEach((d, n) => toplam[d] = toplam[d]! + n);
    }

    final takip = Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          if (_yukleniyor) const LinearProgressIndicator(),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: () => _ayDegistir(-1), icon: const Icon(Icons.chevron_left)),
            Text('${_aylar[_ayNum - 1]} $_yil',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: renk)),
            IconButton(onPressed: () => _ayDegistir(1), icon: const Icon(Icons.chevron_right)),
          ]),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _ozet('Personel', '${liste.length}', renk),
              for (final d in Durum.values) _ozet('${d.ad} (gün)', '${toplam[d]}', d.renk, onTap: () => _durumAylari(d)),
            ]),
          ),
          if (_yazabilir)
            const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Günlere dokunarak seç, sonra İzin / Gelmedi / Raporlu butonuna bas.',
                style: TextStyle(fontSize: 12, color: Colors.black87)),
          ),
          Expanded(
            child: liste.isEmpty
                ? const Center(child: Text('Bu ay için personel yok. "Personel ekle" ile başla.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 88),
                    itemCount: liste.length,
                    itemBuilder: (c, i) => _kart(liste[i]),
                  ),
          ),
          if (_secGunler.isNotEmpty) _secimCubugu(),
        ]),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: (_secGunler.isNotEmpty || !_yazabilir)
            ? null
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                FloatingActionButton.extended(
                  heroTag: 'eski-personel',
                  onPressed: _eskiPersoneldenEkle,
                  icon: const Icon(Icons.history),
                  label: const Text('Eski personelden ekle'),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'personel-ekle',
                  onPressed: () => _personelForm(),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Personel ekle'),
                ),
              ]),
        body: Column(children: [
          _firmaSecici(),
          const TabBar(tabs: [Tab(text: 'Aylık takip'), Tab(text: 'Personel listesi')]),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [takip, _listeSekmesi()],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _firmaSecici() {
    if (widget.firmaId == null) return const SizedBox.shrink(); // yönetici firmayı üst çubuktan seçer
    final firmalar = FirmaDeposu.ornek.liste;
    final sabit = widget.firmaId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        const Icon(Icons.business_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: sabit
              ? Text(FirmaDeposu.ornek.bul(widget.firmaId!)?.unvan ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600))
              : DropdownButton<int>(
                  isExpanded: true,
                  value: firmalar.any((f) => f.id == _firmaId) ? _firmaId : null,
                  hint: const Text('Firma seç'),
                  items: [for (final f in firmalar) DropdownMenuItem(value: f.id, child: Text(f.unvan))],
                  onChanged: (v) {
                    setState(() {
                      _firmaId = v;
                      _secimiTemizle();
                    });
                    _yukle();
                  },
                ),
        ),
      ]),
    );
  }

  Widget _listeSekmesi() {
    final firmaListe = (_firmaPersonel
        .where((p) => p.giris.year <= _yil && (p.cikis == null || p.cikis!.year >= _yil))
        .toList())
      ..sort((a, b) => trKarsilastir(a.ad, b.ad));
    final ayrilan = firmaListe.where((p) => p.cikis != null).length;
    final calisan = firmaListe.length - ayrilan;
    const baslik = TextStyle(fontWeight: FontWeight.w700);
    const kirmizi = Color(0xFFB3261E);
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: () => _ayDegistir(-12), icon: const Icon(Icons.chevron_left)),
        Text('$_yil yılı personel listesi',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        IconButton(onPressed: () => _ayDegistir(12), icon: const Icon(Icons.chevron_right)),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Çalışan: $calisan     Ayrılan: $ayrilan     ${_yazabilir ? '(düzenlemek için satıra dokun)' : ''}',
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ),
      ),
      Expanded(
        child: firmaListe.isEmpty
            ? const Center(child: Text('Henüz personel yok. "Personel ekle" ile başla.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 88),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('Ad Soyad', style: baslik)),
                      DataColumn(label: Text('TC Kimlik No', style: baslik)),
                      DataColumn(label: Text('Meslek Kodu ve Adı', style: baslik)),
                      DataColumn(label: Text('Maaş', style: baslik)),
                      DataColumn(label: Text('İşe Giriş', style: baslik)),
                      DataColumn(label: Text('İşten Çıkış', style: baslik)),
                      DataColumn(label: Text('İzin (hak / kullanılan / kalan)', style: baslik)),
                    ],
                    rows: [
                      for (final p in firmaListe)
                        DataRow(
                          color: WidgetStateProperty.all(p.cikis != null ? const Color(0xFFFCE4E4) : Colors.white),
                          onSelectChanged: _yazabilir ? (secildi) => _personelForm(mevcut: p) : null,
                          cells: [
                            DataCell(Text(p.ad)),
                            DataCell(Text(p.tc.isEmpty ? '-' : p.tc)),
                            DataCell(Text(p.meslek.isEmpty ? '-' : p.meslek)),
                            DataCell(Text(_maas(p) == 0 ? '-' : _paraYaz(_maas(p)))),
                            DataCell(Text(_tarihYaz(p.giris))),
                            DataCell(Text(
                              p.cikis == null ? '-' : _tarihYaz(p.cikis!),
                              style: p.cikis == null ? null : const TextStyle(color: kirmizi, fontWeight: FontWeight.w700),
                            )),
                            DataCell(Text(_izinOzet[p.id] == null
                                ? '-'
                                : '${_izinOzet[p.id]!.toplamHak} / ${_izinOzet[p.id]!.kullanilan} / ${_izinOzet[p.id]!.kalan}')),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _izinOzetiSatiri(IzinOzeti o) {
    final hak = o.hizmetYili < 1
        ? 'Hak: henüz doğmadı (1 yıl dolunca ${_yillikHak(1)} gün hak edilir)'
        : 'Hak: ${o.toplamHak} gün (yeni ${o.yeniHak}${o.devreden == 0 ? '' : ' ${o.devreden > 0 ? '+ devreden' : '- fazla kullanılan'} ${o.devreden.abs()}'})';
    final kalan = o.kalan;
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hizmet yılı: ${_tarihYaz(o.bas)} - ${_tarihYaz(o.son)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E6FB8))),
        Text('$hak   Kullanılan: ${o.kullanilan}   Kalan: $kalan',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kalan < 0 ? const Color(0xFFB3261E) : const Color(0xFF2E7D32))),
      ]),
    );
  }

  /// Gelmediği günler maaştan düşer: günlük ücret = maaş / 30.
  (int, double, double) _maasHesabi(Personel p) {
    final gun = _say(p)[Durum.gelmedi] ?? 0;
    final m = _maas(p);
    final kesinti = m > 0 ? (m / 30 * gun) : 0.0;
    return (gun, kesinti, m - kesinti);
  }

  Widget _kart(Personel p) {
    final sayi = _say(p);
    final ayrildi = p.cikis != null;
    return Card(
      elevation: 0,
      color: ayrildi ? const Color(0xFFFCE4E4) : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p.ad, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            if (_yazabilir)
              personelBelgeMenusu(context, p),
            if (_yazabilir)
              IconButton(
                tooltip: 'Kopyala (aynı kişiyi yeniden işe al)',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () => _personelForm(kopya: p),
              ),
            if (_yazabilir)
              IconButton(
                tooltip: 'Düzenle',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _personelForm(mevcut: p),
              ),
          ]),
          Wrap(spacing: 16, children: [
            if (p.tc.isNotEmpty) Text('TC: ${p.tc}', style: const TextStyle(fontSize: 13)),
            if (p.meslek.isNotEmpty) Text(p.meslek, style: const TextStyle(fontSize: 13)),
            if (_maas(p) > 0) Text('Maaş: ${_paraYaz(_maas(p))}', style: const TextStyle(fontSize: 13)),
            Text('İşe giriş: ${_tarihYaz(p.giris)}', style: const TextStyle(fontSize: 13)),
            Text('Çıkış: ${ayrildi ? _tarihYaz(p.cikis!) : '-'}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: ayrildi ? FontWeight.w700 : FontWeight.w400,
                    color: ayrildi ? const Color(0xFFB3261E) : null)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, children: [
            for (final d in Durum.values)
              Text('${d.ad}: ${sayi[d]}',
                  style: TextStyle(fontSize: 13, color: d.renk, fontWeight: FontWeight.w600)),
          ]),
          if (_maas(p) > 0 && _maasHesabi(p).$1 > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Text(
                'Gelmedi kesintisi: -${_paraYaz(_maasHesabi(p).$2)} (${_maasHesabi(p).$1} gün x ${_paraYaz(_maas(p) / 30)})   '
                'Ödenecek maaş: ${_paraYaz(_maasHesabi(p).$3)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB3261E)),
              ),
            ),
          if (_izinOzet[p.id] != null) _izinOzetiSatiri(_izinOzet[p.id]!),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Wrap(spacing: 5, runSpacing: 5, children: [
              for (var g = 1; g <= _gunSayisi; g++) _gunKutusu(p, g),
            ]),
          ),
          for (final (bas, son) in _izinGruplari(p))
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 10),
              child: OutlinedButton.icon(
                onPressed: () => _formSec(p, bas, son),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text('Yıllık izin formu: ${_aralikYaz(bas, son)} (${_formGun(bas, son, false)} gün)'),
              ),
            ),
          for (final (bas, son) in _durumGruplari(p, Durum.gelmedi))
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 10),
              child: OutlinedButton.icon(
                onPressed: () => _formSec(p, bas, son, ucretsiz: true),
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text('Ücretsiz izin dilekçesi: ${_aralikYaz(bas, son)} (${son - bas + 1} gün)'),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _gunKutusu(Personel p, int gun) {
    final tarih = DateTime(_yil, _ayNum, gun);
    final ilk = DateTime(p.giris.year, p.giris.month, p.giris.day);
    final son = p.cikis == null ? null : DateTime(p.cikis!.year, p.cikis!.month, p.cikis!.day);
    final calisiyor = !tarih.isBefore(ilk) && (son == null || !tarih.isAfter(son));
    if (!calisiyor) {
      return SizedBox(
        width: 36,
        height: 36,
        child: Center(child: Text('$gun', style: const TextStyle(fontSize: 13, color: Colors.black26))),
      );
    }
    final d = _kayit[_anahtar(p, gun)];
    final haftaSonu = tarih.weekday >= 6;
    final secili = _secPersonel == p && _secGunler.contains(gun);
    return InkWell(
      onTap: () => _gunSec(p, gun),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: d?.renk ?? (secili ? const Color(0xFFCFE8E4) : (haftaSonu ? Colors.grey.shade200 : Colors.white)),
          border: Border.all(
              color: secili ? Colors.black87 : (d?.renk ?? Colors.grey.shade300), width: secili ? 2.5 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('$gun',
            style: TextStyle(
                fontSize: 13,
                fontWeight: (d == null && !secili) ? FontWeight.w400 : FontWeight.w700,
                color: d != null ? Colors.white : (haftaSonu ? Colors.black87 : Colors.black87))),
      ),
    );
  }

  Widget _ozet(String baslik, String deger, Color renk, {VoidCallback? onTap}) {
    final icerik = Column(children: [
      Text(deger, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: renk)),
      const SizedBox(height: 2),
      Text(baslik,
          style: TextStyle(
              fontSize: 11,
              color: onTap == null ? Colors.black87 : renk,
              decoration: onTap == null ? null : TextDecoration.underline)),
    ]);
    if (onTap == null) return icerik;
    return Tooltip(
      message: 'Hangi aylarda olduğunu göster',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: icerik),
      ),
    );
  }

  /// Seçili yıl için, personelin izin / gelmedi / rapor günlerini aylara göre listeler.
  Future<void> _durumAylari(Durum d) async {
    final kisiler = _gorunenYil();
    if (kisiler.isEmpty) return;
    final satirlar = <int, Map<int, List<int>>>{}; // personel -> ay -> günler
    String? hata;
    try {
      for (var ofset = 0;; ofset += 1000) {
        final parca = await _db
            .from('izin_kayitlari')
            .select('personel_id, tarih')
            .eq('durum', d.name)
            .inFilter('personel_id', [for (final p in kisiler) p.id])
            .gte('tarih', '$_yil-01-01')
            .lte('tarih', '$_yil-12-31')
            .order('tarih')
            .range(ofset, ofset + 999);
        for (final m in parca) {
          final t = DateTime.parse(m['tarih'] as String);
          satirlar.putIfAbsent(m['personel_id'] as int, () => {}).putIfAbsent(t.month, () => []).add(t.day);
        }
        if (parca.length < 1000) break;
      }
    } catch (e) {
      hata = 'Yüklenemedi: $e';
    }
    if (!mounted) return;

    // 5, 6, 7, 12 -> "5-7, 12"
    String aralik(List<int> g) {
      g.sort();
      final b = <String>[];
      var bas = g.first, onc = g.first;
      for (var i = 1; i <= g.length; i++) {
        if (i < g.length && g[i] == onc + 1) {
          onc = g[i];
          continue;
        }
        b.add(bas == onc ? '$bas' : '$bas-$onc');
        if (i < g.length) bas = onc = g[i];
      }
      return b.join(', ');
    }

    final bulunan = [for (final p in kisiler) if ((satirlar[p.id] ?? {}).isNotEmpty) p];
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${d.ad} günleri, $_yil'),
        content: SizedBox(
          width: 460,
          child: hata != null
              ? Text(hata)
              : bulunan.isEmpty
                  ? Text('$_yil yılında ${d.ad.toLowerCase()} kaydı yok.')
                  : SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final p in bulunan) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 2),
                            child: Text(
                              '${p.ad}  (toplam ${satirlar[p.id]!.values.fold<int>(0, (a, b) => a + b.length)} gün)',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          for (final ay in (satirlar[p.id]!.keys.toList()..sort()))
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 1),
                              child: Text(
                                  '${_aylar[ay - 1]}: ${satirlar[p.id]![ay]!.length} gün (${aralik(satirlar[p.id]![ay]!)})'),
                            ),
                        ],
                      ]),
                    ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
      ),
    );
  }

  /// Seçili yıl içinde çalışmış personel (yıllık liste ile aynı mantık)
  List<Personel> _gorunenYil() =>
      (_firmaPersonel.where((p) => p.giris.year <= _yil && (p.cikis == null || p.cikis!.year >= _yil)).toList())
        ..sort((a, b) => trKarsilastir(a.ad, b.ad));

  /// Daha önce çalışmış (çıkmış) personelden birini seçip yeniden işe giriş kaydı açar.
  Future<void> _eskiPersoneldenEkle() async {
    // Aynı kişi birden çok kez girip çıkmış olabilir: TC (yoksa ad) başına en son kaydı al
    final son = <String, Personel>{};
    for (final p in _firmaPersonel) {
      final k = p.tc.isNotEmpty ? p.tc : p.ad.toLowerCase();
      final o = son[k];
      if (o == null || p.giris.isAfter(o.giris)) son[k] = p;
    }
    final liste = son.values.toList()..sort((a, b) => trKarsilastir(a.ad, b.ad));
    if (liste.isEmpty) {
      _mesaj('Bu firmada daha önce kayıtlı personel yok.');
      return;
    }
    var sorgu = '';
    final secilen = await showDialog<Personel>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final q = sorgu.toLowerCase();
          final gorunen = liste.where((p) => q.isEmpty || p.ad.toLowerCase().contains(q) || p.tc.contains(q)).toList();
          return AlertDialog(
            title: const Text('Eski personelden ekle'),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  onChanged: (v) => setD(() => sorgu = v),
                  decoration: const InputDecoration(hintText: 'Ad veya TC ara', prefixIcon: Icon(Icons.search), isDense: true),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: gorunen.length,
                    itemBuilder: (c, i) {
                      final p = gorunen[i];
                      return ListTile(
                        dense: true,
                        title: Text(p.ad),
                        subtitle: Text(
                            'Giriş ${_tarihYaz(p.giris)}${p.cikis == null ? ' (çalışıyor)' : '  Çıkış ${_tarihYaz(p.cikis!)}'}'),
                        onTap: () => Navigator.pop(c, p),
                      );
                    },
                  ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç'))],
          );
        },
      ),
    );
    if (secilen != null && mounted) await _personelForm(kopya: secilen);
  }
}

// YAMA2-UYGULANDI
