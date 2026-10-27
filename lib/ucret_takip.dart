import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart' show tl;
import 'firmalar.dart';
import 'maas_alani.dart';
import 'pusula_cikti.dart';

/// Müşavirlik ücreti takibi (sadece yönetici). Her firma için aylık ücret (değişiklik geçmişiyle),
/// kesilen fatura ve tahsilat; geçmiş aylardan kalan borç otomatik hesaplanır.
class UcretTakipSayfasi extends StatefulWidget {
  final int? firmaId; // doluysa yalnızca bu firma gösterilir (firma sayfasındaki sekme)
  const UcretTakipSayfasi({super.key, this.firmaId});
  @override
  State<UcretTakipSayfasi> createState() => _UcretTakipSayfasiState();
}

const _ucretAylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

double? _sayi(String s) => double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));
String _girdi(double v) => tl(v);

class _UcretTakipSayfasiState extends State<UcretTakipSayfasi> {
  final _db = Supabase.instance.client;
  late int _yil, _ay;
  bool _yukleniyor = true;
  String? _hata;
  String _filtre = 'hepsi'; // hepsi | bekleyen | borclu
  final Map<int, List<(int, double)>> _ayar = {}; // firma -> [(yil*12+ay-1, aylik)] sıralı
  final Map<String, Map<String, dynamic>> _takip = {}; // 'firma|yil|ay' -> satır
  final Map<String, List<Map<String, dynamic>>> _kalem = {}; // 'firma|yil|ay' -> hesap listesi satırları

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _yil = n.year;
    _ay = n.month;
    _yukle();
  }

  int _idx(int yil, int ay) => yil * 12 + ay - 1;
  String _anahtar(int f, int y, int a) => '$f|$y|$a';

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      await FirmaDeposu.ornek.yukle();
      final ayar = await _db.from('ucret_ayar').select();
      final takip = await _db.from('ucret_takip').select();
      final kalemler = await _db.from('ucret_kalem').select().order('sira');
      _ayar.clear();
      for (final a in ayar) {
        final d = DateTime.parse(a['gecerli'] as String);
        (_ayar[a['firma_id'] as int] ??= []).add((_idx(d.year, d.month), (a['aylik'] as num).toDouble()));
      }
      for (final l in _ayar.values) {
        l.sort((a, b) => a.$1.compareTo(b.$1));
      }
      _kalem.clear();
      for (final k in kalemler) {
        (_kalem[_anahtar(k['firma_id'] as int, k['yil'] as int, k['ay'] as int)] ??= []).add(Map<String, dynamic>.from(k));
      }
      _takip.clear();
      for (final t in takip) {
        _takip[_anahtar(t['firma_id'] as int, t['yil'] as int, t['ay'] as int)] = Map<String, dynamic>.from(t);
      }
    } catch (e) {
      _hata = 'Yüklenemedi: $e\n(supabase_ucret.sql çalıştırıldı mı?)';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  /// O ay için geçerli aylık ücret; ücret tanımlı değilse null.
  double? _efektif(int firma, int yil, int ay) {
    final l = _ayar[firma];
    if (l == null) return null;
    final i = _idx(yil, ay);
    double? sonuc;
    for (final (gi, ucret) in l) {
      if (gi <= i) sonuc = ucret;
    }
    return sonuc;
  }

  double? _tutar(int firma, int yil, int ay) {
    final k = _kalem[_anahtar(firma, yil, ay)];
    if (k != null && k.isNotEmpty) return k.fold<double>(0, (t, e) => t + (e['tutar'] as num).toDouble());
    final t = _takip[_anahtar(firma, yil, ay)];
    final ozel = t?['tutar'];
    if (ozel != null) return (ozel as num).toDouble();
    return _efektif(firma, yil, ay);
  }

  double _tahsil(int firma, int yil, int ay) => ((_takip[_anahtar(firma, yil, ay)]?['tahsil'] ?? 0) as num).toDouble();

  /// Seçili aydan önceki aylardan kalan borç (ilk ücret ayından başlayarak).
  double _gecmisBorc(int firma) {
    final l = _ayar[firma];
    if (l == null || l.isEmpty) return 0;
    var toplam = 0.0;
    for (var i = l.first.$1; i < _idx(_yil, _ay); i++) {
      final y = i ~/ 12, a = i % 12 + 1;
      final tut = _tutar(firma, y, a) ?? 0;
      toplam += tut - _tahsil(firma, y, a);
    }
    return toplam;
  }

  String _hatirlatMetni(Firma f, double kalan) =>
      'Sayın ${f.unvan} yetkilisi, ${_ucretAylar[_ay - 1]} $_yil itibarıyla müşavirlik ücreti bakiyeniz ${tl(kalan)} TL\'dir. Ödemenizi rica eder, iyi çalışmalar dilerim.';

  /// Borcu olan firmaya hazır ödeme hatırlatma mesajını WhatsApp'ta açar.
  Future<void> _hatirlat(Firma f, double kalan) async {
    final tamam = await whatsappMesajAc(f.telefon, _hatirlatMetni(f, kalan));
    if (!tamam && mounted) {
      await Clipboard.setData(ClipboardData(text: _hatirlatMetni(f, kalan)));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Firmada telefon kayıtlı değil, mesaj kopyalandı. WhatsApp Web açıldı.')));
    }
  }

  /// Borcu olan tüm firmaları listeler, her biri için tek dokunuşla WhatsApp mesajı açar.
  Future<void> _topluHatirlat(List<(Firma, double)> borclular) async {
    final gonderildi = <int>{};
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Ödeme hatırlatması (${borclular.length} firma)'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('WhatsApp tek seferde toplu mesaj göndermeye izin vermez. Her firma için mesaj hazır açılır, sen gönder\'e basarsın.',
                  style: TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(children: [
                  for (final (f, kalan) in borclular)
                    ListTile(
                      dense: true,
                      title: Text(f.unvan, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${tl(kalan)} TL${f.telefon.isEmpty ? '  •  telefon yok' : ''}'),
                      trailing: gonderildi.contains(f.id)
                          ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                          : OutlinedButton.icon(
                              onPressed: () async {
                                await _hatirlat(f, kalan);
                                setD(() => gonderildi.add(f.id));
                              },
                              icon: const Icon(Icons.chat, size: 16),
                              label: const Text('Mesaj aç'),
                            ),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      ),
    );
  }

  void _aydaGit(int fark) {
    var i = _idx(_yil, _ay) + fark;
    setState(() {
      _yil = i ~/ 12;
      _ay = i % 12 + 1;
    });
  }

  String _tarihSql(int yil, int ay) => '$yil-${ay.toString().padLeft(2, '0')}-01';

  /// Belirli bir geçerlilik ayında girilmiş ücret değişikliklerini (zamları) seçilen firmalar için siler;
  /// firmanın ücreti bir önceki ücrete döner.
  Future<void> _zamGeriAl() async {
    final tarihler = <int, List<int>>{}; // geçerlilik (idx) -> firmalar
    _ayar.forEach((firma, liste) {
      for (final (i, _) in liste) {
        (tarihler[i] ??= []).add(firma);
      }
    });
    // ilk ücret tanımı geri alınamaz, yalnızca bir önceki ücreti olan değişiklikler listelenir
    final uygun = <int, List<int>>{};
    tarihler.forEach((i, firmalar) {
      final l = [for (final f in firmalar) if ((_ayar[f] ?? []).any((e) => e.$1 < i)) f];
      if (l.isNotEmpty) uygun[i] = l;
    });
    if (uygun.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geri alınacak ücret değişikliği yok.')));
      return;
    }
    final idxler = uygun.keys.toList()..sort();
    var secilen = idxler.last;
    final secili = <int>{...uygun[secilen]!};
    String? hata;
    var mesgul = false;

    double? onceki(int firma, int idx) {
      double? r;
      for (final (i, u) in _ayar[firma] ?? <(int, double)>[]) {
        if (i < idx) r = u;
      }
      return r;
    }

    double? buAy(int firma, int idx) {
      for (final (i, u) in _ayar[firma] ?? <(int, double)>[]) {
        if (i == idx) return u;
      }
      return null;
    }

    String idxAd(int i) => '${_ucretAylar[i % 12]} ${i ~/ 12}';

    final tamam = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) {
          final firmalar = [for (final f in FirmaDeposu.ornek.liste) if (uygun[secilen]!.contains(f.id)) f];
          return AlertDialog(
            title: const Text('Zammı geri al'),
            content: SizedBox(
              width: 560,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Hangi aydan geçerli zam: '),
                  DropdownButton<int>(
                    value: secilen,
                    items: [for (final i in idxler.reversed) DropdownMenuItem(value: i, child: Text('${idxAd(i)} (${uygun[i]!.length} firma)'))],
                    onChanged: (v) => setD(() {
                      secilen = v ?? secilen;
                      secili
                        ..clear()
                        ..addAll(uygun[secilen]!);
                    }),
                  ),
                ]),
                const Text(
                  'Seçilen firmalarda o aydan geçerli ücret kaydı silinir, ücret bir önceki tutara döner. Tahsilatlar ve ay için elle girilmiş özel tutarlar değişmez.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  TextButton(onPressed: () => setD(() => secili.addAll(uygun[secilen]!)), child: const Text('Tüm firmalar')),
                  TextButton(onPressed: () => setD(secili.clear), child: const Text('Hiçbiri')),
                ]),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(children: [
                      for (final f in firmalar)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: secili.contains(f.id),
                          onChanged: (v) => setD(() => v == true ? secili.add(f.id) : secili.remove(f.id)),
                          title: Text(f.unvan, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${tl(buAy(f.id, secilen) ?? 0)} → ${tl(onceki(f.id, secilen) ?? 0)} TL'),
                        ),
                    ]),
                  ),
                ),
                if (hata != null) Text(hata!, style: const TextStyle(color: Colors.red)),
              ]),
            ),
            actions: [
              TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
              FilledButton(
                onPressed: mesgul || secili.isEmpty
                    ? null
                    : () async {
                        setD(() {
                          mesgul = true;
                          hata = null;
                        });
                        try {
                          await _db
                              .from('ucret_ayar')
                              .delete()
                              .eq('gecerli', _tarihSql(secilen ~/ 12, secilen % 12 + 1))
                              .inFilter('firma_id', secili.toList());
                          if (c.mounted) Navigator.pop(c, true);
                        } catch (e) {
                          setD(() {
                            mesgul = false;
                            hata = 'Geri alınamadı: $e';
                          });
                        }
                      },
                child: Text('Geri al (${secili.length} firma)'),
              ),
            ],
          );
        },
      ),
    );
    if (tamam == true) {
      await _yukle();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zam geri alındı.')));
    }
  }

  Future<void> _topluZam() async {
    final adaylar = [for (final f in FirmaDeposu.ornek.liste) if (_efektif(f.id, _yil, _ay) != null) f];
    if (adaylar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ücreti tanımlı firma yok.')));
      return;
    }
    final oran = TextEditingController(text: '25');
    final sabit = TextEditingController();
    var yuzde = true;
    var yuvarla = 50;
    var gy = _ay >= 10 ? _yil + 1 : _yil;
    var ga = _ay >= 10 ? 1 : _ay;
    final secili = {for (final f in adaylar) f.id};
    String? hata;
    var mesgul = false;

    double yeniUcret(double eski) {
      final o = _sayi(oran.text) ?? 0;
      final s = _sayi(sabit.text) ?? 0;
      final y = yuzde ? eski * (1 + o / 100) : eski + s;
      return yuvarla > 0 ? (y / yuvarla).round() * yuvarla.toDouble() : (y * 100).round() / 100;
    }

    final tamam = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Toplu ücret zammı'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: true, label: Text('Yüzde')), ButtonSegment(value: false, label: Text('Sabit tutar'))],
                selected: {yuzde},
                onSelectionChanged: (v) => setD(() => yuzde = v.first),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: yuzde
                      ? TextField(controller: oran, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Zam oranı (%)'), onChanged: (_) => setD(() {}))
                      : TextField(controller: sabit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Eklenecek tutar (TL)'), onChanged: (_) => setD(() {})),
                ),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: yuvarla,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Yuvarlama yok')),
                    DropdownMenuItem(value: 10, child: Text('10 TL\'ye')),
                    DropdownMenuItem(value: 50, child: Text('50 TL\'ye')),
                    DropdownMenuItem(value: 100, child: Text('100 TL\'ye')),
                  ],
                  onChanged: (v) => setD(() => yuvarla = v ?? 0),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Geçerlilik: '),
                DropdownButton<int>(
                  value: ga,
                  items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(_ucretAylar[i - 1]))],
                  onChanged: (v) => setD(() => ga = v ?? ga),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: gy,
                  items: [for (var y = _yil - 1; y <= _yil + 2; y++) DropdownMenuItem(value: y, child: Text('$y'))],
                  onChanged: (v) => setD(() => gy = v ?? gy),
                ),
              ]),
              const Text(
                'Seçili aydan itibaren yeni ücret geçerli olur, önceki aylar değişmez. O ay için elle girilmiş özel tutar veya hesap listesi varsa o ay zamdan etkilenmez.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final f in adaylar)
                      Builder(builder: (_) {
                        final eski = _efektif(f.id, gy, ga) ?? 0;
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: secili.contains(f.id),
                          onChanged: (v) => setD(() => v == true ? secili.add(f.id) : secili.remove(f.id)),
                          title: Text(f.unvan, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${tl(eski)} → ${tl(yeniUcret(eski))} TL'),
                        );
                      }),
                  ]),
                ),
              ),
              if (hata != null) Text(hata!, style: const TextStyle(color: Colors.red)),
            ]),
          ),
          actions: [
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: mesgul || secili.isEmpty
                  ? null
                  : () async {
                      setD(() {
                        mesgul = true;
                        hata = null;
                      });
                      try {
                        final satirlar = [
                          for (final f in adaylar)
                            if (secili.contains(f.id))
                              {'firma_id': f.id, 'gecerli': _tarihSql(gy, ga), 'aylik': yeniUcret(_efektif(f.id, gy, ga) ?? 0)}
                        ];
                        await _db.from('ucret_ayar').upsert(satirlar, onConflict: 'firma_id,gecerli');
                        if (c.mounted) Navigator.pop(c, true);
                      } catch (e) {
                        setD(() {
                          mesgul = false;
                          hata = 'Kaydedilemedi: $e';
                        });
                      }
                    },
              child: Text('Uygula (${secili.length} firma)'),
            ),
          ],
        ),
      ),
    );
    oran.dispose();
    sabit.dispose();
    if (tamam == true) {
      await _yukle();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yeni ücretler kaydedildi.')));
    }
  }

  Future<void> _duzenle(Firma f) async {
    final efektif = _efektif(f.id, _yil, _ay);
    final listeVar = (_kalem[_anahtar(f.id, _yil, _ay)] ?? []).isNotEmpty;
    final mevcut = _takip[_anahtar(f.id, _yil, _ay)];
    final tutarK = TextEditingController(text: _tutar(f.id, _yil, _ay) == null ? '' : _girdi(_tutar(f.id, _yil, _ay)!));
    final tahsilK = TextEditingController(text: _tahsil(f.id, _yil, _ay) == 0 ? '' : _girdi(_tahsil(f.id, _yil, _ay)));
    final faturaNo = TextEditingController(text: (mevcut?['fatura_no'] ?? '') as String);
    final aciklama = TextEditingController(text: (mevcut?['aciklama'] ?? '') as String);
    var fatura = (mevcut?['fatura_kesildi'] ?? false) as bool;
    var sonrakiAylar = efektif == null; // ilk tanımda varsayılan: sonraki aylar için de geçerli
    String? hata;
    var mesgul = false;

    final kaydedildi = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('${f.unvan}\n${_ucretAylar[_ay - 1]} $_yil', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                MaasAlani(
                  controller: tutarK,
                  etiket: listeVar ? 'Bu ayın toplamı (hesap listesinden)' : 'Bu ayın müşavirlik ücreti (TL)',
                  kilitli: listeVar,
                  oneri: efektif == null ? null : _girdi(efektif),
                ),
                if (listeVar) const SizedBox.shrink() else
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: sonrakiAylar,
                  onChanged: (v) => setD(() => sonrakiAylar = v ?? false),
                  title: const Text('Bu ücret sonraki aylar için de geçerli', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Geçmiş aylar etkilenmez.', style: TextStyle(fontSize: 11)),
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: MaasAlani(controller: tahsilK, etiket: 'Tahsil edilen (TL)', ipucu: '0,00')),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: () => setD(() => tahsilK.text = tutarK.text),
                      child: const Text('Tamamı'),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: fatura,
                  onChanged: (v) => setD(() => fatura = v),
                  title: const Text('Fatura kesildi'),
                ),
                TextField(controller: faturaNo, decoration: const InputDecoration(labelText: 'Fatura no (isteğe bağlı)')),
                TextField(controller: aciklama, maxLines: 2, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
                if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: mesgul
                  ? null
                  : () async {
                      final tutar = tutarK.text.trim().isEmpty ? null : _sayi(tutarK.text);
                      final tahsil = tahsilK.text.trim().isEmpty ? 0.0 : _sayi(tahsilK.text);
                      if ((tutarK.text.trim().isNotEmpty && tutar == null) || tahsil == null) {
                        setD(() => hata = 'Tutar okunamadı.');
                        return;
                      }
                      if (!listeVar && tutar == null && efektif == null) {
                        setD(() => hata = 'Önce bu ayın ücretini yaz.');
                        return;
                      }
                      setD(() {
                        mesgul = true;
                        hata = null;
                      });
                      try {
                        final ayarYaz = !listeVar && tutar != null && (sonrakiAylar || efektif == null);
                        if (ayarYaz) {
                          await _db.from('ucret_ayar').upsert(
                              {'firma_id': f.id, 'gecerli': _tarihSql(_yil, _ay), 'aylik': tutar},
                              onConflict: 'firma_id,gecerli');
                        }
                        // Ay için özel tutar yalnızca geçerli aylık ücretten farklıysa saklanır.
                        final ozel = (listeVar || tutar == null || ayarYaz || tutar == efektif) ? null : tutar;
                        await _db.from('ucret_takip').upsert({
                          'firma_id': f.id,
                          'yil': _yil,
                          'ay': _ay,
                          'tutar': ozel,
                          'tahsil': tahsil,
                          'fatura_kesildi': fatura,
                          'fatura_no': faturaNo.text.trim(),
                          'aciklama': aciklama.text.trim(),
                          'guncelleme': DateTime.now().toUtc().toIso8601String(),
                        }, onConflict: 'firma_id,yil,ay');
                        if (c.mounted) Navigator.pop(c, true);
                      } catch (e) {
                        setD(() {
                          mesgul = false;
                          hata = 'Kaydedilemedi: $e';
                        });
                      }
                    },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (kaydedildi == true) await _yukle();
  }


  static const _varsayilanKalemler = [
    'MUH.ÜCRETİ',
    'KDV',
    'MUHTASAR',
    'BELEDİYE',
    'GELİR V. GEÇİCİ V.',
    'CEZA',
    'DAMGA',
    'DEFTER TASDİK',
    'GELİR V.',
  ];

  /// Firmanın bu ayki hesap listesi: ödeme kalemlerinin adı ve tutarı değiştirilebilir, satır eklenip silinebilir.
  Future<void> _pusula(Firma f) async {
    final efektif = _efektif(f.id, _yil, _ay);
    final kayitli = _kalem[_anahtar(f.id, _yil, _ay)];
    // satır: (ad, tutar, ücret satırı mı)
    final satirlar = <(TextEditingController, TextEditingController, bool)>[];
    void ekle(String ad, double tutar, bool ucret) => satirlar.add((
          TextEditingController(text: ad),
          TextEditingController(text: tutar == 0 ? '' : _girdi(tutar)),
          ucret,
        ));
    if (kayitli != null && kayitli.isNotEmpty) {
      for (final k in kayitli) {
        ekle(k['ad'] as String, (k['tutar'] as num).toDouble(), (k['ucret'] ?? false) as bool);
      }
    } else {
      // Bu firmanın önceki aylardaki listesinin adlarını al; yoksa varsayılan adlar
      List<Map<String, dynamic>>? onceki;
      var en = -1;
      for (final e in _kalem.entries) {
        final p = e.key.split('|');
        if (int.parse(p[0]) != f.id || e.value.isEmpty) continue;
        final i = _idx(int.parse(p[1]), int.parse(p[2]));
        if (i < _idx(_yil, _ay) && i > en) {
          en = i;
          onceki = e.value;
        }
      }
      if (onceki != null) {
        for (final k in onceki) {
          final ucret = (k['ucret'] ?? false) as bool;
          ekle(k['ad'] as String, ucret ? (efektif ?? 0) : 0, ucret);
        }
      } else {
        for (var i = 0; i < _varsayilanKalemler.length; i++) {
          ekle(_varsayilanKalemler[i], i == 0 ? (efektif ?? 0) : 0, i == 0);
        }
      }
    }
    final gecen = _gecmisBorc(f.id);
    String? hata;
    var mesgul = false;

    double toplam() => satirlar.fold(0.0, (t, s) => t + (_sayi(s.$2.text) ?? 0));

    PusulaVeri veriOlustur() => PusulaVeri(
          firma: f.unvan,
          donem: '${_ucretAylar[_ay - 1]} $_yil',
          gecenAy: gecen,
          kalemler: [
            for (final s in satirlar)
              if (s.$1.text.trim().isNotEmpty) (s.$1.text.trim(), _sayi(s.$2.text) ?? 0),
          ],
        );

    void bilgi(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

    final kaydedildi = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('${f.unvan}\nHesap listesi • ${_ucretAylar[_ay - 1]} $_yil', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (gecen != 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Expanded(child: Text('GEÇEN AY', style: TextStyle(fontWeight: FontWeight.w700))),
                      Text(tl(gecen), style: TextStyle(fontWeight: FontWeight.w700, color: gecen > 0 ? const Color(0xFFB3261E) : Colors.black87)),
                      const SizedBox(width: 48),
                    ]),
                  ),
                for (var i = 0; i < satirlar.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: satirlar[i].$1,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(isDense: true, hintText: 'Ödeme adı'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 120, child: TutarKutusu(controller: satirlar[i].$2, degisti: () => setD(() {}))),
                      IconButton(
                        tooltip: 'Satırı sil',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setD(() => satirlar.removeAt(i)),
                      ),
                    ]),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setD(() => ekle('', 0, false)),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Satır ekle'),
                  ),
                ),
                const Divider(),
                Row(children: [
                  const Expanded(child: Text('TOPLAM', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  Text(tl(toplam() + gecen), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(width: 48),
                ]),
                if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
              ]),
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Çıktı al / gönder',
              onSelected: (v) async {
                final veri = veriOlustur();
                try {
                  if (v == 'metin') {
                    await Clipboard.setData(ClipboardData(text: veri.metin));
                    bilgi('Liste kopyalandı, WhatsApp\'a yapıştırabilirsin.');
                  } else if (v == 'whatsapp') {
                    bilgi(await pusulaWhatsapp(veri, f.telefon));
                  } else {
                    await pusulaIndir(veri, v);
                    bilgi('Dosya indirildi.');
                  }
                } catch (e) {
                  bilgi('İşlem yapılamadı: $e');
                }
              },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'whatsapp', child: ListTile(dense: true, leading: Icon(Icons.chat_outlined), title: Text('WhatsApp\'a gönder (resim)'))),
                PopupMenuItem(value: 'png', child: ListTile(dense: true, leading: Icon(Icons.image_outlined), title: Text('Resim indir (PNG)'))),
                PopupMenuItem(value: 'pdf', child: ListTile(dense: true, leading: Icon(Icons.picture_as_pdf_outlined), title: Text('PDF indir'))),
                PopupMenuItem(value: 'xlsx', child: ListTile(dense: true, leading: Icon(Icons.table_chart_outlined), title: Text('Excel indir'))),
                PopupMenuItem(value: 'metin', child: ListTile(dense: true, leading: Icon(Icons.copy_outlined), title: Text('Metin olarak kopyala'))),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.ios_share, size: 18),
                  SizedBox(width: 4),
                  Text('Gönder / İndir'),
                ]),
              ),
            ),
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: mesgul
                  ? null
                  : () async {
                      setD(() {
                        mesgul = true;
                        hata = null;
                      });
                      try {
                        await _db.from('ucret_kalem').delete().eq('firma_id', f.id).eq('yil', _yil).eq('ay', _ay);
                        final yeni = <Map<String, dynamic>>[];
                        for (var i = 0; i < satirlar.length; i++) {
                          final ad = satirlar[i].$1.text.trim();
                          if (ad.isEmpty) continue;
                          yeni.add({
                            'firma_id': f.id,
                            'yil': _yil,
                            'ay': _ay,
                            'sira': i,
                            'ad': ad,
                            'tutar': _sayi(satirlar[i].$2.text) ?? 0,
                            'ucret': satirlar[i].$3,
                          });
                        }
                        if (yeni.isNotEmpty) await _db.from('ucret_kalem').insert(yeni);
                        if (c.mounted) Navigator.pop(c, true);
                      } catch (e) {
                        setD(() {
                          mesgul = false;
                          hata = 'Kaydedilemedi: $e';
                        });
                      }
                    },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (kaydedildi == true) await _yukle();
  }

  Widget _kart(String baslik, double tutar, Color renk, IconData ikon) => SizedBox(
        width: 220,
        child: Card(
          elevation: 0,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(backgroundColor: renk.withValues(alpha: 0.14), child: Icon(ikon, color: renk)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tl(tutar)} ₺', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: renk)),
                  Text(baslik, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _durum(double tutar, double tahsil, double toplamBorc) {
    const yesil = Color(0xFF2E7D32);
    const turuncu = Color(0xFFEF6C00);
    const kirmizi = Color(0xFFD98585);
    final (e, r) = toplamBorc <= 0
        ? ('Ödendi', yesil)
        : tahsil > 0
            ? ('Kısmi', turuncu)
            : ('Bekliyor', kirmizi);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: r.withValues(alpha: e == 'Bekliyor' ? 0.09 : 0.12),
        border: Border.all(color: r),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(e, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: r)),
    );
  }

  Widget _hucre(double w, Widget c, {Alignment al = Alignment.centerRight}) =>
      SizedBox(width: w, child: Align(alignment: al, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: c)));

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    const kirmizi = Color(0xFFB3261E);
    const yesil = Color(0xFF2E7D32);
    const turuncu = Color(0xFFEF6C00);

    final satirlar = <(Firma, double, double, double)>[]; // firma, tutar, tahsil, geçmiş borç
    final tanimsiz = <Firma>[];
    var beklenen = 0.0, tahsilToplam = 0.0, gecmisToplam = 0.0, toplamKalan = 0.0;
    for (final f in FirmaDeposu.ornek.liste.where((f) => widget.firmaId == null || f.id == widget.firmaId)) {
      final tutar = _tutar(f.id, _yil, _ay);
      if (tutar == null) {
        tanimsiz.add(f);
        continue;
      }
      final tahsil = _tahsil(f.id, _yil, _ay);
      final borc = _gecmisBorc(f.id);
      beklenen += tutar;
      tahsilToplam += tahsil;
      gecmisToplam += borc > 0 ? borc : 0;
      final k = borc + tutar - tahsil;
      toplamKalan += k > 0 ? k : 0;
      satirlar.add((f, tutar, tahsil, borc));
    }
    final gorunen = satirlar.where((s) {
      if (_filtre == 'bekleyen') return s.$4 + s.$2 - s.$3 > 0;
      if (_filtre == 'borclu') return s.$4 > 0;
      return true;
    }).toList();

    const genislikler = [250.0, 110.0, 120.0, 110.0, 135.0, 70.0, 100.0, 64.0, 64.0];
    final toplamGenislik = genislikler.fold(0.0, (a, b) => a + b);

    Widget baslikSatiri() => Container(
          color: const Color(0xFFD9D9D9),
          height: 40,
          child: Row(children: [
            _hucre(genislikler[0], const Text('Firma', style: TextStyle(fontWeight: FontWeight.w700)), al: Alignment.centerLeft),
            _hucre(genislikler[1], const Text('Ücret', style: TextStyle(fontWeight: FontWeight.w700))),
            _hucre(genislikler[2], const Text('Geçmiş borç', style: TextStyle(fontWeight: FontWeight.w700))),
            _hucre(genislikler[3], const Text('Tahsil', style: TextStyle(fontWeight: FontWeight.w700))),
            _hucre(genislikler[4], const Text('Toplam borç', style: TextStyle(fontWeight: FontWeight.w700))),
            _hucre(genislikler[5], const Text('Fatura', style: TextStyle(fontWeight: FontWeight.w700)), al: Alignment.center),
            _hucre(genislikler[6], const Text('Durum', style: TextStyle(fontWeight: FontWeight.w700)), al: Alignment.center),
            _hucre(genislikler[7], const Text('Liste', style: TextStyle(fontWeight: FontWeight.w700)), al: Alignment.center),
            _hucre(genislikler[8], const Text('Hatırlat', style: TextStyle(fontWeight: FontWeight.w700)), al: Alignment.center),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          IconButton(onPressed: () => _aydaGit(-1), icon: const Icon(Icons.chevron_left)),
          Text('${_ucretAylar[_ay - 1]} $_yil', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          IconButton(onPressed: () => _aydaGit(1), icon: const Icon(Icons.chevron_right)),
          const Spacer(),
          IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (_hata != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_hata!, style: const TextStyle(color: Colors.red))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          _kart('Bu ay beklenen', beklenen, Theme.of(context).colorScheme.primary, Icons.request_quote_outlined),
          _kart('Bu ay tahsil edilen', tahsilToplam, yesil, Icons.check_circle_outline),
          _kart('Geçmiş aylardan borç', gecmisToplam, turuncu, Icons.history),
          _kart('Toplam kalan borç', toplamKalan, kirmizi, Icons.warning_amber_rounded),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'hepsi', label: Text('Hepsi')),
              ButtonSegment(value: 'bekleyen', label: Text('Borcu olan')),
              ButtonSegment(value: 'borclu', label: Text('Geçmiş borcu olan')),
            ],
            selected: {_filtre},
            onSelectionChanged: (v) => setState(() => _filtre = v.first),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () {
              final borclular = [for (final s in satirlar) if (s.$4 + s.$2 - s.$3 > 0) (s.$1, s.$4 + s.$2 - s.$3)];
              _topluHatirlat(borclular);
            },
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Toplu hatırlat'),
          ),
          OutlinedButton.icon(
            onPressed: _topluZam,
            icon: const Icon(Icons.trending_up, size: 18),
            label: const Text('Toplu zam'),
          ),
          OutlinedButton.icon(
            onPressed: _zamGeriAl,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Zammı geri al'),
          ),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (c, kisit) {
          final w = kisit.maxWidth < toplamGenislik ? toplamGenislik : kisit.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: w,
              child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                baslikSatiri(),
                for (var i = 0; i < gorunen.length; i++)
                  Builder(builder: (c) {
                    final (f, tutar, tahsil, borc) = gorunen[i];
                    final kalan = borc + tutar - tahsil; // toplam borç: geçmiş + bu ay - tahsilat
                    final fatura = (_takip[_anahtar(f.id, _yil, _ay)]?['fatura_kesildi'] ?? false) as bool;
                    return Material(
                      color: i.isEven ? Colors.white : const Color(0xFFE6E6E6),
                      child: InkWell(
                        hoverColor: const Color(0xFFFFE680),
                        onTap: () => _duzenle(f),
                        child: SizedBox(
                          height: 48,
                          child: Row(children: [
                            _hucre(genislikler[0], Text(f.unvan, maxLines: 2, overflow: TextOverflow.ellipsis), al: Alignment.centerLeft),
                            _hucre(genislikler[1], Text(tl(tutar))),
                            _hucre(genislikler[2], Text(tl(borc), style: TextStyle(fontWeight: borc > 0 ? FontWeight.w700 : FontWeight.w400, color: borc > 0 ? kirmizi : Colors.black87))),
                            _hucre(genislikler[3], Text(tl(tahsil))),
                            _hucre(genislikler[4], Text(tl(kalan), style: TextStyle(fontWeight: FontWeight.w800, color: kalan > 0 ? kirmizi : yesil))),
                            _hucre(genislikler[5], Icon(fatura ? Icons.check_circle : Icons.circle_outlined, size: 18, color: fatura ? yesil : Colors.black54), al: Alignment.center),
                            _hucre(genislikler[6], _durum(tutar, tahsil, kalan), al: Alignment.center),
                            _hucre(
                                genislikler[7],
                                IconButton(
                                  tooltip: 'Hesap listesi (ödeme kalemleri)',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.receipt_long_outlined,
                                      color: (_kalem[_anahtar(f.id, _yil, _ay)] ?? []).isNotEmpty ? yesil : Colors.black87),
                                  onPressed: () => _pusula(f),
                                ),
                                al: Alignment.center),
                            _hucre(
                                genislikler[8],
                                IconButton(
                                  tooltip: kalan > 0 ? 'WhatsApp ile ödeme hatırlat' : 'Borç yok',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.notifications_active_outlined, color: kalan > 0 ? turuncu : Colors.black26),
                                  onPressed: kalan > 0 ? () => _hatirlat(f, kalan) : null,
                                ),
                                al: Alignment.center),
                          ]),
                        ),
                      ),
                    );
                  }),
                if (gorunen.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Text('Bu görünümde firma yok.')),
                if (tanimsiz.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 22, 16, 6),
                    child: Text('Ücreti henüz belirlenmemiş firmalar', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  for (final f in tanimsiz)
                    ListTile(
                      dense: true,
                      title: Text(f.unvan),
                      trailing: OutlinedButton(onPressed: () => _duzenle(f), child: const Text('Ücret belirle')),
                      leading: IconButton(
                        tooltip: 'Hesap listesi',
                        icon: const Icon(Icons.receipt_long_outlined),
                        onPressed: () => _pusula(f),
                      ),
                    ),
                ],
              ]),
            ),
          );
        }),
      ),
    ]);
  }
}
