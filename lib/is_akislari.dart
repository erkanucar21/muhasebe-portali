import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firmalar.dart';

const _sablonlar = <String, (String, List<String>)>{
  'kurulus': (
    'Şirket kuruluşu',
    [
      'Ortak, sermaye ve ana sözleşme bilgilerinin toplanması',
      'Adres ve kira sözleşmesinin temini',
      'Ticaret sicil (MERSİS) başvurusu ve tescil',
      'İmza sirkülerinin hazırlanması',
      'Vergi dairesi işe başlama bildirimi',
      'Oda kaydı',
      'E-Defter / E-Fatura / E-Arşiv başvuruları',
      'SGK işyeri tescili',
      'Banka hesabı ve sermaye ödemesi',
      'Müşavirlik sözleşmesi ve vekâletname',
      'Firmanın bu sisteme kaydı ve takip ayarları',
    ]
  ),
  'sahis': (
    'Şahıs işe başlama',
    [
      'Kimlik ve adres belgelerinin alınması',
      'Vergi dairesi işe başlama bildirimi',
      'Oda / meslek kuruluşu kaydı',
      'SGK (Bağ-Kur) tescili',
      'E-Defter / E-Fatura / E-Arşiv başvuruları',
      'Müşavirlik sözleşmesi ve vekâletname',
      'Firmanın bu sisteme kaydı ve takip ayarları',
    ]
  ),
  'adres': (
    'Adres değişikliği',
    [
      'Yeni adres kira sözleşmesi veya tapu',
      'Ortaklar / yönetim kurulu kararı',
      'Ticaret sicil tescil ve ilan',
      'Vergi dairesi adres değişikliği bildirimi',
      'SGK işyeri adres bildirimi',
      'Oda kaydının güncellenmesi',
      'Banka, E-Fatura ve diğer kurum bilgilerinin güncellenmesi',
      'Vergi levhasının yenilenmesi',
      'Belgelerin firma arşivine eklenmesi',
    ]
  ),
  'ortak': (
    'Ortak veya sermaye değişikliği',
    [
      'Ortaklar kurulu kararı',
      'Pay devri veya ana sözleşme tadili (noter)',
      'Ticaret sicil tescil ve ilan',
      'Vergi dairesi bildirimi',
      'Pay defterinin güncellenmesi',
      'İmza sirkülerinin yenilenmesi',
      'Banka ve diğer kurumların bilgilendirilmesi',
      'Belgelerin firma arşivine eklenmesi',
    ]
  ),
  'kapanis': (
    'Kapanış / tasfiye',
    [
      'Ortaklar kararı (tasfiyeye giriş veya kapanış)',
      'Ticaret sicil tescil ve ilan',
      'SGK işyeri kapanışı ve personel çıkışları',
      'Kıdem, ihbar ve ibranameler',
      'Son beyannameler (KDV, muhtasar, geçici vergi)',
      'Kapanış bilançosu ve defter kapanışları',
      'Vergi dairesi kapanış bildirimi',
      'E-Fatura / E-Defter kayıtlarının kapatılması',
      'Defter ve belgelerin saklanması',
      'Firmanın bu sistemde kapatılması',
    ]
  ),
  'ozel': ('Özel liste', <String>[]),
};

String _sql(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _yaz(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Şirket kuruluşu, adres değişikliği, kapanış gibi çok adımlı işlerin kontrol listeleri (sadece yönetici).
class IsAkislariSayfasi extends StatefulWidget {
  const IsAkislariSayfasi({super.key});
  @override
  State<IsAkislariSayfasi> createState() => _IsAkislariSayfasiState();
}

class _IsAkislariSayfasiState extends State<IsAkislariSayfasi> {
  final _db = Supabase.instance.client;
  bool _yukleniyor = true;
  String? _hata;
  bool _kapaliGoster = false;
  List<Map<String, dynamic>> _akislar = [];
  final Map<int, List<Map<String, dynamic>>> _adimlar = {};

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      if (FirmaDeposu.ornek.liste.isEmpty) await FirmaDeposu.ornek.yukle();
      final a = await _db.from('is_akisi').select().order('olusturma', ascending: false);
      final s = await _db.from('is_akisi_adim').select().order('sira');
      _akislar = a.cast<Map<String, dynamic>>();
      _adimlar.clear();
      for (final x in s.cast<Map<String, dynamic>>()) {
        (_adimlar[(x['akis_id'] as num).toInt()] ??= []).add(x);
      }
    } catch (e) {
      _hata = 'Yüklenemedi: $e\n(supabase_is_akisi.sql çalıştırıldı mı?)';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  void _bilgi(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _firmaAdi(Map<String, dynamic> a) {
    if (a['firma_id'] != null) {
      final f = FirmaDeposu.ornek.bul((a['firma_id'] as num).toInt());
      if (f != null) return f.unvan;
    }
    return (a['firma_adi'] ?? '') as String;
  }

  Future<void> _yeni() async {
    var sablon = 'kurulus';
    int? firmaId;
    final firmaAd = TextEditingController();
    final baslik = TextEditingController();
    String? hata;
    var mesgul = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Yeni iş akışı'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<String>(
                  initialValue: sablon,
                  decoration: const InputDecoration(labelText: 'Şablon'),
                  items: [for (final e in _sablonlar.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
                  onChanged: (v) => setD(() => sablon = v ?? sablon),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: firmaId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Firma'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Henüz sistemde kayıtlı değil')),
                    for (final f in FirmaDeposu.ornek.liste) DropdownMenuItem<int?>(value: f.id, child: Text(f.unvan, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setD(() => firmaId = v),
                ),
                if (firmaId == null) ...[
                  const SizedBox(height: 10),
                  TextField(controller: firmaAd, decoration: const InputDecoration(labelText: 'Firma / kişi adı')),
                ],
                const SizedBox(height: 10),
                TextField(controller: baslik, decoration: const InputDecoration(labelText: 'Başlık (boşsa şablon adı)')),
                const SizedBox(height: 8),
                const Text('Şablondaki adımlar örnektir; sonra adım ekleyip silebilir, tarih ve not girebilirsin.', style: TextStyle(fontSize: 12, color: Colors.black87)),
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
                      if (firmaId == null && firmaAd.text.trim().isEmpty) {
                        setD(() => hata = 'Firma veya kişi adı yaz');
                        return;
                      }
                      setD(() {
                        mesgul = true;
                        hata = null;
                      });
                      try {
                        final sab = _sablonlar[sablon]!;
                        final ad = firmaId == null ? firmaAd.text.trim() : (FirmaDeposu.ornek.bul(firmaId!)?.unvan ?? '');
                        final r = await _db
                            .from('is_akisi')
                            .insert({
                              'firma_id': firmaId,
                              'firma_adi': firmaId == null ? ad : '',
                              'tur': sablon,
                              'baslik': baslik.text.trim().isEmpty ? '${sab.$1} - $ad' : baslik.text.trim(),
                            })
                            .select()
                            .single();
                        final id = (r['id'] as num).toInt();
                        if (sab.$2.isNotEmpty) {
                          await _db.from('is_akisi_adim').insert([
                            for (var i = 0; i < sab.$2.length; i++) {'akis_id': id, 'sira': i, 'ad': sab.$2[i]}
                          ]);
                        }
                        if (c.mounted) Navigator.pop(c, true);
                      } catch (e) {
                        setD(() {
                          mesgul = false;
                          hata = 'Kaydedilemedi: $e';
                        });
                      }
                    },
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
    firmaAd.dispose();
    baslik.dispose();
    if (ok == true) _yukle();
  }

  Future<void> _adimGuncelle(Map<String, dynamic> a, Map<String, dynamic> yeni) async {
    try {
      await _db.from('is_akisi_adim').update(yeni).eq('id', a['id']);
      a.addAll(yeni);
      if (mounted) setState(() {});
    } catch (e) {
      _bilgi('Kaydedilemedi: $e');
    }
  }

  Future<void> _tarihSec(Map<String, dynamic> a) async {
    final d = await showDatePicker(
      context: context,
      initialDate: a['hedef'] == null ? DateTime.now() : DateTime.parse(a['hedef'] as String),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (d != null) await _adimGuncelle(a, {'hedef': _sql(d)});
  }

  Future<void> _adimDuzenle(int akisId, {Map<String, dynamic>? adim}) async {
    final ad = TextEditingController(text: (adim?['ad'] ?? '') as String);
    final not = TextEditingController(text: (adim?['aciklama'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(adim == null ? 'Adım ekle' : 'Adımı düzenle'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ad, autofocus: true, decoration: const InputDecoration(labelText: 'Adım')),
            const SizedBox(height: 10),
            TextField(controller: not, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    final adYazi = ad.text.trim();
    final notYazi = not.text.trim();
    ad.dispose();
    not.dispose();
    if (ok != true || adYazi.isEmpty) return;
    try {
      if (adim == null) {
        final sira = (_adimlar[akisId] ?? []).length;
        await _db.from('is_akisi_adim').insert({'akis_id': akisId, 'sira': sira, 'ad': adYazi, 'aciklama': notYazi});
        await _yukle();
      } else {
        await _adimGuncelle(adim, {'ad': adYazi, 'aciklama': notYazi});
      }
    } catch (e) {
      _bilgi('Kaydedilemedi: $e');
    }
  }

  Future<void> _adimSil(Map<String, dynamic> a) async {
    try {
      await _db.from('is_akisi_adim').delete().eq('id', a['id']);
      await _yukle();
    } catch (e) {
      _bilgi('Silinemedi: $e');
    }
  }

  Future<void> _akisSil(Map<String, dynamic> a) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('İş akışı silinsin mi?'),
        content: Text('${a['baslik']} ve bütün adımları kalıcı olarak silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _db.from('is_akisi').delete().eq('id', a['id']);
      await _yukle();
    } catch (e) {
      _bilgi('Silinemedi: $e');
    }
  }

  Future<void> _kapat(Map<String, dynamic> a, bool kapandi) async {
    try {
      await _db.from('is_akisi').update({'kapandi': kapandi}).eq('id', a['id']);
      a['kapandi'] = kapandi;
      if (mounted) setState(() {});
    } catch (e) {
      _bilgi('Kaydedilemedi: $e');
    }
  }

  bool _gecikti(Map<String, dynamic> s) {
    if (s['tamam'] == true || s['hedef'] == null) return false;
    final h = DateTime.parse(s['hedef'] as String);
    final b = DateTime.now();
    return h.isBefore(DateTime(b.year, b.month, b.day));
  }

  Widget _adimSatiri(Map<String, dynamic> s, int akisId) {
    final tamam = s['tamam'] == true;
    final gec = _gecikti(s);
    final aciklama = (s['aciklama'] ?? '') as String;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: tamam,
        onChanged: (v) => _adimGuncelle(s, {'tamam': v == true, 'tamam_tarih': v == true ? _sql(DateTime.now()) : null}),
      ),
      title: Text(s['ad'] as String, style: TextStyle(decoration: tamam ? TextDecoration.lineThrough : null, color: tamam ? Colors.black87 : null)),
      subtitle: aciklama.isEmpty ? null : Text(aciklama, style: const TextStyle(fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(
          onPressed: () => _tarihSec(s),
          child: Text(
            s['hedef'] == null ? 'Tarih' : _yaz(DateTime.parse(s['hedef'] as String)),
            style: TextStyle(color: gec ? const Color(0xFFC62828) : null, fontWeight: gec ? FontWeight.w700 : null),
          ),
        ),
        if (s['hedef'] != null) IconButton(tooltip: 'Tarihi kaldır', iconSize: 16, onPressed: () => _adimGuncelle(s, {'hedef': null}), icon: const Icon(Icons.clear)),
        PopupMenuButton<int>(
          onSelected: (v) => v == 1 ? _adimDuzenle(akisId, adim: s) : _adimSil(s),
          itemBuilder: (c) => const [
            PopupMenuItem(value: 1, child: Text('Düzenle')),
            PopupMenuItem(value: 2, child: Text('Sil')),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    final liste = [for (final a in _akislar) if ((a['kapandi'] == true) == _kapaliGoster) a];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('İş akışları', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh)),
              const SizedBox(width: 4),
              FilledButton.icon(onPressed: _yeni, icon: const Icon(Icons.add), label: const Text('Yeni iş akışı')),
            ]),
            const SizedBox(height: 8),
            if (_hata != null) Text(_hata!, style: const TextStyle(color: Colors.red)),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: false, label: Text('Açık')), ButtonSegment(value: true, label: Text('Tamamlanan'))],
              selected: {_kapaliGoster},
              onSelectionChanged: (v) => setState(() => _kapaliGoster = v.first),
            ),
            const SizedBox(height: 10),
            if (liste.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('İş akışı yok. Şirket kuruluşu, adres veya ortak değişikliği, kapanış gibi çok adımlı işleri buradan takip edebilirsin.'),
              ),
            for (final a in liste)
              Builder(builder: (_) {
                final id = (a['id'] as num).toInt();
                final adimlar = _adimlar[id] ?? [];
                final biten = adimlar.where((s) => s['tamam'] == true).length;
                final geciken = adimlar.where(_gecikti).length;
                final hepsi = adimlar.isNotEmpty && biten == adimlar.length;
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  child: ExpansionTile(
                    title: Text('${a['baslik']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${_firmaAdi(a)} • $biten / ${adimlar.length} adım${geciken > 0 ? ' • $geciken adım gecikti' : ''}',
                      style: TextStyle(color: geciken > 0 ? const Color(0xFFC62828) : Colors.black87),
                    ),
                    leading: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(value: adimlar.isEmpty ? 0 : biten / adimlar.length, strokeWidth: 4, backgroundColor: Colors.black12),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
                    children: [
                      for (final s in adimlar) _adimSatiri(s, id),
                      Row(children: [
                        TextButton.icon(onPressed: () => _adimDuzenle(id), icon: const Icon(Icons.add, size: 18), label: const Text('Adım ekle')),
                        const Spacer(),
                        if (a['kapandi'] != true)
                          TextButton.icon(
                            onPressed: () => _kapat(a, true),
                            icon: Icon(Icons.task_alt, size: 18, color: hepsi ? const Color(0xFF2E7D32) : null),
                            label: Text(hepsi ? 'Tamamlandı olarak kapat' : 'Kapat'),
                          )
                        else
                          TextButton.icon(onPressed: () => _kapat(a, false), icon: const Icon(Icons.undo, size: 18), label: const Text('Yeniden aç')),
                        TextButton.icon(onPressed: () => _akisSil(a), icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Sil')),
                      ]),
                    ],
                  ),
                );
              }),
          ]),
        ),
      ),
    ]);
  }
}
