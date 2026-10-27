import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart' show bordroKaydet, tl;
import 'firmalar.dart';
import 'pusula_cikti.dart' show whatsappMesajAc;
import 'secili_firma.dart';
import 'yedek.dart' show xlsxYaz;

part 'ozet.dart';
part 'takvim.dart';

/// Sadece yöneticinin gördüğü beyanname kontrol listesi.
/// Her firma için seçilen ayda: Bekliyor -> Onaylandı -> Gönderildi.
const _kdv = 'KDV';
const _muhtasar = 'Muhtasar ve Prim Hizmet';
const _sgk = 'SGK Hizmet Dökümü'; // sadece o ay personeli olan firmalarda görünür
const _vergi = 'Geçici / Gelir / Kurumlar Vergisi';
const _edefter = 'E-Defter';
const _gekap = 'GEKAP';
const _turler = [_kdv, _muhtasar, _sgk, _vergi, _edefter, _gekap];

// Personeli kalmayan firma "üç aylığa çevrildi" olarak işaretlenince kayıt: yil=0, ay=1, durum=2
const _cevrildiAnahtari = 'Üç aylığa çevrildi';

// ---- Kullanıcının eklediği özel sütunlar (Ba-Bs, KDV iadesi, yıllık işler vb.) ----
class _OzelSutun {
  final int id;
  String ad;
  List<int> aylar; // görüneceği aylar (1-12)
  int gun; // son gün (0 = son gün yok)
  int ofset; // 0: aynı ayın günü, 1: izleyen ayın günü
  bool tum; // tüm firmalar mı
  List<int> firmalar; // tum=false ise geçerli firmalar
  _OzelSutun(this.id, this.ad, this.aylar, this.gun, this.ofset, this.tum, this.firmalar);
  String get anahtar => 'ozel:$id';
}

final List<_OzelSutun> _ozelSutunlar = [];

_OzelSutun? _ozelBul(String tur) {
  for (final o in _ozelSutunlar) {
    if (o.anahtar == tur) return o;
  }
  return null;
}

/// Seçili ayda görünen tüm sütunlar: sabit olanlar + o ay için tanımlı özel sütunlar.
List<String> _tumTurler(int ay) => [
      ..._turler,
      for (final o in _ozelSutunlar)
        if (o.aylar.contains(ay)) o.anahtar,
    ];

Future<void> _ozelYukle() async {
  try {
    final rows = await Supabase.instance.client.from('ozel_sutun').select().eq('aktif', true).order('id');
    _ozelSutunlar
      ..clear()
      ..addAll([
        for (final r in rows)
          _OzelSutun(
            r['id'] as int,
            r['ad'] as String,
            [for (final a in (r['aylar'] as List)) (a as num).toInt()],
            (r['gun'] as num).toInt(),
            (r['ofset'] as num).toInt(),
            (r['tum_firmalar'] ?? true) as bool,
            [for (final f in ((r['firma_idleri'] ?? const []) as List)) (f as num).toInt()],
          ),
      ]);
  } catch (_) {
    // tablo yoksa (supabase_ozel_sutun.sql çalıştırılmadıysa) yalnızca sabit sütunlar görünür
  }
}

String _sutunAdi(String t) => _ozelBul(t)?.ad ?? (t == _sgk ? 'SGK' : t);

// ---- Beyanname bildirim (son gün) kuralları: gerekirse sadece bu bölümü değiştir ----
// Dönem: seçili ay. Hafta sonuna denk gelen son gün bir sonraki iş gününe kaydırılır
// (resmi tatiller hesaba katılmaz).
DateTime _haftaIci(DateTime d) {
  var x = d;
  while (x.weekday == DateTime.saturday || x.weekday == DateTime.sunday) {
    x = x.add(const Duration(days: 1));
  }
  return x;
}

/// Son güne <= 5 gün kala (veya geçmişse) uyarı metni ve rengi; yoksa null.
(String, Color)? _uyari(DateTime tarih) {
  final b = DateTime.now();
  final bugun = DateTime(b.year, b.month, b.day);
  final fark = DateTime(tarih.year, tarih.month, tarih.day).difference(bugun).inDays;
  if (fark < 0) return ('Süresi geçti!', const Color(0xFFB3261E));
  if (fark == 0) return ('SON GÜN BUGÜN!', const Color(0xFFB3261E));
  if (fark == 1) return ('Yarın son gün!', const Color(0xFFE65100));
  if (fark <= 5) return ('Son güne $fark gün kaldı', const Color(0xFFEF6C00));
  return null;
}

Widget _uyariRozeti(DateTime tarih) {
  final u = _uyari(tarih);
  if (u == null) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.warning_amber_rounded, size: 13, color: u.$2),
      const SizedBox(width: 2),
      Text(u.$1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: u.$2)),
    ]),
  );
}

String _gunYaz(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// E-Defter berat yükleme son günü (GİB duyurusu 13.01.2026/27-3).
/// Aylık tercih: Ocak -> Mayıs ... Ağustos -> Aralık, Eylül -> Ocak ... Kasım -> Mart,
/// Aralık -> gelir vergisi beyan ayını (Mart) izleyen ayın 10'u / kurumlar beyan ayını (Nisan) izleyen ayın 14'ü.
/// Geçici vergi dönemi tercihi: Ocak-Mart -> Haziran, Nisan-Haziran -> Eylül, Temmuz-Eylül -> Aralık,
/// Ekim-Aralık -> Nisan 10 (gelir) / Mayıs 14 (kurumlar).
/// Gelir vergisi mükellefi: 10. gün, diğerleri (kurumlar vb.): 14. gün. TC no kayıtlıysa gelir vergisi mükellefi sayılır.
(String, DateTime) _edefterSonGunHam(Firma f, int yil, int ay) {
  final gelir = f.tcNo.isNotEmpty;
  final gun = gelir ? 10 : 14;
  DateTime yilSonu() => gelir ? DateTime(yil + 1, 4, 10) : DateTime(yil + 1, 5, 14);
  if (f.eDefterTercih == 'gecici') {
    final q = (ay - 1) ~/ 3;
    const adlar = ['Ocak-Mart', 'Nisan-Haziran', 'Temmuz-Eylül', 'Ekim-Aralık'];
    final tarih = switch (q) {
      0 => DateTime(yil, 6, gun),
      1 => DateTime(yil, 9, gun),
      2 => DateTime(yil, 12, gun),
      _ => yilSonu(),
    };
    return (adlar[q], _haftaIci(tarih));
  }
  final DateTime tarih;
  if (ay <= 8) {
    tarih = DateTime(yil, ay + 4, gun);
  } else if (ay <= 11) {
    tarih = DateTime(yil + 1, ay - 8, gun);
  } else {
    tarih = yilSonu();
  }
  return ('', _haftaIci(tarih));
}

List<(String, DateTime)> _sonTarihlerHam(String tur, int yil, int ay) {
  final ozel = _ozelBul(tur);
  if (ozel != null) {
    if (ozel.gun <= 0) return [];
    final ayinSonu = DateTime(yil, ay + ozel.ofset + 1, 0).day;
    final gun = ozel.gun > ayinSonu ? ayinSonu : ozel.gun;
    return [('', _haftaIci(DateTime(yil, ay + ozel.ofset, gun)))];
  }
  switch (tur) {
    case _kdv:
      return [('', _haftaIci(DateTime(yil, ay + 1, 28)))]; // izleyen ayın 28'i
    case _muhtasar:
      return [('', _haftaIci(DateTime(yil, ay + 1, 26)))]; // izleyen ayın 26'sı
    case _sgk:
      return [('', _haftaIci(DateTime(yil, ay + 2, 0)))]; // izleyen ayın son günü
    case _gekap:
      return [('', _haftaIci(DateTime(yil, ay + 1, 26)))]; // izleyen ayın 26'sı
    case _edefter:
      return []; // E-Defter son günü firmaya göre hücrede gösterilir (_edefterSonGun)
    case _vergi:
      return switch (ay) {
        3 => [('Geçici ', _haftaIci(DateTime(yil, 5, 17)))],
        6 => [('Geçici ', _haftaIci(DateTime(yil, 8, 17)))],
        9 => [('Geçici ', _haftaIci(DateTime(yil, 11, 17)))],
        12 => [
            ('Geçici ', _haftaIci(DateTime(yil + 1, 2, 17))),
            ('Gelir ', _haftaIci(DateTime(yil + 1, 3, 31))),
            ('Kurumlar ', _haftaIci(DateTime(yil + 1, 4, 30))),
          ],
        _ => <(String, DateTime)>[],
      };
  }
  return [];
}
// ---- Son gün istisnaları: GİB süre uzatması gibi durumlarda yönetici son günü elle değiştirir ----
// anahtar: 'yil|ay|tur|etiket|firma' (firma 0 = tüm firmalar). Firmaya özel olan, genel olandan önce gelir.
final Map<String, (DateTime, String)> _istisnalar = {};
String _istisnaAnahtar(int yil, int ay, String tur, String etiket, int firma) => '$yil|$ay|$tur|$etiket|$firma';

DateTime? _istisnaBul(String tur, int yil, int ay, String etiket, int? firma) {
  if (firma != null) {
    final o = _istisnalar[_istisnaAnahtar(yil, ay, tur, etiket, firma)];
    if (o != null) return o.$1;
  }
  return _istisnalar[_istisnaAnahtar(yil, ay, tur, etiket, 0)]?.$1;
}

bool _firmayaOzelVar(String tur, int yil, int ay, int firma) =>
    _istisnalar.keys.any((k) => k.startsWith('$yil|$ay|$tur|') && k.endsWith('|$firma'));

Future<void> _istisnalariYukle() async {
  try {
    final rows = await Supabase.instance.client.from('son_gun_istisna').select();
    _istisnalar.clear();
    for (final r in rows) {
      _istisnalar[_istisnaAnahtar(r['yil'] as int, r['ay'] as int, r['beyanname'] as String, (r['etiket'] ?? '') as String,
          (r['firma_id'] ?? 0) as int)] = (DateTime.parse(r['yeni_tarih'] as String), (r['neden'] ?? '') as String);
    }
  } catch (_) {
    // tablo yoksa (supabase_istisna.sql çalıştırılmadıysa) kurallar olduğu gibi kalır
  }
}

(String, DateTime) _edefterSonGun(Firma f, int yil, int ay) {
  final (donem, tarih) = _edefterSonGunHam(f, yil, ay);
  return (donem, _istisnaBul(_edefter, yil, ay, '', f.id) ?? tarih);
}

List<(String, DateTime)> _sonTarihler(String tur, int yil, int ay, {int? firma}) => [
      for (final (etiket, tarih) in _sonTarihlerHam(tur, yil, ay)) (etiket, _istisnaBul(tur, yil, ay, etiket, firma) ?? tarih),
    ];

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

/// Süresi geçtiği halde onaylanmamış bir beyanname (hangi firma, hangi dönem).
class _Geciken {
  final Firma f;
  final String tur;
  final int yil, ay;
  final DateTime son;
  _Geciken(this.f, this.tur, this.yil, this.ay, this.son);
}

String _kucuk(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

class BeyannameKontrolSayfasi extends StatefulWidget {
  const BeyannameKontrolSayfasi({super.key});

  @override
  State<BeyannameKontrolSayfasi> createState() => _BeyannameKontrolSayfasiState();
}

class _BeyannameKontrolSayfasiState extends State<BeyannameKontrolSayfasi> {
  final _db = Supabase.instance.client;
  late int _yil;
  late int _ay; // 1-12
  final Set<int> _personelli = {}; // seçili ayda personeli olan firmalar
  final Set<int> _cevrilmeli = {}; // personeli kalmamış, henüz üç aylığa çevrilmemiş firmalar
  final Set<int> _cevrildi = {}; // üç aylığa çevrildi diye işaretlenenler
  final Map<String, int> _durum = {}; // "firmaId|tür" -> 0 bekliyor, 1 onaylandı, 2 gönderildi
  bool _yukleniyor = true;
  bool _sadeceEksik = false;
  final _yatay = ScrollController();
  final _ara = TextEditingController();
  bool _fAylik = false, _fPersonelli = false;
  bool _secimModu = false;
  final Set<int> _secili = {};
  final List<_Geciken> _geciken = [];
  int _gecikenAy = 3; // geciken işler penceresinde kaç ay geriye bakılsın

  @override
  void dispose() {
    _yatay.dispose();
    _ara.dispose();
    super.dispose();
  }

  void _sonaKaydir() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_yatay.hasClients) _yatay.animateTo(_yatay.position.maxScrollExtent, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    });
  }
  String? _hata;

  @override
  void initState() {
    super.initState();
    final simdi = DateTime.now();
    // Genellikle bir önceki ayın beyannameleri hazırlanır.
    _yil = simdi.month == 1 ? simdi.year - 1 : simdi.year;
    _ay = simdi.month == 1 ? 12 : simdi.month - 1;
    _yukle();
  }

  String _anahtar(int firmaId, String tur) => '$firmaId|$tur';

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      await FirmaDeposu.ornek.yukle();
      await _istisnalariYukle();
      await _ozelYukle();
      final satirlar = await _db.from('beyanname_kontrol').select().eq('yil', _yil).eq('ay', _ay);
      final ayBas = DateTime(_yil, _ay, 1);
      final aySon = DateTime(_yil, _ay + 1, 0);
      final personel = await _db.from('personel').select('firma_id, giris, cikis');
      _personelli.clear();
      final kayitli = <int>{}; // hiç personeli olmuş firmalar
      final hepsiAyrildi = <int, bool>{}; // seçili aydan önce hepsi ayrılmış mı
      for (final s in personel) {
        final firmaId = s['firma_id'] as int;
        final giris = DateTime.parse(s['giris'] as String);
        final cikis = s['cikis'] == null ? null : DateTime.parse(s['cikis'] as String);
        kayitli.add(firmaId);
        if (!giris.isAfter(aySon) && (cikis == null || !cikis.isBefore(ayBas))) {
          _personelli.add(firmaId);
        }
        final ayrildi = cikis != null && cikis.isBefore(ayBas);
        hepsiAyrildi[firmaId] = (hepsiAyrildi[firmaId] ?? true) && ayrildi;
      }
      final cevrildiSatirlari = await _db.from('beyanname_kontrol').select('firma_id').eq('beyanname', _cevrildiAnahtari);
      _cevrildi
        ..clear()
        ..addAll([for (final s in cevrildiSatirlari) s['firma_id'] as int]);
      _cevrilmeli
        ..clear()
        ..addAll([for (final id in kayitli) if (hepsiAyrildi[id] == true && !_cevrildi.contains(id)) id]);
      _durum.clear();
      for (final s in satirlar) {
        _durum[_anahtar(s['firma_id'] as int, s['beyanname'] as String)] = (s['durum'] as num).toInt();
      }
      try {
        await _gecikenHesapla(personel);
      } catch (_) {
        _geciken.clear();
      }
    } catch (e) {
      _hata = 'Liste yüklenemedi: $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  /// Son 13 ayın dönemlerinde süresi geçmiş ama onaylanmamış beyannameleri bulur.
  /// Bir firma için yalnızca ilk kayıt girdiği aydan itibaren bakılır (eski aylar geriye dönük borç gibi görünmesin).
  Future<void> _gecikenHesapla(List personel) async {
    final n = DateTime.now();
    final bugun = DateTime(n.year, n.month, n.day);
    final bas = DateTime(n.year, n.month - 12, 1);
    final rows = await _db.from('beyanname_kontrol').select('firma_id, yil, ay, beyanname, durum').gte('yil', bas.year);
    final d = <String, int>{};
    final ilk = <int, int>{}; // firma -> ilk kayıtlı ay (yil*12+ay)
    for (final s in rows) {
      final y = (s['yil'] as num).toInt(), a = (s['ay'] as num).toInt(), f = (s['firma_id'] as num).toInt();
      if (y <= 0) continue;
      d['$f|$y|$a|${s['beyanname']}'] = (s['durum'] as num).toInt();
      final i = y * 12 + a;
      if (!ilk.containsKey(f) || i < ilk[f]!) ilk[f] = i;
    }
    _geciken.clear();
    for (var k = 0; k <= 12; k++) {
      final m = DateTime(bas.year, bas.month + k, 1);
      final yil = m.year, ay = m.month;
      final ayBas = DateTime(yil, ay, 1), aySon = DateTime(yil, ay + 1, 0);
      final personelli = <int>{};
      for (final s in personel) {
        final giris = DateTime.parse(s['giris'] as String);
        final cikis = s['cikis'] == null ? null : DateTime.parse(s['cikis'] as String);
        if (!giris.isAfter(aySon) && (cikis == null || !cikis.isBefore(ayBas))) personelli.add(s['firma_id'] as int);
      }
      for (final f in FirmaDeposu.ornek.liste) {
        if (!ilk.containsKey(f.id) || yil * 12 + ay < ilk[f.id]!) continue;
        for (final t in _tumTurler(ay)) {
          final ozel = _ozelBul(t);
          final gecerli = ozel != null
              ? (ozel.tum || ozel.firmalar.contains(f.id))
              : t == _sgk
                  ? personelli.contains(f.id)
                  : t == _edefter
                      ? f.eDefter
                      : t == _gekap
                          ? f.gekap
                          : true;
          if (!gecerli) continue;
          DateTime son;
          if (t == _edefter) {
            if (f.eDefterTercih == 'gecici' && ay % 3 != 0) continue;
            son = _edefterSonGun(f, yil, ay).$2;
          } else {
            final l = _sonTarihler(t, yil, ay, firma: f.id).map((e) => e.$2).toList()..sort();
            if (l.isEmpty) continue;
            son = l.last;
          }
          if (!son.isBefore(bugun)) continue;
          final tamamDeger = t == _edefter ? 2 : 1;
          var bitti = (d['${f.id}|$yil|$ay|$t'] ?? 0) >= tamamDeger;
          if (!bitti && t == _edefter && f.eDefterTercih == 'gecici') {
            for (var x = ay - 2; x < ay; x++) {
              if ((d['${f.id}|$yil|$x|$t'] ?? 0) >= tamamDeger) bitti = true;
            }
          }
          if (!bitti) _geciken.add(_Geciken(f, t, yil, ay, son));
        }
      }
    }
    _geciken.sort((a, b) => a.son.compareTo(b.son));
  }

  List<_Geciken> get _gecikenGorunen {
    final n = DateTime.now();
    final simdi = n.year * 12 + n.month;
    return [for (final g in _geciken) if (simdi - (g.yil * 12 + g.ay) <= _gecikenAy) g];
  }

  Future<void> _gecikenleriGoster() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        final liste = _gecikenGorunen;
        final grup = <int, List<_Geciken>>{};
        for (final g in liste) {
          (grup[g.f.id] ??= []).add(g);
        }
        final n = DateTime.now();
        final bugun = DateTime(n.year, n.month, n.day);
        return AlertDialog(
          title: Text('Geciken beyannameler (${liste.length})'),
          content: SizedBox(
            width: 620,
            height: 480,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Geriye bakış: '),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 3, label: Text('3 ay')),
                    ButtonSegment(value: 6, label: Text('6 ay')),
                    ButtonSegment(value: 12, label: Text('12 ay')),
                  ],
                  selected: {_gecikenAy},
                  onSelectionChanged: (v) {
                    setState(() => _gecikenAy = v.first);
                    setD(() {});
                  },
                ),
              ]),
              const SizedBox(height: 6),
              const Text('Çipe dokunursan o ayın listesi açılır. Yalnızca ilk kayıt girdiğin aydan sonraki dönemler sayılır.',
                  style: TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(height: 8),
              Expanded(
                child: liste.isEmpty
                    ? const Center(child: Text('Geciken iş görünmüyor.'))
                    : ListView(children: [
                        for (final e in grup.entries)
                          Card(
                            elevation: 0,
                            color: const Color(0xFFF7F2F2),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(e.value.first.f.unvan, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  for (final g in e.value)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text('${_sutunAdi(g.tur)} • ${_aylar[g.ay - 1].substring(0, 3)} ${g.yil} • ${bugun.difference(g.son).inDays} gün', style: const TextStyle(fontSize: 12)),
                                      onPressed: () {
                                        Navigator.pop(c);
                                        setState(() {
                                          _yil = g.yil;
                                          _ay = g.ay;
                                        });
                                        _yukle();
                                      },
                                    ),
                                ]),
                              ]),
                            ),
                          ),
                      ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        );
      }),
    );
  }

  String _hucreMetni(Firma f, String t) {
    if (t == _sgk && _cevrilmeli.contains(f.id)) return 'Çevrilmeli';
    if (!_gecerli(f, t)) return '-';
    return _tamam(f, t) ? (t == _edefter ? 'Gönderildi' : 'Onaylandı') : 'Bekliyor';
  }

  Future<void> _disaAktar(bool pdf, List<Firma> firmalar, List<String> turlar) async {
    final donem = '${_aylar[_ay - 1]} $_yil';
    final dosya = 'kontrol_listesi_${_yil}_${_ay.toString().padLeft(2, '0')}';
    try {
      if (!pdf) {
        final satirlar = <List<dynamic>>[
          for (var i = 0; i < firmalar.length; i++) [i + 1, firmalar[i].unvan, for (final t in turlar) _hucreMetni(firmalar[i], t)]
        ];
        final bytes = xlsxYaz([('Kontrol listesi', ['No', 'Firma', for (final t in turlar) _sutunAdi(t)], satirlar)]);
        await bordroKaydet(dosya, bytes, 'xlsx');
      } else {
        final doc = pw.Document(
          theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()),
        );
        pw.Widget h(String t, {bool kalin = false, PdfColor? zemin}) => pw.Container(
              color: zemin,
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
              child: pw.Text(t, style: pw.TextStyle(fontSize: 7.5, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
            );
        const yesil = PdfColor.fromInt(0xFFD7EBD8), pembe = PdfColor.fromInt(0xFFF6DADA), gri = PdfColor.fromInt(0xFFE6E6E6);
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (c) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text('Beyanname kontrol listesi - $donem', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
          footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8))),
          build: (c) => [
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              columnWidths: {0: const pw.FixedColumnWidth(20), 1: const pw.FlexColumnWidth(3.2), for (var i = 0; i < turlar.length; i++) i + 2: const pw.FlexColumnWidth(1)},
              children: [
                pw.TableRow(children: [h('No', kalin: true, zemin: gri), h('Firma', kalin: true, zemin: gri), for (final t in turlar) h(_sutunAdi(t), kalin: true, zemin: gri)]),
                for (var i = 0; i < firmalar.length; i++)
                  pw.TableRow(children: [
                    h('${i + 1}'),
                    h(firmalar[i].unvan),
                    for (final t in turlar)
                      () {
                        final m = _hucreMetni(firmalar[i], t);
                        return h(m, zemin: m == 'Onaylandı' || m == 'Gönderildi' ? yesil : (m == 'Bekliyor' || m == 'Çevrilmeli' ? pembe : null));
                      }(),
                  ]),
              ],
            ),
          ],
        ));
        await bordroKaydet(dosya, await doc.save(), 'pdf');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dosya oluşturulamadı: $e')));
    }
  }

  /// Firmaya kısa not yazar ve o ayın bekleyen işleri için hazır WhatsApp mesajı oluşturur.
  Future<void> _firmaMesaj(Firma f) async {
    final eksik = [
      for (final t in _tumTurler(_ay))
        if (_gecerli(f, t) && !_tamam(f, t) && !(t == _sgk && _cevrilmeli.contains(f.id))) _sutunAdi(t)
    ];
    final donem = '${_aylar[_ay - 1]} $_yil';
    final mesaj = TextEditingController(
        text: eksik.isEmpty
            ? 'Sayın ${f.unvan} yetkilisi, $donem dönemi işlemleriniz tamamlanmıştır. İyi çalışmalar dilerim.'
            : 'Sayın ${f.unvan} yetkilisi, $donem dönemi ${eksik.join(', ')} işlemleri için gerekli evrak ve bilgilerinizin tarafıma iletilmesini rica ederim. Teşekkürler.');
    final not = TextEditingController(text: f.not);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f.unvan, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: not, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Firma notu (yalnızca sen görürsün)', hintText: 'Örn. evrakı ayın 20\'sinde getiriyor')),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    try {
                      await _db.from('firmalar').update({'not_defteri': not.text.trim()}).eq('id', f.id);
                      f.not = not.text.trim();
                      if (mounted) setState(() {});
                      if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Not kaydedildi.')));
                    } catch (e) {
                      if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
                    }
                  },
                  child: const Text('Notu kaydet'),
                ),
              ),
              const Divider(),
              TextField(controller: mesaj, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Mükellefe mesaj (düzenleyebilirsin)')),
              const SizedBox(height: 6),
              Text(f.telefon.isEmpty ? 'Firmada telefon kayıtlı değil.' : 'Telefon: ${f.telefon}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: mesaj.text));
              if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Mesaj kopyalandı.')));
            },
            child: const Text('Kopyala'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final tamam = await whatsappMesajAc(f.telefon, mesaj.text);
              if (!tamam) {
                await Clipboard.setData(ClipboardData(text: mesaj.text));
                if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Telefon kayıtlı değil, mesaj kopyalandı. WhatsApp Web açıldı.')));
              }
            },
            icon: const Icon(Icons.chat, size: 18),
            label: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }

  /// Çoklu seçimde işaretlenen firmalar için seçilen sütunu toplu onaylar / kaldırır.
  Future<void> _seciliIsle(String tur, bool isaretle) async {
    final secili = [for (final f in FirmaDeposu.ornek.liste) if (_secili.contains(f.id)) f];
    await _topluIsle(tur, isaretle, sadece: secili);
  }

  void _ayDegistir(int fark) {
    var a = _ay + fark;
    var y = _yil;
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
    });
    _yukle();
  }

  Future<void> _ayarla(Firma f, String tur, int yeni) async {
    final k = _anahtar(f.id, tur);
    final eski = _durum[k] ?? 0;
    setState(() => _durum[k] = yeni);
    try {
      if (yeni == 0) {
        await _db
            .from('beyanname_kontrol')
            .delete()
            .eq('firma_id', f.id)
            .eq('yil', _yil)
            .eq('ay', _ay)
            .eq('beyanname', tur);
      } else {
        await _db.from('beyanname_kontrol').upsert({
          'firma_id': f.id,
          'yil': _yil,
          'ay': _ay,
          'beyanname': tur,
          'durum': yeni,
          'guncelleme': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'firma_id,yil,ay,beyanname');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _durum[k] = eski);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      return;
    }
    // Muhtasar ve Prim Hizmet onaylanınca, o ay personeli olan firmanın SGK Hizmet Dökümü de onaylanır.
    if (tur == _muhtasar && yeni >= 1 && _gecerli(f, _sgk) && !_cevrilmeli.contains(f.id) && (_durum[_anahtar(f.id, _sgk)] ?? 0) < 1) {
      await _ayarla(f, _sgk, 1);
    }
  }

  /// Bu sütunun tamamlanma değeri: E-Defter'de "gönderildi" (2), diğerlerinde "onaylandı" (1).
  int _tamamDurum(String tur) => tur == _edefter ? 2 : 1;

  bool _tamam(Firma f, String tur) => (_durum[_anahtar(f.id, tur)] ?? 0) >= _tamamDurum(tur);

  List<Firma> _hedefler(String tur) => [
        for (final f in _firmalarda(tur))
          if (!(tur == _sgk && _cevrilmeli.contains(f.id))) f
      ];

  bool _sutunTamam(String tur) {
    final l = _hedefler(tur);
    return l.isNotEmpty && l.every((f) => _tamam(f, tur));
  }

  Future<void> _topluIsle(String tur, bool isaretle, {List<Firma>? sadece}) async {
    final tumHedef = _hedefler(tur);
    final hedef = sadece == null ? tumHedef : [for (final f in tumHedef) if (sadece.any((s) => s.id == f.id)) f];
    if (hedef.isEmpty) return;
    final etiket = tur == _edefter ? 'Gönderildi' : 'Onaylandı';
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isaretle ? 'Tümünü işaretle' : 'Tüm işaretleri kaldır'),
        content: Text(isaretle
            ? '${_sutunAdi(tur)}: ${hedef.length} ${sadece == null ? '' : 'seçili '}firma "$etiket" olarak işaretlensin mi?${tur == _muhtasar ? ' (Personeli olan firmalarda SGK da onaylanır.)' : ''}'
            : '${_sutunAdi(tur)}: ${hedef.length} firmanın ${_aylar[_ay - 1]} $_yil işareti kaldırılsın mı?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Evet')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      if (isaretle) {
        final zaman = DateTime.now().toUtc().toIso8601String();
        final sgkIle = tur == _muhtasar ? [for (final f in hedef) if (_gecerli(f, _sgk) && !_cevrilmeli.contains(f.id)) f] : <Firma>[];
        await _db.from('beyanname_kontrol').upsert([
          for (final f in hedef)
            {
              'firma_id': f.id,
              'yil': _yil,
              'ay': _ay,
              'beyanname': tur,
              'durum': _tamamDurum(tur),
              'guncelleme': zaman,
            },
          for (final f in sgkIle)
            {
              'firma_id': f.id,
              'yil': _yil,
              'ay': _ay,
              'beyanname': _sgk,
              'durum': 1,
              'guncelleme': zaman,
            },
        ], onConflict: 'firma_id,yil,ay,beyanname');
        if (mounted) setState(() {
          for (final f in sgkIle) {
            _durum[_anahtar(f.id, _sgk)] = 1;
          }
        });
      } else {
        await _db
            .from('beyanname_kontrol')
            .delete()
            .eq('yil', _yil)
            .eq('ay', _ay)
            .eq('beyanname', tur)
            .inFilter('firma_id', [for (final f in hedef) f.id]);
      }
      if (!mounted) return;
      setState(() {
        for (final f in hedef) {
          if (isaretle) {
            _durum[_anahtar(f.id, tur)] = _tamamDurum(tur);
          } else {
            _durum.remove(_anahtar(f.id, tur));
          }
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      await _yukle();
    }
  }


  /// Son günü elle değiştirir (süre uzatması vb.). [firma] verilirse o firma için de seçilebilir.
  Future<void> _sonGunDegistir(String tur, {Firma? firma}) async {
    final adaylar = tur == _edefter ? [('', DateTime(_yil, _ay, 1))] : _sonTarihlerHam(tur, _yil, _ay);
    if (adaylar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_sutunAdi(tur)} için ${_aylar[_ay - 1]} $_yil döneminde son gün tanımlı değil.')));
      return;
    }
    var etiket = adaylar.first.$1;
    var sadeceBuFirma = firma != null;
    DateTime ham(String e) {
      if (tur == _edefter) return firma == null ? DateTime.now() : _edefterSonGunHam(firma, _yil, _ay).$2;
      return adaylar.firstWhere((a) => a.$1 == e).$2;
    }

    DateTime? secili;
    final neden = TextEditingController();
    bool? sonuc;
    var mesgul = false;
    String? hata;

    int kapsamFirma() => sadeceBuFirma ? firma!.id : 0;
    DateTime mevcutTarih() => _istisnalar[_istisnaAnahtar(_yil, _ay, tur, etiket, kapsamFirma())]?.$1 ?? _istisnaBul(tur, _yil, _ay, etiket, firma?.id) ?? ham(etiket);

    secili = mevcutTarih();
    neden.text = _istisnalar[_istisnaAnahtar(_yil, _ay, tur, etiket, kapsamFirma())]?.$2 ?? '';

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final varMi = _istisnalar.containsKey(_istisnaAnahtar(_yil, _ay, tur, etiket, kapsamFirma()));
          return AlertDialog(
            title: Text('${_sutunAdi(tur)} - son günü değiştir', style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_aylar[_ay - 1]} $_yil dönemi', style: const TextStyle(color: Colors.black87)),
                  const SizedBox(height: 10),
                  if (adaylar.length > 1)
                    DropdownButtonFormField<String>(
                      value: etiket,
                      decoration: const InputDecoration(labelText: 'Hangi beyanname'),
                      items: [for (final a in adaylar) DropdownMenuItem(value: a.$1, child: Text(a.$1.trim()))],
                      onChanged: (v) => setD(() {
                        etiket = v ?? etiket;
                        secili = mevcutTarih();
                        neden.text = _istisnalar[_istisnaAnahtar(_yil, _ay, tur, etiket, kapsamFirma())]?.$2 ?? '';
                      }),
                    ),
                  if (firma != null) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: true, label: Text('Sadece bu firma')),
                        ButtonSegment(value: false, label: Text('Tüm firmalar')),
                      ],
                      selected: {sadeceBuFirma},
                      onSelectionChanged: (v) => setD(() {
                        sadeceBuFirma = v.first;
                        secili = mevcutTarih();
                        neden.text = _istisnalar[_istisnaAnahtar(_yil, _ay, tur, etiket, kapsamFirma())]?.$2 ?? '';
                      }),
                    ),
                    if (sadeceBuFirma) Padding(padding: const EdgeInsets.only(top: 4), child: Text(firma.unvan, style: const TextStyle(fontSize: 12, color: Colors.black87))),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Bu sütundaki tüm firmalar için geçerli olur.', style: TextStyle(fontSize: 12, color: Colors.black87)),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: c,
                        initialDate: secili!,
                        firstDate: DateTime(_yil - 1),
                        lastDate: DateTime(_yil + 3),
                      );
                      if (d != null) setD(() => secili = d);
                    },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('Yeni son gün: ${_gunYaz(secili!)}'),
                  ),
                  const SizedBox(height: 4),
                  Text('Normal tarih: ${_gunYaz(ham(etiket))}${tur == _edefter && firma == null ? ' (firmaya göre değişir)' : ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  const SizedBox(height: 8),
                  TextField(controller: neden, decoration: const InputDecoration(labelText: 'Neden (isteğe bağlı)', hintText: 'Örn. GİB süre uzatması')),
                  if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
                ]),
              ),
            ),
            actions: [
              if (varMi)
                TextButton(
                  onPressed: mesgul
                      ? null
                      : () async {
                          setD(() => mesgul = true);
                          try {
                            await _db
                                .from('son_gun_istisna')
                                .delete()
                                .eq('yil', _yil)
                                .eq('ay', _ay)
                                .eq('beyanname', tur)
                                .eq('etiket', etiket)
                                .eq('firma_id', kapsamFirma());
                            sonuc = true;
                            if (c.mounted) Navigator.pop(c);
                          } catch (e) {
                            setD(() {
                              mesgul = false;
                              hata = 'Silinemedi: $e';
                            });
                          }
                        },
                  child: const Text('Normale döndür'),
                ),
              TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(
                onPressed: mesgul
                    ? null
                    : () async {
                        setD(() {
                          mesgul = true;
                          hata = null;
                        });
                        try {
                          final d = secili!;
                          await _db.from('son_gun_istisna').upsert({
                            'yil': _yil,
                            'ay': _ay,
                            'beyanname': tur,
                            'etiket': etiket,
                            'firma_id': kapsamFirma(),
                            'yeni_tarih': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
                            'neden': neden.text.trim(),
                          }, onConflict: 'yil,ay,beyanname,etiket,firma_id');
                          sonuc = true;
                          if (c.mounted) Navigator.pop(c);
                        } catch (e) {
                          setD(() {
                            mesgul = false;
                            hata = 'Kaydedilemedi: $e (supabase_istisna.sql çalıştırıldı mı?)';
                          });
                        }
                      },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
    if (sonuc == true) {
      await _istisnalariYukle();
      if (mounted) setState(() {});
    }
  }


  /// Özel sütunların listesi: ekle, düzenle, sil.
  Future<void> _sutunlariYonet() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Kontrol listesi sütunları'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  'KDV, Muhtasar, SGK, Geçici/Gelir, E-Defter ve GEKAP sabit sütunlardır. Buradan kendi işlerin için ek sütun ekleyebilirsin (örn. Ba-Bs, KDV iadesi, yıllık bilanço).',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                if (_ozelSutunlar.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Henüz özel sütun yok.')),
                for (final o in _ozelSutunlar)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(o.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      o.aylar.length == 12 ? 'Her ay' : o.aylar.map((a) => _aylar[a - 1].substring(0, 3)).join(', '),
                      if (o.gun > 0) 'Son gün: ${o.ofset == 1 ? 'izleyen ayın' : 'ayın'} ${o.gun}. günü',
                      o.tum ? 'Tüm firmalar' : '${o.firmalar.length} firma',
                    ].join(' • ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Düzenle',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () async {
                          await _ozelSutunForm(mevcut: o);
                          setD(() {});
                        },
                      ),
                      IconButton(
                        tooltip: 'Sil',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          final onay = await showDialog<bool>(
                            context: c,
                            builder: (d) => AlertDialog(
                              title: Text('"${o.ad}" sütunu silinsin mi?'),
                              content: const Text('Bu sütundaki tüm işaretlemeler de silinir.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
                                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sil')),
                              ],
                            ),
                          );
                          if (onay != true) return;
                          try {
                            await _db.from('beyanname_kontrol').delete().eq('beyanname', o.anahtar);
                            await _db.from('ozel_sutun').delete().eq('id', o.id);
                            await _ozelYukle();
                            await _yukle();
                            setD(() {});
                          } catch (e) {
                            if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
                          }
                        },
                      ),
                    ]),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final onceki = _ozelSutunlar.length;
                    await _ozelSutunForm();
                    setD(() {});
                    if (_ozelSutunlar.length > onceki) _sonaKaydir();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni sütun ekle'),
                ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      ),
    );
  }

  Future<void> _ozelSutunForm({_OzelSutun? mevcut}) async {
    final ad = TextEditingController(text: mevcut?.ad ?? '');
    final gun = TextEditingController(text: (mevcut?.gun ?? 0) > 0 ? '${mevcut!.gun}' : '');
    final ara = TextEditingController();
    final aylar = <int>{...(mevcut?.aylar ?? List.generate(12, (i) => i + 1))};
    var sonGunVar = (mevcut?.gun ?? 0) > 0;
    var ofset = mevcut?.ofset ?? 1;
    var tum = mevcut?.tum ?? true;
    final secili = <int>{...(mevcut?.firmalar ?? const <int>[])};
    String? hata;
    var mesgul = false;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final q = ara.text.trim().toLowerCase();
          final firmalar = FirmaDeposu.ornek.liste.where((f) => q.isEmpty || f.unvan.toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: Text(mevcut == null ? 'Yeni sütun' : 'Sütunu düzenle'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: ad, decoration: const InputDecoration(labelText: 'Sütun adı', hintText: 'Örn. Ba-Bs')),
                  const SizedBox(height: 14),
                  const Text('Hangi aylarda görünsün?', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 0, children: [
                    for (var i = 1; i <= 12; i++)
                      FilterChip(
                        label: Text(_aylar[i - 1].substring(0, 3)),
                        selected: aylar.contains(i),
                        onSelected: (v) => setD(() => v ? aylar.add(i) : aylar.remove(i)),
                      ),
                  ]),
                  Row(children: [
                    TextButton(onPressed: () => setD(() => aylar..clear()..addAll(List.generate(12, (i) => i + 1))), child: const Text('Her ay')),
                    TextButton(onPressed: () => setD(() => aylar..clear()..addAll([3, 6, 9, 12])), child: const Text('3 ayda bir (Mar, Haz, Eyl, Ara)')),
                  ]),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: sonGunVar,
                    onChanged: (v) => setD(() => sonGunVar = v),
                    title: const Text('Son günü var'),
                    subtitle: const Text('Son günü yaklaşınca uyarı çıkar.', style: TextStyle(fontSize: 11)),
                  ),
                  if (sonGunVar)
                    Row(children: [
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: gun,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Ayın günü', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 0, label: Text('Aynı ay')),
                            ButtonSegment(value: 1, label: Text('İzleyen ay')),
                          ],
                          selected: {ofset},
                          onSelectionChanged: (v) => setD(() => ofset = v.first),
                        ),
                      ),
                    ]),
                  const SizedBox(height: 14),
                  const Text('Hangi firmalarda?', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: true, label: Text('Tüm firmalar')),
                      ButtonSegment(value: false, label: Text('Seçtiğim firmalar')),
                    ],
                    selected: {tum},
                    onSelectionChanged: (v) => setD(() => tum = v.first),
                  ),
                  if (!tum) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: ara,
                      onChanged: (_) => setD(() {}),
                      decoration: InputDecoration(
                        hintText: 'Firma ara',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        suffixText: '${secili.length} seçili',
                      ),
                    ),
                    SizedBox(
                      height: 220,
                      child: ListView(children: [
                        for (final f in firmalar)
                          CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: secili.contains(f.id),
                            onChanged: (v) => setD(() => v == true ? secili.add(f.id) : secili.remove(f.id)),
                            title: Text(f.unvan, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ]),
                    ),
                  ],
                  if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(
                onPressed: mesgul
                    ? null
                    : () async {
                        final g = int.tryParse(gun.text.trim()) ?? 0;
                        if (ad.text.trim().isEmpty) {
                          setD(() => hata = 'Sütun adını yaz.');
                          return;
                        }
                        if (aylar.isEmpty) {
                          setD(() => hata = 'En az bir ay seç.');
                          return;
                        }
                        if (sonGunVar && (g < 1 || g > 31)) {
                          setD(() => hata = 'Gün 1 ile 31 arasında olmalı.');
                          return;
                        }
                        if (!tum && secili.isEmpty) {
                          setD(() => hata = 'En az bir firma seç veya "Tüm firmalar"ı işaretle.');
                          return;
                        }
                        setD(() {
                          mesgul = true;
                          hata = null;
                        });
                        final veri = {
                          'ad': ad.text.trim(),
                          'aylar': (aylar.toList()..sort()),
                          'gun': sonGunVar ? g : 0,
                          'ofset': ofset,
                          'tum_firmalar': tum,
                          'firma_idleri': tum ? <int>[] : secili.toList(),
                        };
                        try {
                          if (mevcut == null) {
                            await _db.from('ozel_sutun').insert(veri);
                          } else {
                            await _db.from('ozel_sutun').update(veri).eq('id', mevcut.id);
                          }
                          await _ozelYukle();
                          await _yukle();
                          if (c.mounted) Navigator.pop(c);
                        } catch (e) {
                          setD(() {
                            mesgul = false;
                            hata = 'Kaydedilemedi: $e (supabase_ozel_sutun.sql çalıştırıldı mı?)';
                          });
                        }
                      },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sutunBasligi(String t) {
    const yesil = Color(0xFF2E7D32);
    final tamam = _sutunTamam(t);
    final tamamNotu = t == _edefter ? 'Tüm firmalar gönderildi' : 'Tüm firmalar onaylandı';
    final bugun = DateTime.now();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: tamam ? yesil.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 128),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        PopupMenuButton<int>(
          tooltip: 'Toplu işlem',
          onSelected: (v) {
            if (v == 3) {
              _sonGunDegistir(t);
            } else {
              _topluIsle(t, v == 1);
            }
          },
          itemBuilder: (c) => const [
            PopupMenuItem(value: 1, child: Text('Tümünü işaretle')),
            PopupMenuItem(value: 2, child: Text('Tüm işaretleri kaldır')),
            PopupMenuDivider(),
            PopupMenuItem(value: 3, child: Text('Son günü değiştir…')),
          ],
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(_sutunAdi(t),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tamam ? yesil : null)),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ]),
        ),
        for (final (etiket, tarih) in _sonTarihler(t, _yil, _ay))
          Text('Son: $etiket${_gunYaz(tarih)}${_istisnaBul(t, _yil, _ay, etiket, null) != null ? ' (değişti)' : ''}',
              style: TextStyle(
                  fontSize: 11,
                  color: (!tamam && bugun.isAfter(tarih.add(const Duration(days: 1))))
                      ? const Color(0xFFB3261E)
                      : Colors.black87)),
        if (tamam)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, size: 14, color: yesil),
            const SizedBox(width: 3),
            Flexible(child: Text(tamamNotu, style: const TextStyle(fontSize: 11, color: yesil, fontWeight: FontWeight.w700))),
          ]),
      ]),
      ),
    );
  }

  bool _gecerli(Firma f, String tur) {
    final ozel = _ozelBul(tur);
    if (ozel != null) return ozel.tum || ozel.firmalar.contains(f.id);
    if (tur == _sgk) return _personelli.contains(f.id);
    if (tur == _edefter) return f.eDefter;
    if (tur == _gekap) return f.gekap;
    return true;
  }

  List<Firma> _firmalarda(String tur) => [for (final f in FirmaDeposu.ornek.liste) if (_gecerli(f, tur)) f];

  Widget _uyariButonu(Firma f) {
    const kirmizi = Color(0xFFB3261E);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: kirmizi,
        side: const BorderSide(color: kirmizi),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => _cevirOnayla(f),
      icon: const Icon(Icons.warning_amber_rounded, size: 18),
      label: const Text('Üç aylığa çevir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _cevirOnayla(Firma f) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Üç aylığa çevrildi mi?'),
        content: Text('${f.unvan} firmasının personeli kalmadı. Üç aylık beyan dönemine çevirdiysen "Çevrildi" de, uyarı kalksın.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çevrildi')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _db.from('beyanname_kontrol').upsert({
        'firma_id': f.id,
        'yil': 0,
        'ay': 1,
        'beyanname': _cevrildiAnahtari,
        'durum': 2,
        'guncelleme': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'firma_id,yil,ay,beyanname');
      if (!mounted) return;
      setState(() {
        _cevrildi.add(f.id);
        _cevrilmeli.remove(f.id);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Widget _hucre(Firma f, String tur) {
    if (tur == _sgk && _cevrilmeli.contains(f.id)) return _uyariButonu(f);
    if (!_gecerli(f, tur)) return const Text('-', style: TextStyle(color: Colors.black54));
    final tamam = _tamam(f, tur);
    final tamamEtiketi = tur == _edefter ? 'Gönderildi' : 'Onaylandı';
    const yesil = Color(0xFF2E7D32);
    final (etiket, renk0, ikon) = tamam
        ? (tamamEtiketi, yesil, tur == _edefter ? Icons.done_all : Icons.check)
        : ('Bekliyor', const Color(0xFFD98585), Icons.hourglass_empty); // hafif kırmızı
    // E-Defter'i aylık yükleyen firmalar mor renkte görünür (geçici vergi dönemlerinde yükleyenlerden ayrılır)
    final aylikEdefter = tur == _edefter && f.eDefterTercih == 'aylik';
    final renk = aylikEdefter ? const Color(0xFF6A3FB5) : renk0;
    final d = tamam ? 1 : 0;
    final secenek = PopupMenuButton<int>(
      tooltip: '$tur - ${f.unvan}',
      onSelected: (v) {
        if (v == 99) {
          _sonGunDegistir(tur, firma: f);
        } else {
          _ayarla(f, tur, v);
        }
      },
      itemBuilder: (c) => [
        const PopupMenuItem(value: 0, child: Text('Bekliyor')),
        PopupMenuItem(value: _tamamDurum(tur), child: Text(tamamEtiketi)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 99, child: Text('Son günü değiştir…')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: d == 0 ? 0.09 : 0.12),
          border: Border.all(color: renk),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, size: 14, color: renk),
          const SizedBox(width: 3),
          Text(etiket, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: renk)),
        ]),
      ),
    );
    if (tur != _edefter) {
      if (tamam) return secenek;
      final tarihler = _sonTarihler(tur, _yil, _ay, firma: f.id).map((e) => e.$2).toList()..sort();
      final yaklasan = tarihler.where((t) => _uyari(t) != null).toList();
      if (yaklasan.isEmpty) return secenek;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        secenek,
        _uyariRozeti(yaklasan.first),
      ]);
    }
    final (donem, tarih) = _edefterSonGun(f, _yil, _ay);
    final gecti = !tamam && DateTime.now().isAfter(tarih.add(const Duration(days: 1)));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      secenek,
      Text('Son: ${_gunYaz(tarih)}${donem.isEmpty ? '' : ' ($donem)'}${_istisnaBul(_edefter, _yil, _ay, '', f.id) != null ? ' (değişti)' : ''}${aylikEdefter ? ' • aylık' : ''}',
          style: TextStyle(fontSize: 10.5, color: gecti ? const Color(0xFFB3261E) : Colors.black87)),
      if (!tamam) _uyariRozeti(tarih),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme.primary;
    final turlar = _tumTurler(_ay);
    final tum = FirmaDeposu.ornek.liste;
    final eksiklerle = _sadeceEksik
        ? tum.where((f) => _cevrilmeli.contains(f.id) || turlar.any((t) => _gecerli(f, t) && !_tamam(f, t))).toList()
        : tum;
    final aranan = _kucuk(_ara.text.trim());
    final firmalar = [
      for (final f in eksiklerle)
        if ((aranan.isEmpty || _kucuk(f.unvan).contains(aranan)) &&
            (!_fAylik || (f.eDefter && f.eDefterTercih == 'aylik')) &&
            (!_fPersonelli || _personelli.contains(f.id)))
          f
    ];
    final gecikenSayi = _gecikenGorunen.length;

    return Column(children: [
      if (_yukleniyor) const LinearProgressIndicator(),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(onPressed: () => _ayDegistir(-1), icon: const Icon(Icons.chevron_left)),
        Text('${_aylar[_ay - 1]} $_yil',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: renk)),
        IconButton(onPressed: () => _ayDegistir(1), icon: const Icon(Icons.chevron_right)),
        const SizedBox(width: 20),
        TextButton.icon(
          onPressed: _sutunlariYonet,
          icon: const Icon(Icons.view_column_outlined, size: 18),
          label: const Text('Sütunları düzenle'),
        ),
        TextButton.icon(
          onPressed: _gecikenleriGoster,
          style: gecikenSayi > 0 ? TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)) : null,
          icon: const Icon(Icons.warning_amber_rounded, size: 18),
          label: Text('Geciken işler ($gecikenSayi)'),
        ),
        TextButton.icon(
          onPressed: () => setState(() {
            _secimModu = !_secimModu;
            if (!_secimModu) _secili.clear();
          }),
          icon: Icon(_secimModu ? Icons.check_box : Icons.check_box_outline_blank, size: 18),
          label: const Text('Çoklu seçim'),
        ),
        PopupMenuButton<String>(
          tooltip: 'Bu listeyi indir',
          onSelected: (v) => _disaAktar(v == 'pdf', firmalar, turlar),
          itemBuilder: (c) => const [
            PopupMenuItem(value: 'xlsx', child: Text('Excel olarak indir')),
            PopupMenuItem(value: 'pdf', child: Text('PDF olarak indir')),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.download_outlined, size: 18), SizedBox(width: 6), Text('İndir')]),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final t in turlar)
            Text(
              _sutunTamam(t)
                  ? '${_sutunAdi(t)}: Tüm firmalar ${t == _edefter ? 'gönderildi' : 'onaylandı'} ✓'
                  : '${_sutunAdi(t)}: ${_hedefler(t).where((f) => _tamam(f, t)).length}/${_hedefler(t).length} ${t == _edefter ? 'gönderildi' : 'onaylandı'}',
              style: TextStyle(
                fontSize: 13,
                color: _sutunTamam(t) ? const Color(0xFF2E7D32) : Colors.black87,
                fontWeight: _sutunTamam(t) ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          FilterChip(
            label: const Text('Sadece tamamlanmayanlar'),
            selected: _sadeceEksik,
            onSelected: (v) => setState(() => _sadeceEksik = v),
          ),
          FilterChip(
            label: const Text('E-Defter aylık'),
            selected: _fAylik,
            onSelected: (v) => setState(() => _fAylik = v),
          ),
          FilterChip(
            label: const Text('Personeli olanlar'),
            selected: _fPersonelli,
            onSelected: (v) => setState(() => _fPersonelli = v),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _ara,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Firma ara',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _ara.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _ara.clear())),
              ),
            ),
          ),
        ]),
      ),
      if (_secimModu)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${_secili.length} firma seçili', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextButton(onPressed: () => setState(() => _secili..clear()..addAll(firmalar.map((f) => f.id))), child: const Text('Görünenlerin hepsini seç')),
            TextButton(onPressed: () => setState(_secili.clear), child: const Text('Seçimi temizle')),
            PopupMenuButton<String>(
              enabled: _secili.isNotEmpty,
              tooltip: 'Seçili firmalarda onayla',
              onSelected: (t) => _seciliIsle(t, true),
              itemBuilder: (c) => [for (final t in turlar) PopupMenuItem(value: t, child: Text(_sutunAdi(t)))],
              child: Chip(avatar: const Icon(Icons.check, size: 16), label: const Text('Seçililer için onayla ▾'), backgroundColor: _secili.isEmpty ? Colors.black12 : const Color(0xFFD7EBD8)),
            ),
            PopupMenuButton<String>(
              enabled: _secili.isNotEmpty,
              tooltip: 'Seçili firmalarda işareti kaldır',
              onSelected: (t) => _seciliIsle(t, false),
              itemBuilder: (c) => [for (final t in turlar) PopupMenuItem(value: t, child: Text(_sutunAdi(t)))],
              child: Chip(avatar: const Icon(Icons.undo, size: 16), label: const Text('İşareti kaldır ▾'), backgroundColor: _secili.isEmpty ? Colors.black12 : const Color(0xFFF6DADA)),
            ),
          ]),
        ),
      if (_cevrilmeli.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFB3261E)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${_cevrilmeli.length} firmanın personeli kalmadı, üç aylığa çevrilmesi gerekiyor.',
                  style: const TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      if (_hata != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(_hata!, style: const TextStyle(color: Color(0xFFB3261E)))),
      Expanded(
        child: firmalar.isEmpty
            ? Center(child: Text(tum.isEmpty ? 'Henüz firma yok. Firmalar bölümünden firma ekle.' : 'Tüm beyannameler tamamlanmış.'))
            : LayoutBuilder(builder: (context, kisit) {
                // Sütun genişlikleri; ekran genişse orantılı büyür, darsa yatay kaydırma çıkar
                final temel = <double>[44, 210, for (final t in turlar) t == _edefter ? 200 : 165];
                final topTemel = temel.fold<double>(0, (a, b) => a + b);
                final oran = kisit.maxWidth > topTemel ? kisit.maxWidth / topTemel : (kisit.maxWidth / topTemel < 0.88 ? 0.88 : kisit.maxWidth / topTemel);
                final w = [for (final x in temel) x * oran];
                final genel = w.fold<double>(0, (a, b) => a + b);

                Widget kutu(int i, Widget c, {Alignment hiza = Alignment.centerLeft}) =>
                    SizedBox(width: w[i], child: Align(alignment: hiza, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c)));

                // Başlık satırı sabit kalır; yalnızca firma satırları aşağı kayar
                final baslik = Container(
                  height: 112,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade500, width: 1.4)),
                    boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 2))],
                  ),
                  child: Row(children: [
                    kutu(0, const Text('No', style: TextStyle(fontWeight: FontWeight.w700))),
                    kutu(1, const Text('Firma', style: TextStyle(fontWeight: FontWeight.w700))),
                    for (var i = 0; i < turlar.length; i++) kutu(i + 2, _sutunBasligi(turlar[i])),
                  ]),
                );

                return Scrollbar(
                  controller: _yatay,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                  controller: _yatay,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: genel,
                    child: Column(children: [
                      baslik,
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: firmalar.length,
                          itemBuilder: (c, i) {
                            final f = firmalar[i];
                            return _KontrolSatiri(
                              yukseklik: 60,
                              zemin: i.isEven ? Colors.white : const Color(0xFFE6E6E6),
                              children: [
                                kutu(
                                    0,
                                    _secimModu
                                        ? SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: Checkbox(
                                              visualDensity: VisualDensity.compact,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              value: _secili.contains(f.id),
                                              onChanged: (v) => setState(() => v == true ? _secili.add(f.id) : _secili.remove(f.id)),
                                            ),
                                          )
                                        : Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
                                SizedBox(
                                  width: w[1],
                                  child: InkWell(
                                    onTap: () {
                                      seciliFirmaId.value = f.id;
                                      bolumIstegi.value = 'Beyannameler';
                                    },
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Row(children: [
                                          Expanded(child: Text(f.unvan, overflow: TextOverflow.ellipsis, maxLines: 2)),
                                          if (f.not.isNotEmpty)
                                            Tooltip(
                                              message: f.not,
                                              child: const Padding(
                                                padding: EdgeInsets.only(left: 4),
                                                child: Icon(Icons.sticky_note_2_outlined, size: 17, color: Color(0xFFEF6C00)),
                                              ),
                                            ),
                                          InkWell(
                                            onTap: () => _firmaMesaj(f),
                                            child: const Tooltip(
                                              message: 'Not ve WhatsApp mesajı',
                                              child: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.chat_bubble_outline, size: 16, color: Colors.black87)),
                                            ),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                                for (var k = 0; k < turlar.length; k++) kutu(k + 2, _hucre(f, turlar[k])),
                              ],
                            );
                          },
                        ),
                      ),
                    ]),
                  ),
                  ),
                );
              }),
      ),
    ]);
  }
}

/// Kontrol listesi satırı: zebra rengi ve fare üzerine gelince sarı vurgu
class _KontrolSatiri extends StatefulWidget {
  final double yukseklik;
  final Color zemin;
  final List<Widget> children;
  const _KontrolSatiri({required this.yukseklik, required this.zemin, required this.children});
  @override
  State<_KontrolSatiri> createState() => _KontrolSatiriState();
}

class _KontrolSatiriState extends State<_KontrolSatiri> {
  bool _uzerinde = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _uzerinde = true),
        onExit: (_) => setState(() => _uzerinde = false),
        child: Container(
          height: widget.yukseklik,
          decoration: BoxDecoration(
            color: _uzerinde ? const Color(0xFFFFE680) : widget.zemin,
            border: Border(bottom: BorderSide(color: Colors.grey.shade400, width: 1.2)),
          ),
          child: Row(children: widget.children),
        ),
      );
}
