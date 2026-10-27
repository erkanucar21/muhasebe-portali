/// Bordro hesap motoru (saf Dart, ekran bağımsız).
///
/// Ücretli çalışan için aylık bordro: SGK ve işsizlik işçi payı, kümülatif gelir vergisi,
/// asgari ücret gelir vergisi ve damga vergisi istisnası, net ödenecek ve işveren maliyeti.
/// Net maaştan brüte geri hesap (kümülatif matrahla) desteklenir.
///
/// Yıllık parametreler aşağıdaki tabloda tutulur. Her yılbaşında güncellenmelidir.
/// Kaynak: Cott Group "Yılı İçin Bordrodaki Yasal Kesintiler" özetleri (2025, 2026).
library;

class YilParam {
  final int yil;
  final double sgkTaban; // aylık prime esas kazanç alt sınırı (= brüt asgari ücret)
  final double sgkTavan; // aylık prime esas kazanç üst sınırı
  final double asgariBrut; // aylık brüt asgari ücret
  final double damgaIstisna; // aylık damga vergisi istisnası
  final double isverenSgk; // işveren SGK payı (indirim öncesi)
  final double isverenIssizlik;
  final int varsayilanIndirim; // 5510 işveren SGK indirimi, puan
  final List<(double, double)> dilimler; // (üst sınır, oran)
  const YilParam({
    required this.yil,
    required this.sgkTaban,
    required this.sgkTavan,
    required this.asgariBrut,
    required this.damgaIstisna,
    required this.isverenSgk,
    required this.isverenIssizlik,
    required this.varsayilanIndirim,
    required this.dilimler,
  });

  YilParam copyWithYil(int y) => YilParam(
        yil: y,
        sgkTaban: sgkTaban,
        sgkTavan: sgkTavan,
        asgariBrut: asgariBrut,
        damgaIstisna: damgaIstisna,
        isverenSgk: isverenSgk,
        isverenIssizlik: isverenIssizlik,
        varsayilanIndirim: varsayilanIndirim,
        dilimler: dilimler,
      );

  Map<String, dynamic> toJson() => {
        'sgkTaban': sgkTaban,
        'sgkTavan': sgkTavan,
        'asgariBrut': asgariBrut,
        'damgaIstisna': damgaIstisna,
        'isverenSgk': isverenSgk,
        'isverenIssizlik': isverenIssizlik,
        'varsayilanIndirim': varsayilanIndirim,
        'dilimler': [for (final (u, o) in dilimler) [u, o]],
      };

  factory YilParam.fromJson(int yil, Map<String, dynamic> m) => YilParam(
        yil: yil,
        sgkTaban: (m['sgkTaban'] as num).toDouble(),
        sgkTavan: (m['sgkTavan'] as num).toDouble(),
        asgariBrut: (m['asgariBrut'] as num).toDouble(),
        damgaIstisna: (m['damgaIstisna'] as num).toDouble(),
        isverenSgk: (m['isverenSgk'] as num).toDouble(),
        isverenIssizlik: (m['isverenIssizlik'] as num).toDouble(),
        varsayilanIndirim: (m['varsayilanIndirim'] as num).toInt(),
        dilimler: [for (final d in (m['dilimler'] as List)) ((d[0] as num).toDouble(), (d[1] as num).toDouble())],
      );
}

const double _inf = 1e18;
const double isciSgkOrani = 0.14;
const double isciIssizlikOrani = 0.01;
const double damgaOrani = 0.00759;

const _varsayilanParametreler = <int, YilParam>{
  2025: YilParam(
    yil: 2025,
    sgkTaban: 26005.50,
    sgkTavan: 195041.40,
    asgariBrut: 26005.50,
    damgaIstisna: 197.38,
    isverenSgk: 0.2075,
    isverenIssizlik: 0.02,
    varsayilanIndirim: 5,
    dilimler: [(158000.0, 0.15), (330000.0, 0.20), (1200000.0, 0.27), (4300000.0, 0.35), (_inf, 0.40)],
  ),
  2026: YilParam(
    yil: 2026,
    sgkTaban: 33030.00,
    sgkTavan: 297270.00,
    asgariBrut: 33030.00,
    damgaIstisna: 250.70,
    isverenSgk: 0.2175,
    isverenIssizlik: 0.02,
    varsayilanIndirim: 2,
    dilimler: [(190000.0, 0.15), (400000.0, 0.20), (1500000.0, 0.27), (5300000.0, 0.35), (_inf, 0.40)],
  ),
};

/// Veritabanından yüklenen değerler varsayılanların üzerine yazılır.
final Map<int, YilParam> _parametreler = Map.of(_varsayilanParametreler);

class ParamKaynak {
  final String kaynak, notlar;
  final DateTime? sonKontrol;
  const ParamKaynak(this.kaynak, this.notlar, this.sonKontrol);
}

final Map<int, ParamKaynak> paramKaynaklari = {};

void paramUygula(int yil, YilParam p, ParamKaynak k) {
  _parametreler[yil] = p;
  paramKaynaklari[yil] = k;
}

bool paramVarsayilanMi(int yil) => !paramKaynaklari.containsKey(yil);

YilParam? bordroParam(int yil) => _parametreler[yil];
List<int> bordroYillari() => _parametreler.keys.toList()..sort();

double kurus(double v) => (v * 100).roundToDouble() / 100;

/// Kümülatif matrah için yıllık gelir vergisi (tarife).
double gelirVergisiTarife(YilParam p, double matrah) {
  var kalan = matrah, alt = 0.0, vergi = 0.0;
  for (final (ust, oran) in p.dilimler) {
    if (kalan <= 0) break;
    final dilim = (ust - alt).clamp(0, double.infinity).toDouble();
    final kullan = kalan < dilim ? kalan : dilim;
    vergi += kullan * oran;
    kalan -= kullan;
    alt = ust;
  }
  return vergi;
}

class BordroGirdi {
  final double ucret; // personel kaydındaki maaş
  final bool net; // true: ucret net, false: brüt
  final bool asgari; // asgari ücretli
  final DateTime giris;
  final DateTime? cikis;
  const BordroGirdi({required this.ucret, required this.net, required this.asgari, required this.giris, this.cikis});
}

class AyBordro {
  final int ay;
  final int gun; // 30 günlük esasa göre çalışılan gün
  final double brut, sgkIsci, issizlikIsci, gvMatrah, kumMatrah, gvHesap, gvIstisna, gelirVergisi;
  final double damgaHesap, damgaIstisna, damga, net;
  final double sgkMatrah, isverenSgk, isverenIssizlik, maliyet;
  const AyBordro({
    required this.ay,
    required this.gun,
    this.brut = 0,
    this.sgkIsci = 0,
    this.issizlikIsci = 0,
    this.gvMatrah = 0,
    this.kumMatrah = 0,
    this.gvHesap = 0,
    this.gvIstisna = 0,
    this.gelirVergisi = 0,
    this.damgaHesap = 0,
    this.damgaIstisna = 0,
    this.damga = 0,
    this.net = 0,
    this.sgkMatrah = 0,
    this.isverenSgk = 0,
    this.isverenIssizlik = 0,
    this.maliyet = 0,
  });

  double get isciKesinti => sgkIsci + issizlikIsci + gelirVergisi + damga;
  double get isverenPayi => isverenSgk + isverenIssizlik;
}

/// Ay için çalışılan gün (30 günlük esas). Giriş/çıkış ay içindeyse orantılanır.
int calisilanGun(DateTime giris, DateTime? cikis, int yil, int ay) {
  final ilk = DateTime(yil, ay, 1);
  final sonGun = DateTime(yil, ay + 1, 0).day;
  final son = DateTime(yil, ay, sonGun);
  if (giris.isAfter(son)) return 0;
  if (cikis != null && cikis.isBefore(ilk)) return 0;
  var bas = giris.isBefore(ilk) ? 1 : giris.day;
  var bit = (cikis == null || cikis.isAfter(son)) ? sonGun : cikis.day;
  if (bit >= sonGun) bit = 30;
  if (bas > 30) bas = 30;
  return (bit - bas + 1).clamp(0, 30);
}

/// Seçili aya kadar (1..sonAy) personelin aylık bordrolarını kümülatif olarak hesaplar.
///
/// [gelmedi]: ay numarası -> o ayda işe gelmediği gün sayısı. Gelmediği günler maaştan düşer
/// (günlük ücret = maaş / 30) ve SGK prim günü o kadar azalır.
List<AyBordro> yillikBordro(YilParam p, BordroGirdi g, int sonAy,
    {int? indirimPuan, Map<int, int>? gelmedi}) {
  final indirim = (indirimPuan ?? p.varsayilanIndirim) / 100.0;
  final asgariMatrah = kurus(p.asgariBrut * (1 - isciSgkOrani - isciIssizlikOrani));
  final sonuc = <AyBordro>[];
  var kum = 0.0;

  for (var ay = 1; ay <= sonAy; ay++) {
    final gun = (calisilanGun(g.giris, g.cikis, p.yil, ay) - (gelmedi?[ay] ?? 0)).clamp(0, 30);
    if (gun == 0) {
      sonuc.add(AyBordro(ay: ay, gun: 0, kumMatrah: kum));
      continue;
    }
    final oran = gun / 30.0;
    final matrahAlt = p.sgkTaban * oran, matrahUst = p.sgkTavan * oran;
    final istisnaGv = gelirVergisiTarife(p, asgariMatrah * ay) - gelirVergisiTarife(p, asgariMatrah * (ay - 1));

    // Brüte göre tüm kalemleri hesaplar
    AyBordro hesap(double brut) {
      final sgkM = brut.clamp(matrahAlt, matrahUst).toDouble();
      final sgk = kurus(sgkM * isciSgkOrani);
      final iss = kurus(sgkM * isciIssizlikOrani);
      final gvM = kurus(brut - sgk - iss);
      final gvH = kurus(gelirVergisiTarife(p, kum + gvM) - gelirVergisiTarife(p, kum));
      final gvIst = kurus(istisnaGv);
      final gv = kurus((gvH - gvIst) < 0 ? 0 : gvH - gvIst);
      final dH = kurus(brut * damgaOrani);
      final dIst = p.damgaIstisna;
      final d = kurus((dH - dIst) < 0 ? 0 : dH - dIst);
      final net = kurus(brut - sgk - iss - gv - d);
      final isvSgk = kurus(sgkM * (p.isverenSgk - indirim));
      final isvIss = kurus(sgkM * p.isverenIssizlik);
      return AyBordro(
        ay: ay,
        gun: gun,
        brut: brut,
        sgkIsci: sgk,
        issizlikIsci: iss,
        gvMatrah: gvM,
        kumMatrah: kurus(kum + gvM),
        gvHesap: gvH,
        gvIstisna: gvH < gvIst ? gvH : gvIst,
        gelirVergisi: gv,
        damgaHesap: dH,
        damgaIstisna: dH < dIst ? dH : dIst,
        damga: d,
        net: net,
        sgkMatrah: sgkM,
        isverenSgk: isvSgk,
        isverenIssizlik: isvIss,
        maliyet: kurus(brut + isvSgk + isvIss),
      );
    }

    late AyBordro b;
    if (g.asgari) {
      b = hesap(kurus(p.asgariBrut * oran));
    } else if (!g.net) {
      b = hesap(kurus(g.ucret * oran));
    } else {
      // Net -> brüt: net, brütle artan bir fonksiyondur; ikili aramayla bulunur.
      final hedef = kurus(g.ucret * oran);
      var alt = 0.0, ust = hedef * 4 + 1000;
      for (var i = 0; i < 80; i++) {
        final orta = (alt + ust) / 2;
        if (hesap(orta).net < hedef) {
          alt = orta;
        } else {
          ust = orta;
        }
      }
      // Kuruş yuvarlamaları yüzünden net hedefi birkaç kuruş şaşabilir; en yakın brütü seç
      final taban = kurus(ust);
      b = hesap(taban);
      var fark = (b.net - hedef).abs();
      for (var c = -5; c <= 5; c++) {
        final aday = hesap(kurus(taban + c / 100));
        final f = (aday.net - hedef).abs();
        if (f < fark - 1e-9) {
          b = aday;
          fark = f;
        }
      }
    }
    kum = b.kumMatrah;
    sonuc.add(b);
  }
  return sonuc;
}
