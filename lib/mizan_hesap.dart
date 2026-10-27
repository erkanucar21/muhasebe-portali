import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Mizandaki bir ana hesap (3 haneli). [net] borç bakiyesi pozitif, alacak bakiyesi negatif.
class MizanSatir {
  final String kod, ad;
  final double net;
  const MizanSatir(this.kod, this.ad, this.net);
  Map<String, dynamic> toJson() => {'k': kod, 'a': ad, 'n': net};
  factory MizanSatir.fromJson(Map<String, dynamic> m) => MizanSatir(m['k'] as String, m['a'] as String, (m['n'] as num).toDouble());
}

class Mizan {
  final String unvan, donem, aralik;
  final List<MizanSatir> satirlar;
  const Mizan({required this.unvan, required this.donem, required this.aralik, required this.satirlar});

  List<DateTime> get _tarihler {
    final kaynak = aralik.trim().isNotEmpty ? aralik : donem;
    return [
      for (final m in RegExp(r'(\d{1,2})[/.](\d{1,2})[/.](\d{4})').allMatches(kaynak))
        DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)),
    ];
  }

  DateTime? get bas => _tarihler.isEmpty ? null : _tarihler.first;
  DateTime? get son => _tarihler.length < 2 ? null : _tarihler.last;

  /// Mizanın kapsadığı gün sayısı (tarih aralığı okunamazsa 365).
  int get gun => (bas != null && son != null) ? son!.difference(bas!).inDays + 1 : 365;

  Map<String, dynamic> toJson() => {'unvan': unvan, 'donem': donem, 'aralik': aralik, 'satirlar': [for (final s in satirlar) s.toJson()]};
  factory Mizan.fromJson(Map<String, dynamic> m) => Mizan(
        unvan: (m['unvan'] ?? '') as String,
        donem: (m['donem'] ?? '') as String,
        aralik: (m['aralik'] ?? '') as String,
        satirlar: [for (final s in (m['satirlar'] as List)) MizanSatir.fromJson(Map<String, dynamic>.from(s as Map))],
      );
}

// ------------------------------------------------------------------ dosya okuma
String _coz(String s) => s
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _norm(String s) {
  const m = {'İ': 'I', 'ı': 'I', 'i': 'I', 'Ş': 'S', 'ş': 'S', 'Ğ': 'G', 'ğ': 'G', 'Ü': 'U', 'ü': 'U', 'Ö': 'O', 'ö': 'O', 'Ç': 'C', 'ç': 'C'};
  final sb = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final x = m[ch] ?? ch.toUpperCase();
    if (RegExp(r'^[A-Z0-9]$').hasMatch(x)) sb.write(x);
  }
  return sb.toString();
}

int _kolon(String harf) {
  var n = 0;
  for (final c in harf.codeUnits) {
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

double? _sayi(String s) {
  var t = s.trim();
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

List<List<String>> _xlsxSatirlar(Uint8List b) {
  final z = ZipDecoder().decodeBytes(b);
  ArchiveFile? bul(String ad) {
    for (final f in z.files) {
      if (f.name == ad) return f;
    }
    return null;
  }

  String metin(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

  final paylasilan = <String>[];
  final ss = bul('xl/sharedStrings.xml');
  if (ss != null) {
    for (final m in RegExp(r'<si(?:\s[^>]*)?(?:/>|>(.*?)</si>)', dotAll: true).allMatches(metin(ss))) {
      final sb = StringBuffer();
      for (final t in RegExp(r'<t(?:\s[^>]*)?>(.*?)</t>', dotAll: true).allMatches(m.group(1) ?? '')) {
        sb.write(_coz(t.group(1)!));
      }
      paylasilan.add(sb.toString());
    }
  }
  var sayfa = bul('xl/worksheets/sheet1.xml');
  if (sayfa == null) {
    final adaylar = z.files.where((f) => f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')).toList()..sort((a, b) => a.name.compareTo(b.name));
    if (adaylar.isEmpty) throw 'Excel dosyasında çalışma sayfası bulunamadı.';
    sayfa = adaylar.first;
  }
  final xml = metin(sayfa);
  final satirlar = <List<String>>[];
  for (final r in RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true).allMatches(xml)) {
    final govde = r.group(1) ?? '';
    final hucre = <int, String>{};
    var enBuyuk = -1;
    for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(govde)) {
      final at = c.group(1) ?? '';
      final ic = c.group(2) ?? '';
      final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(at);
      if (ref == null) continue;
      final col = _kolon(ref.group(1)!);
      final tip = RegExp(r'\bt="([^"]*)"').firstMatch(at)?.group(1) ?? '';
      var deger = '';
      if (tip == 'inlineStr') {
        final sb = StringBuffer();
        for (final t in RegExp(r'<t(?:\s[^>]*)?>(.*?)</t>', dotAll: true).allMatches(ic)) {
          sb.write(_coz(t.group(1)!));
        }
        deger = sb.toString();
      } else {
        final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(ic)?.group(1);
        if (v != null) {
          if (tip == 's') {
            final i = int.tryParse(v) ?? -1;
            deger = (i >= 0 && i < paylasilan.length) ? paylasilan[i] : '';
          } else {
            deger = _coz(v);
          }
        }
      }
      hucre[col] = deger;
      enBuyuk = math.max(enBuyuk, col);
    }
    satirlar.add([for (var i = 0; i <= enBuyuk; i++) hucre[i] ?? '']);
  }
  return satirlar;
}

List<List<String>> _csvSatirlar(String metin) {
  final satirlar = metin.split(RegExp(r'\r?\n')).where((s) => s.trim().isNotEmpty).toList();
  if (satirlar.isEmpty) return [];
  final ayrac = ';'.allMatches(satirlar.join('\n')).length >= ','.allMatches(satirlar.join('\n')).length ? ';' : ',';
  List<String> bol(String s) {
    final r = <String>[];
    final sb = StringBuffer();
    var tirnak = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') {
        tirnak = !tirnak;
      } else if (c == ayrac && !tirnak) {
        r.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
    r.add(sb.toString());
    return r;
  }

  return [for (final s in satirlar) bol(s)];
}

/// Excel (.xlsx) veya CSV mizanını okur. Yalnızca 3 haneli ana hesapları alır;
/// alt hesaplar (100.01 gibi) ana hesaba toplanır, ana hesap satırı yoksa oradan türetilir.
Mizan mizanOku(Uint8List bayt) {
  final xlsx = bayt.length > 3 && bayt[0] == 0x50 && bayt[1] == 0x4B;
  final satirlar = xlsx ? _xlsxSatirlar(bayt) : _csvSatirlar(utf8.decode(bayt, allowMalformed: true));
  final basIdx = satirlar.indexWhere((r) => r.isNotEmpty && _norm(r[0]).contains('HESAPKODU'));
  if (basIdx < 0) {
    throw 'Başlık satırı ("HESAP KODU") bulunamadı. Mizan; Hesap Kodu, Hesap Adı, Borç, Alacak, Borç Bakiyesi ve Alacak Bakiyesi sütunlarını içermelidir.';
  }
  final baslik = satirlar[basIdx];
  int kolon(String anahtar, int yedek) {
    for (var i = 0; i < baslik.length; i++) {
      if (_norm(baslik[i]) == anahtar) return i;
    }
    return yedek;
  }

  final kAd = kolon('HESAPADI', 1), kBb = kolon('BORCBAKIYESI', 5), kAb = kolon('ALACAKBAKIYESI', 6);
  String hucre(List<String> r, int i) => i < r.length ? r[i] : '';

  var unvan = '', donem = '', aralik = '';
  for (var i = 0; i < basIdx; i++) {
    final r = satirlar[i];
    final ilk = r.isEmpty ? '' : r[0].trim();
    if (ilk.isEmpty) continue;
    final n = _norm(ilk);
    final deger = hucre(r, 1).trim();
    if (n.contains('TARIHARALIGI')) {
      aralik = deger;
    } else if (n.startsWith('DONEM')) {
      donem = deger;
    } else if (n != 'MIZAN' && unvan.isEmpty && deger.isEmpty) {
      unvan = ilk;
    }
  }

  final tam = <String, MizanSatir>{};
  final alt = <String, double>{};
  for (var i = basIdx + 1; i < satirlar.length; i++) {
    final r = satirlar[i];
    final kod = r.isEmpty ? '' : r[0].trim();
    if (kod.isEmpty || _norm(kod).startsWith('GENELTOPLAM')) continue;
    final net = (_sayi(hucre(r, kBb)) ?? 0) - (_sayi(hucre(r, kAb)) ?? 0);
    if (RegExp(r'^\d{3}$').hasMatch(kod)) {
      tam[kod] = MizanSatir(kod, hucre(r, kAd).trim(), net);
    } else {
      final m = RegExp(r'^(\d{3})\D').firstMatch(kod);
      if (m != null) alt[m.group(1)!] = (alt[m.group(1)!] ?? 0) + net;
    }
  }
  for (final e in alt.entries) {
    tam.putIfAbsent(e.key, () => MizanSatir(e.key, 'Hesap ${e.key}', e.value));
  }
  if (tam.isEmpty) throw 'Dosyada 3 haneli hesap kodu satırı bulunamadı.';
  final liste = tam.values.toList()..sort((a, b) => a.kod.compareTo(b.kod));
  return Mizan(unvan: unvan, donem: donem, aralik: aralik, satirlar: liste);
}

// ------------------------------------------------------------------ hesaplar
class MizanOzet {
  final double donen, duran, aktif, hazir, ticariAlacak, stok, ticariBorc, kv, uv, ozk;
  final double brutSatis, indirim, netSatis, smm, brutKar, faalGider, faalKar, diger, sonuc;
  const MizanOzet({
    required this.donen,
    required this.duran,
    required this.aktif,
    required this.hazir,
    required this.ticariAlacak,
    required this.stok,
    required this.ticariBorc,
    required this.kv,
    required this.uv,
    required this.ozk,
    required this.brutSatis,
    required this.indirim,
    required this.netSatis,
    required this.smm,
    required this.brutKar,
    required this.faalGider,
    required this.faalKar,
    required this.diger,
    required this.sonuc,
  });

  /// Aktif toplamı ile pasif toplamı arasındaki fark (0 olmalı).
  double get denge => aktif - (kv + uv + ozk);
}

MizanOzet mizanOzetle(Mizan m) {
  double topla(String onek) {
    var t = 0.0;
    for (final s in m.satirlar) {
      if (s.kod.startsWith(onek)) t += s.net;
    }
    return t;
  }

  final donen = topla('1'), duran = topla('2');
  final brut = -topla('60'), indirim = topla('61');
  final netSatis = brut - indirim;
  final smm = topla('62');
  final brutKar = netSatis - smm;
  final faalGider = topla('63');
  final faalKar = brutKar - faalGider;
  final sonuc = -topla('6');
  return MizanOzet(
    donen: donen,
    duran: duran,
    aktif: donen + duran,
    hazir: topla('10'),
    ticariAlacak: topla('12'),
    stok: topla('15'),
    ticariBorc: -topla('32'),
    kv: -topla('3'),
    uv: -topla('4'),
    ozk: -topla('5') - topla('6'),
    brutSatis: brut,
    indirim: indirim,
    netSatis: netSatis,
    smm: smm,
    brutKar: brutKar,
    faalGider: faalGider,
    faalKar: faalKar,
    diger: sonuc - faalKar,
    sonuc: sonuc,
  );
}

class Gosterge {
  final String anahtar, ad, birim, aciklama;
  final double? deger;
  const Gosterge(this.anahtar, this.ad, this.deger, this.birim, this.aciklama);
}

double? _bol(double a, double b) => b > 0 ? a / b : null;

List<Gosterge> mizanGostergeleri(MizanOzet o, int gun) {
  double? yuzde(double? v) => v == null ? null : v * 100;
  return [
    Gosterge('cari', 'Cari oran', _bol(o.donen, o.kv), 'x', 'Dönen varlıklar / kısa vadeli yabancı kaynaklar'),
    Gosterge('asit', 'Asit-test oranı', _bol(o.donen - o.stok, o.kv), 'x', '(Dönen varlıklar - stoklar) / kısa vadeli yabancı kaynaklar'),
    Gosterge('nakit', 'Nakit oranı', _bol(o.hazir, o.kv), 'x', 'Hazır değerler / kısa vadeli yabancı kaynaklar'),
    Gosterge('isl', 'Net işletme sermayesi', o.donen - o.kv, 'TL', 'Dönen varlıklar - kısa vadeli yabancı kaynaklar'),
    Gosterge('borcluluk', 'Borçluluk oranı', yuzde(_bol(o.kv + o.uv, o.aktif)), '%', 'Toplam yabancı kaynak / toplam varlık'),
    Gosterge('ozkOran', 'Özkaynak oranı', yuzde(_bol(o.ozk, o.aktif)), '%', 'Özkaynak / toplam varlık (dönem sonucu dahil)'),
    Gosterge('kaldirac', 'Finansal kaldıraç', _bol(o.kv + o.uv, o.ozk), 'x', 'Toplam yabancı kaynak / özkaynak'),
    Gosterge('alacakGun', 'Alacak tahsil süresi', o.netSatis > 0 ? o.ticariAlacak / o.netSatis * gun : null, 'gün', 'Ticari alacaklar / net satışlar x dönem günü (yaklaşık)'),
    Gosterge('stokGun', 'Stok devir süresi', o.smm > 0 ? o.stok / o.smm * gun : null, 'gün', 'Stoklar / satışların maliyeti x dönem günü (yaklaşık)'),
    Gosterge('borcGun', 'Ticari borç ödeme süresi', o.smm > 0 ? o.ticariBorc / o.smm * gun : null, 'gün', 'Ticari borçlar / satışların maliyeti x dönem günü (alış verisi olmadığından yaklaşık)'),
    Gosterge('brutMarj', 'Brüt kâr marjı', yuzde(_bol(o.brutKar, o.netSatis)), '%', 'Brüt kâr / net satışlar'),
    Gosterge('faalMarj', 'Faaliyet kâr marjı', yuzde(_bol(o.faalKar, o.netSatis)), '%', 'Faaliyet kârı / net satışlar'),
    Gosterge('netMarj', 'Net kâr marjı', yuzde(_bol(o.sonuc, o.netSatis)), '%', 'Dönem sonucu / net satışlar'),
    Gosterge('giderOran', 'Faaliyet gider oranı', yuzde(_bol(o.faalGider, o.netSatis)), '%', 'Faaliyet giderleri / net satışlar'),
  ];
}

/// Karşılaştırma için tüm sayısal değerler.
Map<String, double?> mizanDegerleri(MizanOzet o, int gun) => {
      for (final g in mizanGostergeleri(o, gun)) g.anahtar: g.deger,
      'aktif': o.aktif,
      'hazir': o.hazir,
      'ticariAlacak': o.ticariAlacak,
      'stok': o.stok,
      'kv': o.kv,
      'ozk': o.ozk,
      'netSatis': o.netSatis,
      'sonuc': o.sonuc,
    };

String mizanTl(double v, {int ondalik = 2}) {
  final neg = v < 0 && v.abs() >= 0.5 * math.pow(10, -ondalik);
  final s = v.abs().toStringAsFixed(ondalik);
  final p = s.split('.');
  final ip = p[0];
  final sb = StringBuffer();
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) sb.write('.');
    sb.write(ip[i]);
  }
  return '${neg ? '-' : ''}$sb${ondalik > 0 ? ',${p[1]}' : ''}';
}

String gostergeMetni(Gosterge g) {
  final v = g.deger;
  if (v == null) return '-';
  switch (g.birim) {
    case 'x':
      return mizanTl(v);
    case '%':
      return '%${mizanTl(v, ondalik: 1)}';
    case 'gün':
      return '${mizanTl(v, ondalik: 0)} gün';
    default:
      return mizanTl(v);
  }
}

/// Yalnızca sayıya dayanan, değer yargısı içermeyen yorum cümleleri.
List<String> mizanYorumlari(Mizan m, MizanOzet o, int gun, {Mizan? onceki, MizanOzet? oncekiOzet}) {
  final g = {for (final x in mizanGostergeleri(o, gun)) x.anahtar: x};
  final y = <String>[];
  final cari = g['cari']!.deger;
  if (cari != null) {
    y.add('Cari oran ${mizanTl(cari)}: dönen varlıklar kısa vadeli yabancı kaynakların ${cari >= 1 ? 'üzerinde, yani kısa vadeli borçlar dönen varlıklarla karşılanabiliyor' : 'altında, yani kısa vadeli borçlar dönen varlıkların üzerinde'}.');
  }
  y.add('Net işletme sermayesi ${mizanTl(o.donen - o.kv)} TL (${o.donen - o.kv >= 0 ? 'pozitif' : 'negatif'}).');
  final borc = g['borcluluk']!.deger;
  if (borc != null) y.add('Varlıkların %${mizanTl(borc, ondalik: 1)} kadarı yabancı kaynaklarla finanse edilmiştir.');
  if (o.netSatis > 0) {
    y.add('Dönem sonucu ${mizanTl(o.sonuc.abs())} TL ${o.sonuc >= 0 ? 'kâr' : 'zarar'}; net satışların %${mizanTl(o.sonuc.abs() / o.netSatis * 100, ondalik: 1)}\'i.');
  } else {
    y.add('Dönem sonucu ${mizanTl(o.sonuc.abs())} TL ${o.sonuc >= 0 ? 'kâr' : 'zarar'}.');
  }
  final ag = g['alacakGun']!.deger, sg = g['stokGun']!.deger, bg = g['borcGun']!.deger;
  if (ag != null || sg != null || bg != null) {
    y.add([
      if (ag != null) 'Ticari alacaklar yaklaşık ${mizanTl(ag, ondalik: 0)} günlük satışa',
      if (sg != null) 'stoklar yaklaşık ${mizanTl(sg, ondalik: 0)} günlük maliyete',
      if (bg != null) 'ticari borçlar yaklaşık ${mizanTl(bg, ondalik: 0)} günlük maliyete',
    ].join(', ') + ' karşılık gelmektedir.');
  }
  if (onceki != null && oncekiOzet != null) {
    String degisim(String ad, double simdi, double once) {
      if (once.abs() < 0.01) return '';
      final p = (simdi - once) / once.abs() * 100;
      return '$ad önceki mizana göre %${mizanTl(p.abs(), ondalik: 1)} ${p >= 0 ? 'arttı' : 'azaldı'}.';
    }

    for (final s in [
      degisim('Toplam varlıklar', o.aktif, oncekiOzet.aktif),
      degisim('Ticari alacaklar', o.ticariAlacak, oncekiOzet.ticariAlacak),
      degisim('Stoklar', o.stok, oncekiOzet.stok),
      degisim('Hazır değerler', o.hazir, oncekiOzet.hazir),
      degisim('Özkaynaklar', o.ozk, oncekiOzet.ozk),
    ]) {
      if (s.isNotEmpty) y.add(s);
    }
  }
  return y;
}
