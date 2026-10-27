import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bordro_cikti.dart' show bordroKaydet;

const arsivKategorileri = [
  'İmza sirküleri',
  'Vekâletname',
  'Kira sözleşmesi',
  'Ticaret sicil gazetesi',
  'Faaliyet belgesi',
  'Vergi levhası',
  'Sözleşme',
  'SGK belgesi',
  'Mali mühür',
  'E-imza',
  'E-defter / e-fatura entegratör sözleşmesi',
  'Kontör / paket',
  'Yetki belgesi (GİB / SGK)',
  'Diğer',
];

String _dosyaAdiTemizle(String s) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosucgiosu';
  var r = s;
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

String _tarihYaz(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
String _tarihSql(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Firmanın imza sirküleri, vekâletname, kira sözleşmesi gibi belgelerinin arşivi. Mükellef göremez.
class FirmaArsivSayfasi extends StatefulWidget {
  final int firmaId;
  const FirmaArsivSayfasi({super.key, required this.firmaId});
  @override
  State<FirmaArsivSayfasi> createState() => _FirmaArsivSayfasiState();
}

class _FirmaArsivSayfasiState extends State<FirmaArsivSayfasi> {
  SupabaseClient get _db => Supabase.instance.client;
  List<Map<String, dynamic>> _liste = [];
  List<Map<String, dynamic>> _beyBelgeler = [];
  bool _yukleniyor = true;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void didUpdateWidget(covariant FirmaArsivSayfasi eski) {
    super.didUpdateWidget(eski);
    if (eski.firmaId != widget.firmaId) _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await _db.from('firma_belge').select().eq('firma_id', widget.firmaId).order('kategori').order('ad');
      _liste = List<Map<String, dynamic>>.from(r);
      try {
        final b = await _db.from('belgeler').select().eq('firma_id', widget.firmaId).order('yil', ascending: false).order('yuklenme', ascending: false);
        _beyBelgeler = List<Map<String, dynamic>>.from(b);
      } catch (_) {
        _beyBelgeler = [];
      }
      _hata = null;
    } catch (e) {
      _hata = 'Belgeler alınamadı: $e\n\nsupabase_arsiv.sql dosyasını çalıştırdın mı?';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  DateTime? _gecerlilik(Map<String, dynamic> b) => b['gecerlilik'] == null ? null : DateTime.parse(b['gecerlilik'] as String);

  Future<void> _form({Map<String, dynamic>? mevcut}) async {
    final yeni = mevcut == null;
    var kategori = (mevcut?['kategori'] ?? 'İmza sirküleri') as String;
    if (!arsivKategorileri.contains(kategori)) kategori = 'Diğer';
    final ad = TextEditingController(text: (mevcut?['ad'] ?? '') as String);
    final not = TextEditingController(text: (mevcut?['aciklama'] ?? '') as String);
    DateTime? gecerlilik = mevcut == null ? null : _gecerlilik(mevcut);
    PlatformFile? dosya;
    String? hata;
    var mesgul = false;
    final tamam = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(yeni ? 'Belge ekle' : 'Belgeyi düzenle'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<String>(
                  initialValue: kategori,
                  decoration: const InputDecoration(labelText: 'Belge türü'),
                  items: [for (final k in arsivKategorileri) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => setD(() {
                    kategori = v ?? kategori;
                    if (ad.text.trim().isEmpty) ad.text = kategori;
                  }),
                ),
                const SizedBox(height: 10),
                TextField(controller: ad, decoration: const InputDecoration(labelText: 'Belge adı')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: c,
                          initialDate: gecerlilik ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          locale: const Locale('tr', 'TR'),
                        );
                        if (d != null) setD(() => gecerlilik = d);
                      },
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(gecerlilik == null ? 'Geçerlilik bitiş tarihi (isteğe bağlı)' : 'Geçerlilik: ${_tarihYaz(gecerlilik!)}'),
                    ),
                  ),
                  if (gecerlilik != null) IconButton(tooltip: 'Tarihi kaldır', onPressed: () => setD(() => gecerlilik = null), icon: const Icon(Icons.clear)),
                ]),
                const SizedBox(height: 10),
                TextField(controller: not, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
                if (yeni) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final r = await FilePicker.platform.pickFiles(withData: true);
                      if (r != null && r.files.isNotEmpty && r.files.first.bytes != null) {
                        setD(() {
                          dosya = r.files.first;
                          if (ad.text.trim().isEmpty) ad.text = kategori;
                        });
                      }
                    },
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(dosya == null ? 'Dosya seç' : dosya!.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
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
                      if (ad.text.trim().isEmpty) {
                        setD(() => hata = 'Belge adı yaz');
                        return;
                      }
                      if (yeni && dosya == null) {
                        setD(() => hata = 'Dosya seç');
                        return;
                      }
                      setD(() {
                        mesgul = true;
                        hata = null;
                      });
                      try {
                        final alanlar = {
                          'kategori': kategori,
                          'ad': ad.text.trim(),
                          'gecerlilik': gecerlilik == null ? null : _tarihSql(gecerlilik!),
                          'aciklama': not.text.trim(),
                        };
                        if (yeni) {
                          final yol = 'arsiv_${widget.firmaId}/${DateTime.now().millisecondsSinceEpoch}_${_dosyaAdiTemizle(dosya!.name)}';
                          await _db.storage.from('belgeler').uploadBinary(yol, dosya!.bytes!);
                          try {
                            await _db.from('firma_belge').insert({...alanlar, 'firma_id': widget.firmaId, 'dosya_adi': dosya!.name, 'yol': yol});
                          } catch (e) {
                            await _db.storage.from('belgeler').remove([yol]);
                            rethrow;
                          }
                        } else {
                          await _db.from('firma_belge').update(alanlar).eq('id', mevcut['id']);
                        }
                        if (c.mounted) Navigator.pop(c, true);
                      } catch (e) {
                        setD(() {
                          mesgul = false;
                          hata = '$e';
                        });
                      }
                    },
              child: Text(mesgul ? 'Kaydediliyor...' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (tamam == true) {
      _mesaj(yeni ? 'Belge eklendi.' : 'Kaydedildi.');
      _yukle();
    }
  }

  Future<void> _indir(Map<String, dynamic> b) async {
    try {
      final veri = await _db.storage.from('belgeler').download(b['yol'] as String);
      final tam = (b['dosya_adi'] ?? '') as String;
      final nokta = tam.lastIndexOf('.');
      final uzanti = nokta > 0 && nokta < tam.length - 1 ? tam.substring(nokta + 1) : 'pdf';
      final ad = nokta > 0 ? tam.substring(0, nokta) : (tam.isEmpty ? 'belge' : tam);
      await bordroKaydet(ad, veri, uzanti);
    } catch (e) {
      _mesaj('Dosya indirilemedi: $e');
    }
  }

  Future<void> _sil(Map<String, dynamic> b) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Belge silinsin mi?'),
        content: Text('"${b['ad']}" dosyası kalıcı olarak silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _db.from('firma_belge').delete().eq('id', b['id']);
      try {
        await _db.storage.from('belgeler').remove([b['yol'] as String]);
      } catch (_) {}
      _yukle();
    } catch (e) {
      _mesaj('Silinemedi: $e');
    }
  }

  Widget _gecerlilikRozeti(DateTime? g) {
    if (g == null) return const SizedBox.shrink();
    final bugun = DateTime.now();
    final fark = DateTime(g.year, g.month, g.day).difference(DateTime(bugun.year, bugun.month, bugun.day)).inDays;
    Color renk = Colors.black87;
    String yazi = 'Geçerlilik: ${_tarihYaz(g)}';
    if (fark < 0) {
      renk = const Color(0xFFC62828);
      yazi = 'Süresi doldu (${_tarihYaz(g)})';
    } else if (fark <= 30) {
      renk = const Color(0xFFEF6C00);
      yazi = fark == 0 ? 'Bugün bitiyor' : '$fark gün kaldı (${_tarihYaz(g)})';
    }
    return Text(yazi, style: TextStyle(color: renk, fontWeight: renk == Colors.black87 ? FontWeight.normal : FontWeight.w700, fontSize: 12));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'arsiv-ekle',
        onPressed: () => _form(),
        icon: const Icon(Icons.upload_file),
        label: const Text('Belge ekle'),
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : _hata != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_hata!, textAlign: TextAlign.center)))
              : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      children: [
                        if (_liste.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Bu firma için arşivde belge yok. İmza sirküleri, vekâletname, kira sözleşmesi gibi belgeleri ekleyebilirsin. '
                                'Mükellef bu belgeleri göremez.', textAlign: TextAlign.center),
                          ),
                        for (final b in _liste)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(b['ad'] as String),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${b['kategori']}  |  ${b['dosya_adi']}', style: const TextStyle(fontSize: 12)),
                                _gecerlilikRozeti(_gecerlilik(b)),
                                if (((b['aciklama'] ?? '') as String).isNotEmpty) Text(b['aciklama'] as String, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                              ]),
                              onTap: () => _indir(b),
                              trailing: PopupMenuButton<int>(
                                onSelected: (v) {
                                  if (v == 1) _indir(b);
                                  if (v == 2) _form(mevcut: b);
                                  if (v == 3) _sil(b);
                                },
                                itemBuilder: (c) => const [
                                  PopupMenuItem(value: 1, child: Text('İndir')),
                                  PopupMenuItem(value: 2, child: Text('Düzenle')),
                                  PopupMenuItem(value: 3, child: Text('Sil')),
                                ],
                              ),
                            ),
                          ),
                        if (_beyBelgeler.isNotEmpty) ..._beyanBolumu(),
                      ],
                    ),
    );
  }

  static const _beyTurAd = {
    'kdvBeyannamesi': 'KDV Beyannamesi',
    'muhtasarBeyannamesi': 'Muhtasar ve Prim Hizmet',
    'gelirVergisi': 'Gelir Vergisi',
    'kurumlarVergisi': 'Kurumlar Vergisi',
    'geciciVergi': 'Geçici Vergi',
    'sgkHizmet': 'SGK Hizmet Dökümü',
    'tahakkuk': 'Tahakkuk Fişi',
  };

  Future<void> _beyIndir(Map<String, dynamic> b) async {
    try {
      final veri = await _db.storage.from('belgeler').download(b['yol'] as String);
      final tam = (b['dosya_adi'] ?? '') as String;
      final ad = tam.toLowerCase().endsWith('.pdf') ? tam.substring(0, tam.length - 4) : (tam.isEmpty ? 'belge' : tam);
      await bordroKaydet(ad, veri, 'pdf');
    } catch (e) {
      _mesaj('Dosya indirilemedi: $e');
    }
  }

  List<Widget> _beyanBolumu() {
    final yillar = <int>[];
    for (final b in _beyBelgeler) {
      final y = (b['yil'] as num).toInt();
      if (!yillar.contains(y)) yillar.add(y);
    }
    return [
      const Padding(
        padding: EdgeInsets.only(top: 20, bottom: 4),
        child: Text('Beyanname ve tahakkuk belgeleri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('Beyannameler sekmesinden yüklenen belgeler buraya yıl ve döneme göre kendiliğinden düşer.',
            style: TextStyle(fontSize: 12, color: Colors.black87)),
      ),
      for (final y in yillar)
        Card(
          child: ExpansionTile(
            initiallyExpanded: y == yillar.first,
            title: Text('$y  (${_beyBelgeler.where((b) => (b['yil'] as num).toInt() == y).length} belge)'),
            children: [
              for (final b in _beyBelgeler.where((b) => (b['yil'] as num).toInt() == y))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: Text('${_beyTurAd[b['tur']] ?? b['tur']}${'${b['beyanname'] ?? ''}'.isEmpty ? '' : ' - ${b['beyanname']}'}'),
                  subtitle: Text('${b['donem']} ${b['yil']}  |  ${b['dosya_adi']}'),
                  trailing: const Icon(Icons.download_outlined, size: 18),
                  onTap: () => _beyIndir(b),
                ),
            ],
          ),
        ),
    ];
  }
}
