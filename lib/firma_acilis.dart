import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firmalar.dart';

const _elleAdimlar = <(String, String, String)>[
  ('vekalet', 'Vekaletname / yetki belgesi', 'Mükellefin müşavire verdiği vekaletname alındı'),
  ('sozlesme', 'Hizmet sözleşmesi', 'Müşavirlik sözleşmesi imzalandı'),
  ('eimza', 'E-imza / mali mühür', 'Firmanın e-imzası veya mali mührü temin edildi'),
  ('gib', 'GİB yetkileri', 'İnteraktif vergi dairesi ve e-beyanname yetkileri tanımlandı'),
  ('sgk', 'SGK tescili ve yetkisi', 'İşyeri tescili ve e-bildirge yetkisi hazır'),
  ('edefter', 'e-Defter / e-Fatura', 'Gerekliyse başvuru ve kayıt yapıldı'),
  ('belgeler', 'İlk dönem belgeleri', 'Açılış bilançosu, fatura ve belgeler teslim alındı'),
];

/// Yeni mükellef açılış kontrol listesi. Bazı adımlar firma bilgilerinden otomatik işaretlenir.
Future<void> acilisSihirbaziAc(BuildContext context, Firma f) async {
  final db = Supabase.instance.client;
  final tamam = <String, bool>{};
  String? hata;
  try {
    final r = await db.from('firma_acilis').select('adim, tamam').eq('firma_id', f.id);
    for (final x in r) {
      tamam[x['adim'] as String] = x['tamam'] == true;
    }
  } catch (e) {
    hata = 'Liste okunamadı: $e\n(supabase_duyuru_acilis.sql çalıştırıldı mı?)';
  }
  if (!context.mounted) return;

  final otomatik = <(String, String, bool)>[
    ('Temel bilgiler', 'Vergi dairesi, vergi/TC no ve telefon dolu', f.vergiDairesi.isNotEmpty && (f.vergiNo.isNotEmpty || f.tcNo.isNotEmpty) && f.telefon.isNotEmpty),
    ('İletişim e-postası', 'Duyurular için e-posta adresi girildi', f.eposta.isNotEmpty),
    ('Vergi levhası', 'Vergi levhası yüklendi', f.levhaVar),
    ('Mükellef girişi', 'Mükellef giriş hesabı açıldı', f.erisimVar && f.girisAktif),
  ];

  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final toplam = _elleAdimlar.length + otomatik.length;
        final bitti = _elleAdimlar.where((a) => tamam[a.$1] == true).length + otomatik.where((a) => a.$3).length;
        return AlertDialog(
          title: Text('Açılış kontrol listesi\n${f.unvan}', style: const TextStyle(fontSize: 18)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                LinearProgressIndicator(value: bitti / toplam),
                Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text('$bitti / $toplam adım tamam')),
                if (hata != null) Text(hata, style: const TextStyle(color: Colors.red)),
                for (final a in _elleAdimlar)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: tamam[a.$1] == true,
                    title: Text(a.$2),
                    subtitle: Text(a.$3, style: const TextStyle(fontSize: 12)),
                    onChanged: hata != null
                        ? null
                        : (v) async {
                            final yeni = v == true;
                            set(() => tamam[a.$1] = yeni);
                            try {
                              await db.from('firma_acilis').upsert({'firma_id': f.id, 'adim': a.$1, 'tamam': yeni, 'tarih': DateTime.now().toUtc().toIso8601String()});
                            } catch (e) {
                              set(() => tamam[a.$1] = !yeni);
                              if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
                            }
                          },
                  ),
                const Divider(),
                const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('Firma bilgilerinden otomatik', style: TextStyle(fontWeight: FontWeight.w600))),
                for (final a in otomatik)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a.$3 ? Icons.check_circle : Icons.radio_button_unchecked, color: a.$3 ? const Color(0xFF2E7D32) : Colors.black87),
                    title: Text(a.$1),
                    subtitle: Text(a.$2, style: const TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        );
      },
    ),
  );
}
