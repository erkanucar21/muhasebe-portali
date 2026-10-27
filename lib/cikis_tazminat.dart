import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_hesap.dart';
import 'personel_takip.dart';
import 'tazminat.dart' show kidemTavani;

class CikisHesabi {
  final double maasNet; // çıkış ayının bordro neti
  final double kidemBrut, kidemDamga, ihbarBrut, ihbarGv, ihbarDamga;
  final int ihbarHafta;
  final String? not;
  final AyBordro? bordro; // çıkış ayı bordrosu
  final int gelmediGun;
  final double brut, tavan, esas; // tam aylık brüt, kıdem tavanı, kıdem esas ücreti
  final String sure;
  final bool kidemVar;
  const CikisHesabi({
    this.maasNet = 0,
    this.kidemBrut = 0,
    this.kidemDamga = 0,
    this.ihbarBrut = 0,
    this.ihbarGv = 0,
    this.ihbarDamga = 0,
    this.ihbarHafta = 0,
    this.not,
    this.bordro,
    this.gelmediGun = 0,
    this.brut = 0,
    this.tavan = 0,
    this.esas = 0,
    this.sure = '',
    this.kidemVar = false,
  });
  double get kidemNet => kidemBrut - kidemDamga;
  double get ihbarNet => ihbarBrut - ihbarGv - ihbarDamga;
  double get tazminatNet => kidemNet + ihbarNet;
  double get toplamNet => maasNet + tazminatNet;
}

/// Personelin çıkış ayı bordrosunu (devamsızlık dahil) hesaplar; istenirse kıdem ve ihbar tazminatını ekler.
/// Kıdem: yalnızca damga vergisi. İhbar: gelir vergisi ve damga vergisi. İkisinde de SGK yok.
Future<CikisHesabi> cikisHesapla(Personel p, DateTime cikis, {required bool kidem, required bool ihbar}) async {
  final param = bordroParam(cikis.year);
  if (param == null) return CikisHesabi(not: '${cikis.year} yılı bordro parametresi tanımlı değil.');
  final gelmedi = <int, int>{};
  try {
    final r = await Supabase.instance.client
        .from('izin_kayitlari')
        .select('tarih')
        .eq('personel_id', p.id)
        .eq('durum', 'gelmedi')
        .gte('tarih', '${cikis.year}-01-01')
        .lte('tarih', '${cikis.year}-12-31');
    for (final m in r as List) {
      final t = DateTime.parse((m as Map)['tarih'] as String);
      if (t.month <= cikis.month) gelmedi[t.month] = (gelmedi[t.month] ?? 0) + 1;
    }
  } catch (_) {}
  final liste = yillikBordro(
    param,
    BordroGirdi(ucret: p.ucret, net: p.maasTuru != 'brut', asgari: p.asgari, giris: p.giris, cikis: cikis),
    cikis.month,
    gelmedi: gelmedi,
  );
  AyBordro? son;
  for (final b in liste) {
    if (b.ay == cikis.month && b.gun > 0) son = b;
  }
  if (son == null) return const CikisHesabi(not: 'Çıkış ayında bordro oluşmuyor (giriş veya çıkış tarihini kontrol et).');
  final tamBrut = son.gun >= 30 ? son.brut : kurus(son.brut * 30 / son.gun);

  final s = DateTime(cikis.year, cikis.month, cikis.day + 1);
  var y = s.year - p.giris.year, m = s.month - p.giris.month, g = s.day - p.giris.day;
  if (g < 0) {
    m -= 1;
    g += DateTime(s.year, s.month, 0).day;
  }
  if (m < 0) {
    y -= 1;
    m += 12;
  }
  final toplamAy = y * 12 + m;
  final tavan = kidemTavani(cikis);
  final esas = tamBrut < tavan ? tamBrut : tavan;
  final kBrut = kidem && toplamAy >= 12 ? kurus(esas * (y + m / 12 + g / 365)) : 0.0;
  final kDamga = kurus(kBrut * damgaOrani);
  final hafta = toplamAy < 6 ? 2 : (toplamAy < 18 ? 4 : (toplamAy < 36 ? 6 : 8));
  final iBrut = ihbar ? kurus(tamBrut / 30 * 7 * hafta) : 0.0;
  final kum = liste.last.kumMatrah;
  final iGv = iBrut > 0 ? kurus(gelirVergisiTarife(param, kum + iBrut) - gelirVergisiTarife(param, kum)) : 0.0;
  final iDamga = kurus(iBrut * damgaOrani);
  String? not;
  if (kidem && toplamAy < 12) not = 'Çalışma süresi 1 yıldan az: kıdem tazminatı hesaplanmadı.';
  return CikisHesabi(
    maasNet: son.net,
    kidemBrut: kBrut,
    kidemDamga: kDamga,
    ihbarBrut: iBrut,
    ihbarGv: iGv,
    ihbarDamga: iDamga,
    ihbarHafta: ihbar ? hafta : 0,
    not: not,
    bordro: son,
    gelmediGun: gelmedi[cikis.month] ?? 0,
    brut: tamBrut,
    tavan: tavan,
    esas: esas,
    sure: '$y yıl $m ay $g gün',
    kidemVar: kidem && toplamAy >= 12,
  );
}

/// Hesabı seçili ayın bordrosuna yazar (varsa üzerine yazar).
Future<void> cikisBordroyaYansit(Personel p, DateTime cikis, CikisHesabi h) async {
  await Supabase.instance.client.from('bordro_tazminat').upsert({
    'personel_id': p.id,
    'yil': cikis.year,
    'ay': cikis.month,
    'kidem_brut': h.kidemBrut,
    'kidem_damga': h.kidemDamga,
    'ihbar_brut': h.ihbarBrut,
    'ihbar_gv': h.ihbarGv,
    'ihbar_damga': h.ihbarDamga,
    'guncelleme': DateTime.now().toUtc().toIso8601String(),
  }, onConflict: 'personel_id,yil,ay');
}
