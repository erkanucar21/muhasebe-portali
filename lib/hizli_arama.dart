import 'package:flutter/material.dart';
import 'firmalar.dart';

class AramaSonucu {
  final int? bolumIndex;
  final int? firmaId;
  const AramaSonucu({this.bolumIndex, this.firmaId});
}

String _duz(String s) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosucgiosu';
  var r = s;
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r.toLowerCase();
}

class _Oge {
  final String ad, alt;
  final IconData ikon;
  final AramaSonucu sonuc;
  const _Oge(this.ad, this.alt, this.ikon, this.sonuc);
}

/// Cmd+K / Ctrl+K ile açılan hızlı arama: firma veya bölüm yaz, Enter ile git.
Future<AramaSonucu?> hizliAramaAc(BuildContext context, List<({String ad, IconData ikon})> bolumler) {
  final tum = <_Oge>[
    for (var i = 0; i < bolumler.length; i++) _Oge(bolumler[i].ad, 'Bölüm', bolumler[i].ikon, AramaSonucu(bolumIndex: i)),
    for (final f in FirmaDeposu.ornek.liste)
      _Oge(f.unvan, [f.vergiNo, f.telefon].where((e) => e.isNotEmpty).join('  |  '), Icons.business_outlined, AramaSonucu(firmaId: f.id)),
  ];
  final kontrol = TextEditingController();
  return showDialog<AramaSonucu>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) {
        final q = _duz(kontrol.text.trim());
        final bulunan = (q.isEmpty ? tum : tum.where((o) => _duz(o.ad).contains(q) || _duz(o.alt).contains(q)).toList()).take(30).toList();
        return Dialog(
          alignment: Alignment.topCenter,
          insetPadding: const EdgeInsets.fromLTRB(16, 70, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: kontrol,
                  autofocus: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Firma veya bölüm ara (Enter ile aç)'),
                  onChanged: (_) => setD(() {}),
                  onSubmitted: (_) {
                    if (bulunan.isNotEmpty) Navigator.pop(c, bulunan.first.sonuc);
                  },
                ),
              ),
              Flexible(
                child: bulunan.isEmpty
                    ? const Padding(padding: EdgeInsets.all(20), child: Text('Sonuç yok'))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final o in bulunan)
                            ListTile(
                              dense: true,
                              leading: Icon(o.ikon),
                              title: Text(o.ad),
                              subtitle: o.alt.isEmpty ? null : Text(o.alt),
                              onTap: () => Navigator.pop(c, o.sonuc),
                            ),
                        ],
                      ),
              ),
            ]),
          ),
        );
      },
    ),
  );
}
