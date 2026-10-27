import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'firmalar.dart';
import 'secili_firma.dart';

part 'toplu_yukle.dart';

/// Yüklenebilecek belge türleri: 4 beyanname + tüm beyannamelerin tahakkuk fişleri.
enum BelgeTuru {
  kdvBeyannamesi('KDV Beyannamesi'),
  muhtasarBeyannamesi('Muhtasar ve Prim Hizmet Beyannamesi'),
  gelirVergisi('Gelir Vergisi Beyannamesi'),
  kurumlarVergisi('Kurumlar Vergisi Beyannamesi'),
  geciciVergi('Geçici Vergi Beyannamesi'),
  sgkHizmet('SGK Hizmet Dökümü'),
  tahakkuk('Tahakkuk Fişi');

  final String ad;
  const BelgeTuru(this.ad);
}

const _tahakkukBeyannameleri = [
  'KDV',
  'Muhtasar ve Prim Hizmet',
  'Damga Vergisi',
  'Gelir Vergisi',
  'Kurumlar Vergisi',
  'Geçici Vergi',
  'SGK Prim',
  'Diğer',
];

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _geciciDonemler = [
  '1. Geçici Vergi Dönemi (Ocak-Mart)',
  '2. Geçici Vergi Dönemi (Nisan-Haziran)',
  '3. Geçici Vergi Dönemi (Temmuz-Eylül)',
  '4. Geçici Vergi Dönemi (Ekim-Aralık)',
];

List<String> _donemler(BelgeTuru t) => switch (t) {
      BelgeTuru.gelirVergisi || BelgeTuru.kurumlarVergisi => ['Yıllık'],
      BelgeTuru.geciciVergi => _geciciDonemler,
      BelgeTuru.sgkHizmet || BelgeTuru.kdvBeyannamesi || BelgeTuru.muhtasarBeyannamesi => _aylar,
      BelgeTuru.tahakkuk => [..._aylar, ..._geciciDonemler, 'Yıllık'],
    };

String _tarihYaz(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _sqlTarih(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Belgeleri dönem sırasına dizmek için: aylar 0-11, geçici vergi dönemleri ilgili ayın sonrasına, yıllık en sona.
double _donemSirasi(String d) {
  final i = _aylar.indexOf(d);
  if (i >= 0) return i.toDouble();
  final g = _geciciDonemler.indexOf(d);
  if (g >= 0) return g * 3 + 2.5;
  return 12;
}

class Belge {
  final int id, firmaId, yil;
  final BelgeTuru tur;
  final String beyanname; // tahakkuk fişinde hangi beyannameye ait
  final String donem, dosyaAdi;
  final String yol; // Supabase Storage yolu
  final DateTime yuklenme;
  final bool odendi;
  final DateTime? odemeTarihi;
  Belge({
    required this.id,
    required this.firmaId,
    required this.tur,
    this.beyanname = '',
    required this.yil,
    required this.donem,
    required this.dosyaAdi,
    required this.yol,
    required this.yuklenme,
    this.odendi = false,
    this.odemeTarihi,
  });

  factory Belge.fromMap(Map<String, dynamic> m) => Belge(
        id: m['id'] as int,
        firmaId: m['firma_id'] as int,
        tur: BelgeTuru.values.firstWhere((t) => t.name == m['tur'], orElse: () => BelgeTuru.tahakkuk),
        beyanname: (m['beyanname'] ?? '') as String,
        yil: m['yil'] as int,
        donem: m['donem'] as String,
        dosyaAdi: m['dosya_adi'] as String,
        yol: m['yol'] as String,
        yuklenme: DateTime.parse(m['yuklenme'] as String).toLocal(),
        odendi: (m['odendi'] ?? false) as bool,
        odemeTarihi: m['odeme_tarihi'] == null ? null : DateTime.parse(m['odeme_tarihi'] as String),
      );

  String get baslik => (tur == BelgeTuru.tahakkuk && beyanname.isNotEmpty) ? 'Tahakkuk Fişi: $beyanname' : tur.ad;
}

/// firmaId doluysa (firma kullanıcısı) yalnızca o firmanın belgelerini görür ve indirir.
/// Boşsa (yönetici) firma seçer, belge yükler ve siler.
class BeyannamelerSayfasi extends StatefulWidget {
  final int? firmaId;
  const BeyannamelerSayfasi({super.key, this.firmaId});
  @override
  State<BeyannamelerSayfasi> createState() => _BeyannamelerSayfasiState();
}

// Başka bölüme gidip dönünce kaldığın firmadan devam etmek için (uygulama açık kaldığı sürece).
int? _sonBeyannameFirmaId;

class _BeyannamelerSayfasiState extends State<BeyannamelerSayfasi> {
  int? _firmaId;
  int? _yilFiltre;
  BelgeTuru? _turFiltre;

  final List<Belge> _belgeler = [];
  bool _yukleniyor = true;

  bool get _yonetici => widget.firmaId == null;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final f = FirmaDeposu.ornek.liste;
    final sonVar = _sonBeyannameFirmaId != null && f.any((x) => x.id == _sonBeyannameFirmaId);
    _firmaId = widget.firmaId ?? seciliFirmaId.value ?? (sonVar ? _sonBeyannameFirmaId : (f.isEmpty ? null : f.first.id));
    seciliFirmaId.addListener(_firmaDegisti);
    _baslat();
  }

  @override
  void dispose() {
    seciliFirmaId.removeListener(_firmaDegisti);
    super.dispose();
  }

  /// Üst çubuktan başka firma seçilince yeniden yükler.
  void _firmaDegisti() {
    if (widget.firmaId != null) return;
    final v = seciliFirmaId.value;
    if (v == _firmaId) return;
    setState(() {
      _firmaId = v;
      _yilFiltre = null;
    });
    _getir();
  }

  /// Firma listesi henüz yüklenmediyse önce yükler.
  Future<void> _baslat() async {
    if (widget.firmaId == null && _firmaId == null) {
      try {
        await FirmaDeposu.ornek.yukle();
      } catch (_) {}
      final f = FirmaDeposu.ornek.liste;
      if (mounted && f.isNotEmpty) {
        final sonVar = _sonBeyannameFirmaId != null && f.any((x) => x.id == _sonBeyannameFirmaId);
        _firmaId = sonVar ? _sonBeyannameFirmaId : f.first.id;
      }
    }
    if (mounted) await _getir();
  }

  /// Seçili firmanın belgelerini veritabanından alır.
  Future<void> _getir() async {
    final firma = _firmaId;
    if (widget.firmaId == null) _sonBeyannameFirmaId = firma;
    if (firma == null) {
      setState(() {
        _belgeler.clear();
        _yukleniyor = false;
      });
      return;
    }
    setState(() => _yukleniyor = true);
    try {
      final rows = await _db.from('belgeler').select().eq('firma_id', firma).order('yuklenme', ascending: false);
      _belgeler
        ..clear()
        ..addAll([for (final m in rows) Belge.fromMap(m)]);
    } catch (e) {
      if (mounted) _mesaj('Belgeler yüklenemedi: $e');
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  List<Belge> get _firmaBelgeleri => _belgeler;

  List<Belge> get _liste => (_firmaBelgeleri
      .where((b) => (_yilFiltre == null || b.yil == _yilFiltre) && (_turFiltre == null || b.tur == _turFiltre))
      .toList()
    ..sort((a, b) {
      var c = b.yil.compareTo(a.yil);
      if (c == 0) c = _donemSirasi(b.donem).compareTo(_donemSirasi(a.donem));
      if (c == 0) c = a.baslik.compareTo(b.baslik);
      return c != 0 ? c : b.yuklenme.compareTo(a.yuklenme);
    }));

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _secim<T>(String etiket, T deger, List<T> liste, String Function(T) yazi, void Function(T) degisti) =>
      InputDecorator(
        decoration: InputDecoration(labelText: etiket),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: deger,
            items: [for (final x in liste) DropdownMenuItem<T>(value: x, child: Text(yazi(x)))],
            onChanged: (v) {
              if (v != null) degisti(v);
            },
          ),
        ),
      );

  Future<void> _yukle() async {
    if (_firmaId == null) {
      _mesaj('Önce Firmalar bölümünden bir firma ekle.');
      return;
    }
    final simdi = DateTime.now();
    var tur = BelgeTuru.tahakkuk;
    var beyanname = _tahakkukBeyannameleri.first;
    var yil = simdi.year;
    var donem = _donemler(tur).first;
    var dosyalar = <PlatformFile>[];
    String? hata;
    var mesgul = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Belge yükle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _secim<BelgeTuru>('Belge türü', tur, BelgeTuru.values, (t) => t.ad, (t) {
                setD(() {
                  tur = t;
                  donem = _donemler(t).first;
                });
              }),
              if (tur == BelgeTuru.tahakkuk) ...[
                const SizedBox(height: 12),
                _secim<String>('Hangi beyannamenin tahakkuk fişi', beyanname, _tahakkukBeyannameleri, (s) => s,
                    (s) => setD(() => beyanname = s)),
              ],
              const SizedBox(height: 12),
              _secim<int>('Yıl', yil, [for (var y = simdi.year + 1; y >= simdi.year - 5; y--) y], (y) => '$y',
                  (y) => setD(() => yil = y)),
              const SizedBox(height: 12),
              _secim<String>('Dönem', donem, _donemler(tur), (s) => s, (s) => setD(() => donem = s)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    allowMultiple: true,
                    withData: true,
                  );
                  if (r != null) setD(() => dosyalar = r.files.where((f) => f.bytes != null).toList());
                },
                icon: const Icon(Icons.attach_file),
                label: Text(dosyalar.isEmpty ? 'PDF seç (birden fazla seçilebilir)' : '${dosyalar.length} dosya seçildi'),
              ),
              for (final f in dosyalar)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(f.name, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                ),
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(hata!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: mesgul
                  ? null
                  : () async {
                      if (dosyalar.isEmpty) {
                        setD(() => hata = 'En az bir PDF dosyası seç');
                        return;
                      }
                      setD(() {
                        hata = null;
                        mesgul = true;
                      });
                      try {
                        final damga = DateTime.now().microsecondsSinceEpoch;
                        var sira = 0;
                        for (final f in dosyalar) {
                          final yol = 'firma_$_firmaId/belgeler/${damga}_${sira++}.pdf';
                          await _db.storage
                              .from('belgeler')
                              .uploadBinary(yol, f.bytes!, fileOptions: const FileOptions(contentType: 'application/pdf'));
                          await _db.from('belgeler').insert({
                            'firma_id': _firmaId,
                            'tur': tur.name,
                            'beyanname': tur == BelgeTuru.tahakkuk ? beyanname : '',
                            'yil': yil,
                            'donem': donem,
                            'dosya_adi': f.name,
                            'yol': yol,
                          });
                        }
                        await _getir();
                        if (c.mounted) Navigator.pop(c);
                        _mesaj('${dosyalar.length} belge yüklendi.');
                      } catch (e) {
                        setD(() {
                          hata = 'Yüklenemedi: $e';
                          mesgul = false;
                        });
                      }
                    },
              child: Text(mesgul ? 'Yükleniyor...' : 'Yükle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _indir(Belge b) async {
    final ad = b.dosyaAdi.toLowerCase().endsWith('.pdf') ? b.dosyaAdi.substring(0, b.dosyaAdi.length - 4) : b.dosyaAdi;
    final dynamic fs = FileSaver.instance;
    try {
      final veri = await _db.storage.from('belgeler').download(b.yol);
      try {
        await fs.saveFile(name: ad, bytes: veri, fileExtension: 'pdf', mimeType: MimeType.other);
      } on NoSuchMethodError {
        await fs.saveFile(name: ad, bytes: veri, ext: 'pdf', mimeType: MimeType.other);
      }
    } catch (e) {
      _mesaj('Dosya indirilemedi: $e');
    }
  }

  Future<void> _sil(Belge b) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Belge silinsin mi?'),
        content: Text('${b.baslik}\n${b.donem} ${b.yil}\n${b.dosyaAdi}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _db.storage.from('belgeler').remove([b.yol]);
      await _db.from('belgeler').delete().eq('id', b.id);
      await _getir();
    } catch (e) {
      _mesaj('Silinemedi: $e');
    }
  }

  /// Tahakkuk fişinin ödendi bilgisini değiştirir (sadece yönetici).
  Future<void> _odemeDegistir(Belge b) async {
    final yeni = !b.odendi;
    try {
      await _db
          .from('belgeler')
          .update({'odendi': yeni, 'odeme_tarihi': yeni ? _sqlTarih(DateTime.now()) : null}).eq('id', b.id);
      await _getir();
    } catch (e) {
      _mesaj('Kaydedilemedi: $e');
    }
  }

  Widget _odemeButonu(Belge b) {
    const yesil = Color(0xFF2E7D32);
    final tikla = _yonetici ? () => _odemeDegistir(b) : null;
    if (b.odendi) {
      final tarih = b.odemeTarihi == null ? '' : ' (${_tarihYaz(b.odemeTarihi!)})';
      return FilledButton.icon(
        onPressed: tikla,
        icon: const Icon(Icons.check_circle, size: 18),
        label: Text('Ödendi$tarih'),
        style: FilledButton.styleFrom(
          backgroundColor: yesil,
          disabledBackgroundColor: yesil,
          disabledForegroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: tikla,
      icon: const Icon(Icons.payments_outlined, size: 18),
      label: Text(_yonetici ? 'Ödendi olarak işaretle' : 'Ödenmedi'),
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }

  Widget _firmaSecici() {
    if (widget.firmaId == null) return const SizedBox.shrink(); // yönetici firmayı üst çubuktan seçer
    final firmalar = FirmaDeposu.ornek.liste;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        const Icon(Icons.business_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: !_yonetici
              ? Text(FirmaDeposu.ornek.bul(widget.firmaId!)?.unvan ?? '', style: const TextStyle(fontWeight: FontWeight.w600))
              : DropdownButton<int>(
                  isExpanded: true,
                  value: firmalar.any((f) => f.id == _firmaId) ? _firmaId : null,
                  hint: const Text('Firma seç'),
                  items: [for (final f in firmalar) DropdownMenuItem(value: f.id, child: Text(f.unvan))],
                  onChanged: (v) {
                    setState(() {
                      _firmaId = v;
                      _yilFiltre = null;
                    });
                    _getir();
                  },
                ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liste = _liste;
    final yillar = ({for (final b in _firmaBelgeleri) b.yil}.toList()..sort((a, b) => b.compareTo(a)));
    final yilDegeri = yillar.contains(_yilFiltre) ? _yilFiltre : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _yonetici
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              FloatingActionButton.extended(
                heroTag: 'toplu-yukle',
                onPressed: _topluYukle,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Toplu yükle (otomatik)'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'belge-yukle',
                onPressed: _yukle,
                icon: const Icon(Icons.upload_file),
                label: const Text('Belge yükle'),
              ),
            ])
          : null,
      body: Column(children: [
        if (_yukleniyor) const LinearProgressIndicator(),
        _firmaSecici(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<int?>(
              value: yilDegeri,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Tüm yıllar')),
                for (final y in yillar) DropdownMenuItem<int?>(value: y, child: Text('$y')),
              ],
              onChanged: (v) => setState(() => _yilFiltre = v),
            ),
            DropdownButton<BelgeTuru?>(
              value: _turFiltre,
              items: [
                const DropdownMenuItem<BelgeTuru?>(value: null, child: Text('Tüm belgeler')),
                for (final t in BelgeTuru.values) DropdownMenuItem<BelgeTuru?>(value: t, child: Text(t.ad)),
              ],
              onChanged: (v) => setState(() => _turFiltre = v),
            ),
          ]),
        ),
        Expanded(
          child: liste.isEmpty
              ? Center(
                  child: Text(_yonetici ? 'Bu firma için belge yok. "Belge yükle" ile ekle.' : 'Henüz belge yok.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: liste.length,
                  itemBuilder: (c, i) {
                    final b = liste[i];
                    return Card(
                      elevation: 0,
                      color: b.odendi ? const Color(0xFFEAF6EC) : Colors.white,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        onTap: () => _indir(b),
                        leading: Icon(Icons.picture_as_pdf_outlined, color: Colors.red.shade700),
                        title: Text(b.baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${b.donem} ${b.yil}\n${b.dosyaAdi}   (yüklenme: ${_tarihYaz(b.yuklenme)})'),
                          if (b.tur == BelgeTuru.tahakkuk)
                            Padding(padding: const EdgeInsets.only(top: 6), child: _odemeButonu(b)),
                        ]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'İndir',
                            icon: const Icon(Icons.download_outlined),
                            onPressed: () => _indir(b),
                          ),
                          if (_yonetici)
                            IconButton(
                              tooltip: 'Sil',
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                              onPressed: () => _sil(b),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// YAMA2-UYGULANDI
