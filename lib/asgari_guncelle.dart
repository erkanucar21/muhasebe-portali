import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart' show tl;
import 'firmalar.dart';
import 'maas_alani.dart';

/// Önceki yıllarda yürürlükte olmuş net asgari ücretler: bu tutarda maaşı olan ama "asgari ücretli" işaretlenmemiş personeli yakalamak için.
const _eskiAsgariler = [4253.40, 5500.35, 8506.80, 11402.32, 17002.12, 22104.67, 28075.50];

double? _sayi(String s) => double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

class _Aday {
  final int id;
  final String ad;
  final String firma;
  final double eski;
  final bool isaretli;
  _Aday(this.id, this.ad, this.firma, this.eski, this.isaretli);
}

/// Yeni net asgari ücreti girip asgari ücretli personelin maaşını toplu günceller.
Future<void> asgariGuncelleAc(BuildContext context) async {
  final db = Supabase.instance.client;
  final mesaj = ScaffoldMessenger.of(context);
  List<Map<String, dynamic>> satirlar;
  try {
    if (FirmaDeposu.ornek.liste.isEmpty) await FirmaDeposu.ornek.yukle();
    final r = await db.from('personel').select('id, ad, firma_id, ucret, asgari_ucretli, maas_turu, cikis').filter('cikis', 'is', null);
    satirlar = (r as List).cast<Map<String, dynamic>>();
  } catch (e) {
    mesaj.showSnackBar(SnackBar(content: Text('Personel okunamadı: $e')));
    return;
  }
  if (!context.mounted) return;

  final yeni = TextEditingController();
  final secili = <int>{};
  var hazir = false;
  List<_Aday> adaylar = [];
  String? hata;
  var mesgul = false;

  void hesapla(double y) {
    adaylar = [];
    for (final s in satirlar) {
      final ucret = ((s['ucret'] ?? 0) as num).toDouble();
      final isaretli = s['asgari_ucretli'] == true;
      final net = (s['maas_turu'] ?? 'net') == 'net';
      if ((ucret - y).abs() < 0.005) continue;
      final eskiyeEsit = net && _eskiAsgariler.any((a) => (a - ucret).abs() < 0.005);
      if (!isaretli && !eskiyeEsit) continue;
      final f = FirmaDeposu.ornek.bul((s['firma_id'] as num).toInt());
      adaylar.add(_Aday((s['id'] as num).toInt(), '${s['ad']}', f?.unvan ?? '', ucret, isaretli));
    }
    adaylar.sort((a, b) => a.firma.compareTo(b.firma) != 0 ? a.firma.compareTo(b.firma) : a.ad.compareTo(b.ad));
    secili
      ..clear()
      ..addAll(adaylar.map((a) => a.id));
  }

  final tamam = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Asgari ücret güncelle'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Yeni aylık net asgari ücreti yaz. "Asgari ücretli" işaretli personel ile maaşı önceki yılların asgari ücretine eşit olan personel listelenir; '
              'seçtiklerinin maaşı yeni tutara çekilir ve asgari ücretli olarak işaretlenir. Çıkış yapmış personele dokunulmaz.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: MaasAlani(controller: yeni, etiket: 'Yeni net asgari ücret (TL)', ipucu: '28.075,50')),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () {
                  final y = _sayi(yeni.text);
                  if (y == null || y <= 0) {
                    setD(() => hata = 'Geçerli bir tutar yaz');
                    return;
                  }
                  setD(() {
                    hata = null;
                    hesapla(y);
                    hazir = true;
                  });
                },
                child: const Text('Listele'),
              ),
            ]),
            if (hata != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(hata!, style: const TextStyle(color: Colors.red))),
            if (hazir) ...[
              const Divider(),
              if (adaylar.isEmpty)
                const Text('Güncellenecek personel bulunamadı.')
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(children: [
                      for (final a in adaylar)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: secili.contains(a.id),
                          onChanged: (v) => setD(() => v == true ? secili.add(a.id) : secili.remove(a.id)),
                          title: Text('${a.firma} - ${a.ad}', overflow: TextOverflow.ellipsis),
                          subtitle: Text('${tl(a.eski)} → ${tl(_sayi(yeni.text) ?? 0)} TL${a.isaretli ? '' : '  (işaretli değildi, eski asgari ücrete eşit)'}'),
                        ),
                    ]),
                  ),
                ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: mesgul || !hazir || secili.isEmpty
                ? null
                : () async {
                    setD(() => mesgul = true);
                    try {
                      await db
                          .from('personel')
                          .update({'ucret': _sayi(yeni.text), 'asgari_ucretli': true, 'maas_turu': 'net'})
                          .inFilter('id', secili.toList());
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      setD(() {
                        mesgul = false;
                        hata = 'Kaydedilemedi: $e';
                      });
                    }
                  },
            child: Text('Güncelle (${secili.length} kişi)'),
          ),
        ],
      ),
    ),
  );
  yeni.dispose();
  if (tamam == true) {
    mesaj.showSnackBar(const SnackBar(content: Text('Maaşlar güncellendi. Personel ekranını yenile.')));
  }
}
