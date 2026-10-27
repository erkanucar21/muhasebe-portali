import 'marka.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart';
import 'bordro_hesap.dart';
import 'firmalar.dart';
import 'personel_takip.dart';

/// Bir firmanın seçili ay bordrosunu PDF olarak hazırlar. Çalışan yoksa null.
Future<Uint8List?> firmaBordroPdf(Firma f, int yil, int ay) async {
  final param = bordroParam(yil);
  if (param == null) throw 'Bu yıl için bordro parametresi tanımlı değil';
  final db = Supabase.instance.client;
  final r = await db.from('personel').select().eq('firma_id', f.id);
  final personel = [for (final m in r as List) Personel.fromMap(m as Map<String, dynamic>)];
  final calisan = personel.where((k) => calisilanGun(k.giris, k.cikis, yil, ay) > 0).toList();
  if (calisan.isEmpty) return null;
  final ids = [for (final k in calisan) k.id];

  final gelmedi = <int, Map<int, int>>{};
  final bit = DateTime(yil, ay + 1, 0);
  for (var ofset = 0;; ofset += 1000) {
    final parca = await db
        .from('izin_kayitlari')
        .select('personel_id, tarih')
        .eq('durum', 'gelmedi')
        .inFilter('personel_id', ids)
        .gte('tarih', '$yil-01-01')
        .lte('tarih', '$yil-${ay.toString().padLeft(2, '0')}-${bit.day.toString().padLeft(2, '0')}')
        .order('tarih')
        .order('personel_id')
        .range(ofset, ofset + 999);
    for (final m in parca) {
      final t = DateTime.parse(m['tarih'] as String);
      final a = gelmedi.putIfAbsent(m['personel_id'] as int, () => {});
      a[t.month] = (a[t.month] ?? 0) + 1;
    }
    if (parca.length < 1000) break;
  }

  final taz = <int, List<double>>{};
  try {
    final t = await db.from('bordro_tazminat').select().eq('yil', yil).eq('ay', ay).inFilter('personel_id', ids);
    for (final m in t as List) {
      double n(String k) => ((m[k] ?? 0) as num).toDouble();
      taz[m['personel_id'] as int] = [n('kidem_brut') + n('ihbar_brut'), n('kidem_damga') + n('ihbar_gv') + n('ihbar_damga')];
    }
  } catch (_) {}

  final liste = <PersonelBordro>[];
  for (final k in calisan) {
    final dizi = yillikBordro(param, BordroGirdi(ucret: k.ucret, net: k.maasTuru != 'brut', asgari: k.asgari, giris: k.giris, cikis: k.cikis), ay,
        gelmedi: gelmedi[k.id]);
    liste.add(PersonelBordro(
      ad: k.ad,
      tc: k.tc,
      meslek: k.meslek,
      sgkSicil: k.sgkSicil,
      gelmedi: gelmedi[k.id]?[ay] ?? 0,
      giris: k.giris,
      cikis: k.cikis,
      asgari: k.asgari,
      netMaas: k.maasTuru != 'brut',
      kayitliMaas: k.ucret,
      b: dizi.last,
      tazBrut: k.cikis == null ? 0 : (taz[k.id]?[0] ?? 0),
      tazKesinti: k.cikis == null ? 0 : (taz[k.id]?[1] ?? 0),
    ));
  }
  liste.sort((a, b) => trKarsilastir(a.ad, b.ad));
  return bordroListePdf(
    liste,
    firma: FirmaBilgi(
      ad: f.unvan,
      adres: f.adres,
      sgkSicil: f.sgkSicilNo,
      sgkSube: f.sgkSubesi,
      vergiDairesi: f.vergiDairesi,
      vergiNo: f.vergiNo.isNotEmpty ? f.vergiNo : f.tcNo,
      mersis: f.mersisNo,
      ticaretSicil: f.ticaretSicilNo,
    ),
    yil: yil,
    ay: ay,
  );
}

String _ascii(String s) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosuCGIOSU';
  var r = s;
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
}

/// Seçili ayın bordrosunu mükelleflere e-postayla gönderme penceresi.
Future<void> bordroEpostaDialog(BuildContext context, int yil, int ay) async {
  final firmalar = FirmaDeposu.ornek.liste;
  final secili = <int>{for (final f in firmalar) if (f.eposta.contains('@')) f.id};
  final donem = '${bordroAylar[ay - 1]} $yil';
  final metin = TextEditingController(
    text: 'Sayın yetkili,\n\n$donem dönemi bordronuz ekte sunulmuştur.\nİyi çalışmalar dilerim.\n\n${marka.epostaImza}',
  );
  final sonuc = <int, String>{};
  var test = false, mesgul = false;
  String? hata;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: Text('Bordroyu e-postayla gönder: $donem'),
        content: SizedBox(
          width: 480,
          height: 520,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Her firmaya yalnızca kendi personelinin bordrosu (PDF) gider. E-posta adresi olmayan firmalar seçilemez.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            TextField(controller: metin, maxLines: 5, decoration: const InputDecoration(labelText: 'E-posta metni', border: OutlineInputBorder())),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: test,
              onChanged: mesgul ? null : (v) => setD(() => test = v ?? false),
              title: const Text('Deneme: e-postalar mükellefe değil kendi adresime gitsin'),
            ),
            Row(children: [
              TextButton(
                onPressed: mesgul ? null : () => setD(() => secili..clear()..addAll([for (final f in firmalar) if (f.eposta.contains('@')) f.id])),
                child: const Text('Tümünü seç'),
              ),
              TextButton(onPressed: mesgul ? null : () => setD(secili.clear), child: const Text('Temizle')),
              Text('${secili.length} firma'),
            ]),
            Expanded(
              child: ListView(children: [
                for (final f in firmalar)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: secili.contains(f.id),
                    onChanged: (mesgul || !f.eposta.contains('@')) ? null : (v) => setD(() => v == true ? secili.add(f.id) : secili.remove(f.id)),
                    title: Text(f.unvan),
                    subtitle: Text(sonuc[f.id] ?? (f.eposta.contains('@') ? f.eposta : 'E-posta adresi yok'),
                        style: TextStyle(fontSize: 12, color: (sonuc[f.id] ?? '').startsWith('Hata') ? Colors.red : null)),
                  ),
              ]),
            ),
            if (hata != null) Text(hata!, style: const TextStyle(color: Colors.red)),
          ]),
        ),
        actions: [
          TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Kapat')),
          FilledButton(
            onPressed: mesgul || secili.isEmpty
                ? null
                : () async {
                    setD(() {
                      mesgul = true;
                      hata = null;
                      sonuc.clear();
                    });
                    final db = Supabase.instance.client;
                    for (final f in firmalar.where((e) => secili.contains(e.id))) {
                      setD(() => sonuc[f.id] = 'Hazırlanıyor...');
                      try {
                        final pdf = await firmaBordroPdf(f, yil, ay);
                        if (pdf == null) {
                          setD(() => sonuc[f.id] = 'Atlandı: bu ay çalışan personel yok');
                          continue;
                        }
                        final r = await db.rpc('bordro_eposta_gonder', params: {
                          'p_firma_id': f.id,
                          'p_konu': 'Bordro $donem - ${f.unvan}',
                          'p_metin': metin.text,
                          'p_dosya_ad': 'bordro_${_ascii(f.unvan)}_$yil-${ay.toString().padLeft(2, '0')}.pdf',
                          'p_dosya_b64': base64Encode(pdf),
                          'p_test': test,
                        });
                        final durum = (r as Map)['durum'];
                        setD(() => sonuc[f.id] = durum == 'iletildi' ? 'Gönderildi' : 'Atlandı: ${r['neden'] ?? ''}');
                      } catch (e) {
                        setD(() => sonuc[f.id] = 'Hata: $e');
                      }
                    }
                    setD(() => mesgul = false);
                  },
            child: Text(mesgul ? 'Gönderiliyor...' : 'Gönder'),
          ),
        ],
      ),
    ),
  );
}
