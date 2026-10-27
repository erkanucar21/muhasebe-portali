import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dogrulama.dart';
import 'faaliyet_kodlari.dart';
import 'firma_acilis.dart';
import 'tarih_alani.dart';
import 'luca_aktar.dart';
import 'yedek.dart';
import 'toplu_aktar.dart';
import 'secili_firma.dart';
import 'firma_sayfasi.dart';
import 'hesap_islem.dart';

import 'ayarlar.dart';

String _tarihYaz(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _sqlTarih(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _tarihCoz(String s) {
  final p = s.trim().split('.');
  if (p.length != 3) return null;
  final g = int.tryParse(p[0]), a = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (g == null || a == null || y == null || y < 1900) return null;
  final d = DateTime(y, a, g);
  return (d.day == g && d.month == a) ? d : null;
}

/// Türkçe alfabe sırasına göre karşılaştırır (ç, ğ, ı, ö, ş, ü doğru yerde olur, büyük/küçük harf fark etmez).
int trKarsilastir(String a, String b) {
  const sira = '0123456789abcçdefgğhıijklmnoöpqrsştuüvwxyz';
  String duz(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final x = duz(a), y = duz(b);
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final p = sira.indexOf(x[i]), q = sira.indexOf(y[i]);
    final pp = p < 0 ? x.codeUnitAt(i) - 1000 : p;
    final qq = q < 0 ? y.codeUnitAt(i) - 1000 : q;
    if (pp != qq) return pp.compareTo(qq);
  }
  return x.length.compareTo(y.length);
}

/// Mükellefin yazdığı firma adından, Supabase giriş hesabı için sahte bir e-posta üretir.
/// Örn. "Yılmaz Ticaret" -> yilmazticaret@muhasebeportal.app (mükellef bunu hiç görmez).
String girisEposta(String ad) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosucgiosu';
  var r = ad.trim();
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  r = r.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return '$r@muhasebeportal.app';
}

class Firma {
  final int id;
  String unvan, vergiDairesi, vergiNo, tcNo, faaliyetKodu, faaliyetAciklama;
  String sgkSicilNo, ticaretSicilNo;
  String sgkSubesi, mersisNo, adres; // bordro başlığı için
  String not; // yönetici notu (yalnızca müşavir görür)
  String telefon; // WhatsApp / iletişim
  String eposta; // duyuru e-postaları için
  DateTime? kurulus;
  String girisAdi; // mükellefin giriş adı (boşsa giriş hesabı yok)
  bool girisAktif; // false ise giriş kapalı
  bool eDefter; // e-defter tutuyor mu
  bool gekap; // GEKAP beyanı var mı
  String eDefterTercih; // e-defter yükleme tercihi: 'aylik' veya 'gecici' (geçici vergi dönemleri)
  String? vergiLevhasiYol; // Supabase Storage yolu
  String vergiLevhasiAdi;
  Firma(
    this.id,
    this.unvan, {
    this.vergiDairesi = '',
    this.vergiNo = '',
    this.tcNo = '',
    this.faaliyetKodu = '',
    this.faaliyetAciklama = '',
    this.sgkSicilNo = '',
    this.ticaretSicilNo = '',
    this.sgkSubesi = '',
    this.mersisNo = '',
    this.adres = '',
    this.not = '',
    this.telefon = '',
    this.eposta = '',
    this.kurulus,
    this.girisAdi = '',
    this.girisAktif = true,
    this.eDefter = false,
    this.gekap = false,
    this.eDefterTercih = 'aylik',
    this.vergiLevhasiYol,
    this.vergiLevhasiAdi = '',
  });

  bool get erisimVar => girisAdi.isNotEmpty;
  bool get levhaVar => vergiLevhasiYol != null;

  factory Firma.fromMap(Map<String, dynamic> m, {String girisAdi = '', bool aktif = true}) => Firma(
        m['id'] as int,
        m['unvan'] as String,
        vergiDairesi: (m['vergi_dairesi'] ?? '') as String,
        vergiNo: (m['vergi_no'] ?? '') as String,
        tcNo: (m['tc_no'] ?? '') as String,
        faaliyetKodu: (m['faaliyet_kodu'] ?? '') as String,
        faaliyetAciklama: (m['faaliyet_aciklama'] ?? '') as String,
        sgkSicilNo: (m['sgk_sicil_no'] ?? '') as String,
        ticaretSicilNo: (m['ticaret_sicil_no'] ?? '') as String,
        sgkSubesi: (m['sgk_subesi'] ?? '') as String,
        mersisNo: (m['mersis_no'] ?? '') as String,
        adres: (m['adres'] ?? '') as String,
        not: (m['not_defteri'] ?? '') as String,
        telefon: (m['telefon'] ?? '') as String,
        eposta: (m['eposta'] ?? '') as String,
        kurulus: m['kurulus'] == null ? null : DateTime.parse(m['kurulus'] as String),
        girisAdi: girisAdi,
        girisAktif: aktif,
        eDefter: (m['e_defter'] ?? false) as bool,
        gekap: (m['gekap'] ?? false) as bool,
        eDefterTercih: (m['e_defter_tercih'] ?? 'aylik') as String,
        vergiLevhasiYol: m['vergi_levhasi_yol'] as String?,
        vergiLevhasiAdi: (m['vergi_levhasi_adi'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'unvan': unvan,
        'vergi_dairesi': vergiDairesi,
        'vergi_no': vergiNo,
        'tc_no': tcNo,
        'faaliyet_kodu': faaliyetKodu,
        'faaliyet_aciklama': faaliyetAciklama,
        'sgk_sicil_no': sgkSicilNo,
        'ticaret_sicil_no': ticaretSicilNo,
        'sgk_subesi': sgkSubesi,
        'mersis_no': mersisNo,
        'adres': adres,
        'not_defteri': not,
        'telefon': telefon,
        'eposta': eposta,
        'e_defter': eDefter,
        'gekap': gekap,
        'e_defter_tercih': eDefterTercih,
        'kurulus': kurulus == null ? null : _sqlTarih(kurulus!),
      };
}

/// Firmalar Supabase'ten yüklenir. Yönetici hepsini, mükellef yalnızca kendi firmasını alır
/// (bu ayrımı veritabanındaki güvenlik kuralları yapar).
class FirmaDeposu {
  FirmaDeposu._();
  static final FirmaDeposu ornek = FirmaDeposu._();

  final List<Firma> liste = [];

  Future<void> yukle() async {
    final db = Supabase.instance.client;
    final firmalar = await db.from('firmalar').select().order('unvan');
    final hesaplar = <int, Map<String, dynamic>>{};
    final profiller = await db.from('profiller').select('firma_id, giris_adi, aktif').eq('rol', 'musteri');
    for (final p in profiller) {
      final id = p['firma_id'];
      if (id is int) hesaplar[id] = p;
    }
    liste
      ..clear()
      ..addAll([
        for (final m in firmalar)
          Firma.fromMap(m,
              girisAdi: (hesaplar[m['id'] as int]?['giris_adi'] ?? '') as String,
              aktif: (hesaplar[m['id'] as int]?['aktif'] ?? true) as bool),
      ]);
    liste.sort((a, b) => trKarsilastir(a.unvan, b.unvan));
  }

  Firma? bul(int id) {
    for (final f in liste) {
      if (f.id == id) return f;
    }
    return null;
  }
}

class FirmalarSayfasi extends StatefulWidget {
  final int? firmaId; // doluysa mükellef: yalnızca kendi firmasını görür
  const FirmalarSayfasi({super.key, this.firmaId});
  @override
  State<FirmalarSayfasi> createState() => _FirmalarSayfasiState();
}

class _FirmalarSayfasiState extends State<FirmalarSayfasi> {
  final _depo = FirmaDeposu.ornek;
  SupabaseClient get _db => Supabase.instance.client;
  bool get _yonetici => widget.firmaId == null;

  final _aramaKutusu = TextEditingController();
  final _aramaOdagi = FocusNode();
  String _sorgu = '';

  static String _firmaKatla(String s) {
    const kaynak = 'çğıöşüÇĞİÖŞÜIâîû';
    const hedef = 'cgiosucgiosuiaiu';
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final k = kaynak.indexOf(ch);
      b.write(k >= 0 ? hedef[k] : ch.toLowerCase());
    }
    return b.toString();
  }

  // Ctrl+F / Cmd+F: tarayıcının kendi aramasını açmak yerine firma arama kutusuna gider
  bool _aramaKisayolu(KeyEvent e) {
    if (!mounted || e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyF) return false;
    final kk = HardwareKeyboard.instance;
    if (!(kk.isControlPressed || kk.isMetaPressed)) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _aramaOdagi.requestFocus();
    _aramaKutusu.selection = TextSelection(baseOffset: 0, extentOffset: _aramaKutusu.text.length);
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_aramaKisayolu);
    _yenile();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_aramaKisayolu);
    _aramaKutusu.dispose();
    _aramaOdagi.dispose();
    super.dispose();
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _yenile() async {
    try {
      await _depo.yukle();
    } catch (e) {
      if (mounted) _mesaj('Firmalar yüklenemedi: $e');
    }
    if (mounted) setState(() {});
  }

  Future<PlatformFile?> _pdfSec() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return null;
    return r.files.first;
  }

  Future<String> _levhaDepoya(int firmaId, Uint8List veri) async {
    final yol = 'firma_$firmaId/vergi_levhasi.pdf';
    await _db.storage
        .from('belgeler')
        .uploadBinary(yol, veri, fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'));
    return yol;
  }

  Future<void> _levhaYukle(Firma f) async {
    final d = await _pdfSec();
    if (d == null) return;
    try {
      final yol = await _levhaDepoya(f.id, d.bytes!);
      await _db.from('firmalar').update({'vergi_levhasi_yol': yol, 'vergi_levhasi_adi': d.name}).eq('id', f.id);
      await _yenile();
      _mesaj('Vergi levhası yüklendi.');
    } catch (e) {
      _mesaj('Yüklenemedi: $e');
    }
  }

  Future<void> _levhaIndir(Firma f) async {
    final yol = f.vergiLevhasiYol;
    if (yol == null) return;
    try {
      final veri = await _db.storage.from('belgeler').download(yol);
      final adi = f.vergiLevhasiAdi;
      final ad = adi.toLowerCase().endsWith('.pdf')
          ? adi.substring(0, adi.length - 4)
          : (adi.isEmpty ? 'vergi_levhasi' : adi);
      final dynamic fs = FileSaver.instance;
      try {
        await fs.saveFile(name: ad, bytes: veri, fileExtension: 'pdf', mimeType: MimeType.other);
      } on NoSuchMethodError {
        await fs.saveFile(name: ad, bytes: veri, ext: 'pdf', mimeType: MimeType.other);
      }
    } catch (e) {
      _mesaj('Dosya indirilemedi: $e');
    }
  }

  Widget _levhaButonu(Firma f) {
    if (f.levhaVar) {
      return FilledButton.tonalIcon(
        onPressed: () => _levhaIndir(f),
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Vergi levhası'),
        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
      );
    }
    if (_yonetici) {
      return OutlinedButton.icon(
        onPressed: () => _levhaYukle(f),
        icon: const Icon(Icons.upload_file, size: 18),
        label: const Text('Vergi levhası yükle'),
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      );
    }
    return const SizedBox.shrink();
  }

  /// Mükellef için giriş hesabı açar ve firmaya bağlar.
  /// (Ayrı bir Supabase istemcisi kullanmaz, yönetici oturumu bozulmasın diye doğrudan istek atar.)
  Future<void> _hesapOlustur(int firmaId, String girisAdi, String sifre) async {
    final eposta = girisEposta(girisAdi);
    await authHesapOlustur(eposta, sifre);
    await _db.rpc('musteri_bagla', params: {'p_eposta': eposta, 'p_firma_id': firmaId, 'p_giris_adi': girisAdi.trim()});
    await _db.rpc('musteri_sifre_degistir', params: {'p_firma_id': firmaId, 'p_sifre': sifre});
  }

  /// Firmanın tüm işlerinin sekmeli sayfasını açar.
  Future<void> _firmaAc(Firma f) async {
    seciliFirmaId.value = f.id;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FirmaSayfasi(firmaId: f.id, duzenle: () => _form(mevcut: FirmaDeposu.ornek.bul(f.id) ?? f)),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _form({Firma? mevcut}) async {
    final unvan = TextEditingController(text: mevcut?.unvan ?? '');
    final vDairesi = TextEditingController(text: mevcut?.vergiDairesi ?? '');
    final vergi = TextEditingController(text: mevcut?.vergiNo ?? '');
    final tc = TextEditingController(text: mevcut?.tcNo ?? '');
    final sgkSicil = TextEditingController(text: mevcut?.sgkSicilNo ?? '');
    final ticSicil = TextEditingController(text: mevcut?.ticaretSicilNo ?? '');
    final sgkSube = TextEditingController(text: mevcut?.sgkSubesi ?? '');
    final mersis = TextEditingController(text: mevcut?.mersisNo ?? '');
    final adres = TextEditingController(text: mevcut?.adres ?? '');
    final notDefteri = TextEditingController(text: mevcut?.not ?? '');
    final telefon = TextEditingController(text: mevcut?.telefon ?? '');
    final eposta = TextEditingController(text: mevcut?.eposta ?? '');
    final fKodu = TextEditingController(text: mevcut?.faaliyetKodu ?? '');
    final fAciklama = TextEditingController(text: mevcut?.faaliyetAciklama ?? '');
    final kurulus = TextEditingController(text: mevcut?.kurulus == null ? '' : _tarihYaz(mevcut!.kurulus!));
    final hesapVar0 = mevcut?.erisimVar ?? false;
    final girisAdi = TextEditingController(text: mevcut?.girisAdi ?? '');
    final sifre = TextEditingController();
    var girisAktif = mevcut?.girisAktif ?? true;
    var eDefter = mevcut?.eDefter ?? false;
    var gekap = mevcut?.gekap ?? false;
    var eDefterTercih = mevcut?.eDefterTercih ?? 'aylik';
    Uint8List? yeniLevha;
    var levhaVar = mevcut?.levhaVar ?? false;
    var levhaAdi = mevcut?.vergiLevhasiAdi ?? '';
    int? kayitliId = mevcut?.id;
    var mesgul = false;
    String? hata;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(mevcut == null ? 'Firma ekle' : 'Firma bilgileri'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: unvan,
                autofocus: mevcut == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Firma ünvanı'),
              ),
              TextField(
                controller: vDairesi,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Vergi dairesi'),
              ),
              TextField(
                controller: vergi,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: const InputDecoration(labelText: 'Vergi no (10 haneli)', counterText: ''),
              ),
              TextField(
                controller: tc,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: const InputDecoration(labelText: 'TC kimlik no (11 haneli)', counterText: ''),
              ),
              TextField(
                controller: sgkSicil,
                decoration: const InputDecoration(labelText: 'SGK sicil no'),
              ),
              TextField(
                controller: ticSicil,
                decoration: const InputDecoration(labelText: 'Ticaret sicil no'),
              ),
              TextField(
                controller: sgkSube,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'SGK şubesi (örn. BEYOĞLU SOSYAL GÜVENLİK MERKEZİ)'),
              ),
              TextField(
                controller: mersis,
                decoration: const InputDecoration(labelText: 'MERSİS no'),
              ),
              TextField(
                controller: adres,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Adres (bordroda görünür)'),
              ),
              if (_yonetici)
                TextField(
                  controller: telefon,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefon / WhatsApp', hintText: '0532 123 45 67'),
                ),
              if (_yonetici)
                TextField(
                  controller: eposta,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'İletişim e-postası (duyurular için)', hintText: 'ornek@firma.com'),
                ),
              if (_yonetici)
                TextField(
                  controller: notDefteri,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Müşavir notu (mükellefe gösterilmez)',
                    hintText: 'Örn. KDV\'yi ayın 25\'inde istiyor',
                  ),
                ),
              FaaliyetAlani(kod: fKodu, aciklama: fAciklama),
              TarihAlani(controller: kurulus, etiket: 'Kuruluş tarihi'),
              const SizedBox(height: 16),
              const Text('Vergi levhası', style: TextStyle(fontWeight: FontWeight.w700)),
              Row(children: [
                Expanded(child: Text(levhaVar ? levhaAdi : 'Yüklenmedi', overflow: TextOverflow.ellipsis)),
                TextButton(
                  onPressed: () async {
                    final d = await _pdfSec();
                    if (d != null) {
                      setD(() {
                        yeniLevha = d.bytes;
                        levhaAdi = d.name;
                        levhaVar = true;
                      });
                    }
                  },
                  child: Text(levhaVar ? 'Değiştir' : 'PDF seç'),
                ),
                if (levhaVar)
                  TextButton(
                    onPressed: () => setD(() {
                      yeniLevha = null;
                      levhaAdi = '';
                      levhaVar = false;
                    }),
                    child: const Text('Kaldır'),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Mükellef girişi', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Mükellef uygulamaya firma adı ve şifreyle girer. Giriş adını ve şifreyi sen belirlersin. '
                'Boş bırakırsan giriş hesabı açılmaz.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              TextField(
                controller: girisAdi,
                enabled: !hesapVar0,
                decoration: const InputDecoration(labelText: 'Giriş adı (firma adı)'),
              ),
              TextField(
                controller: sifre,
                decoration: InputDecoration(
                  labelText: hesapVar0 ? 'Yeni şifre (boş bırakırsan değişmez)' : 'Şifre (en az 8 karakter)',
                ),
              ),
              if (hesapVar0)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Girişe açık'),
                  value: girisAktif,
                  onChanged: (v) => setD(() => girisAktif = v),
                ),
              const SizedBox(height: 16),
              const Text('Beyanname kontrol listesi', style: TextStyle(fontWeight: FontWeight.w700)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('E-Defter var'),
                value: eDefter,
                onChanged: (v) => setD(() => eDefter = v),
              ),
              if (eDefter)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('Yükleme tercihi:'),
                    ChoiceChip(
                      label: const Text('Aylık'),
                      selected: eDefterTercih == 'aylik',
                      onSelected: (_) => setD(() => eDefterTercih = 'aylik'),
                    ),
                    ChoiceChip(
                      label: const Text('Geçici vergi dönemleri'),
                      selected: eDefterTercih == 'gecici',
                      onSelected: (_) => setD(() => eDefterTercih = 'gecici'),
                    ),
                  ]),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('GEKAP var'),
                value: gekap,
                onChanged: (v) => setD(() => gekap = v),
              ),
              if (hata != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(hata!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            if (mevcut != null)
              TextButton(
                onPressed: mesgul
                    ? null
                    : () async {
                        final onay = await showDialog<bool>(
                          context: c,
                          builder: (d) => AlertDialog(
                            title: Text('${mevcut.unvan} silinsin mi?'),
                            content: const Text('Bu firmanın personeli, izin kayıtları, beyanname kontrolleri, belgeleri ve giriş hesabı kalıcı olarak silinir. Geri alınamaz. Önce "Yedek al (Excel)" ile yedek almanı öneririm.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sil')),
                            ],
                          ),
                        );
                        if (onay != true) return;
                        try {
                          if (mevcut.levhaVar) await _db.storage.from('belgeler').remove([mevcut.vergiLevhasiYol!]);
                          await _db.from('firmalar').delete().eq('id', mevcut.id);
                          await _depo.yukle();
                          if (mounted) setState(() {});
                          if (c.mounted) Navigator.pop(c);
                        } catch (e) {
                          setD(() => hata = 'Silinemedi: $e');
                        }
                      },
                child: Text('Sil', style: TextStyle(color: Colors.red.shade700)),
              ),
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: mesgul
                  ? null
                  : () async {
                      final g = girisAdi.text.trim();
                      final s = sifre.text.trim();
                      final v = vergi.text.trim();
                      final t = tc.text.trim();
                      final kMetin = kurulus.text.trim();
                      final kTarih = kMetin.isEmpty ? null : _tarihCoz(kMetin);
                      final rakam = RegExp(r'^\d+$');
                      String? h;
                      if (unvan.text.trim().isEmpty) {
                        h = 'Firma ünvanı boş olamaz';
                      } else if (v.isNotEmpty && (v.length != 10 || !rakam.hasMatch(v))) {
                        h = 'Vergi no 10 haneli rakam olmalı';
                      } else if (t.isNotEmpty && (t.length != 11 || !rakam.hasMatch(t))) {
                        h = 'TC kimlik no 11 haneli rakam olmalı';
                      } else if (eposta.text.trim().isNotEmpty && !epostaGecerli(eposta.text.trim())) {
                        h = 'E-posta adresi geçersiz';
                      } else if (kMetin.isNotEmpty && kTarih == null) {
                        h = 'Kuruluş tarihi geçersiz, örnek: 14.05.2018';
                      } else if (!hesapVar0 && (g.isNotEmpty != s.isNotEmpty)) {
                        h = 'Giriş adı ve şifreyi birlikte doldur veya ikisini de boş bırak';
                      } else if (!hesapVar0 && g.isNotEmpty && girisEposta(g).startsWith('@')) {
                        h = 'Giriş adında en az bir harf veya rakam olmalı';
                      } else if (!hesapVar0 && g.isNotEmpty && girisEposta(g) == 'admin@muhasebeportal.app') {
                        h = 'Bu giriş adı kullanılamaz';
                      } else if (s.isNotEmpty && s.length < 8) {
                        h = 'Şifre en az 8 karakter olmalı';
                      }
                      if (h != null) {
                        setD(() => hata = h);
                        return;
                      }
                      final uyarilar = <String>[];
                      if (v.isNotEmpty && !vknGecerli(v)) uyarilar.add('Vergi no kontrol hanesine uymuyor, yanlış yazılmış olabilir.');
                      if (t.isNotEmpty && !tcGecerli(t)) uyarilar.add('TC kimlik no geçerli görünmüyor, yanlış yazılmış olabilir.');
                      final benimId = kayitliId ?? mevcut?.id ?? -1;
                      for (final x in _depo.liste) {
                        if (x.id == benimId) continue;
                        if (v.isNotEmpty && x.vergiNo == v) uyarilar.add('Bu vergi numarası "${x.unvan}" firmasında da kayıtlı.');
                        if (t.isNotEmpty && x.tcNo == t) uyarilar.add('Bu TC kimlik numarası "${x.unvan}" firmasında da kayıtlı.');
                      }
                      if (uyarilar.isNotEmpty) {
                        final devam = await showDialog<bool>(
                          context: c,
                          builder: (d) => AlertDialog(
                            title: const Text('Kontrol et'),
                            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              for (final u in uyarilar) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $u')),
                            ]),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Düzelteyim')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yine de kaydet')),
                            ],
                          ),
                        );
                        if (devam != true || !c.mounted) return;
                      }
                      setD(() {
                        hata = null;
                        mesgul = true;
                      });
                      try {
                        final f = Firma(0, unvan.text.trim(),
                            vergiDairesi: vDairesi.text.trim(),
                            vergiNo: v,
                            tcNo: t,
                            faaliyetKodu: fKodu.text.trim(),
                            faaliyetAciklama: fAciklama.text.trim(),
                            sgkSicilNo: sgkSicil.text.trim(),
                            ticaretSicilNo: ticSicil.text.trim(),
                            sgkSubesi: sgkSube.text.trim(),
                            mersisNo: mersis.text.trim(),
                            adres: adres.text.trim(),
                            not: notDefteri.text.trim(),
                            telefon: telefon.text.trim(),
                            eposta: eposta.text.trim(),
                            eDefter: eDefter,
                            gekap: gekap,
                            eDefterTercih: eDefterTercih,
                            kurulus: kTarih);
                        if (kayitliId == null) {
                          final r = await _db.from('firmalar').insert(f.toMap()).select().single();
                          kayitliId = r['id'] as int;
                        } else {
                          await _db.from('firmalar').update(f.toMap()).eq('id', kayitliId!);
                        }
                        final id = kayitliId!;
                        if (yeniLevha != null) {
                          final yol = await _levhaDepoya(id, yeniLevha!);
                          await _db
                              .from('firmalar')
                              .update({'vergi_levhasi_yol': yol, 'vergi_levhasi_adi': levhaAdi}).eq('id', id);
                          yeniLevha = null;
                        } else if (!levhaVar && mevcut?.vergiLevhasiYol != null) {
                          await _db.storage.from('belgeler').remove([mevcut!.vergiLevhasiYol!]);
                          await _db
                              .from('firmalar')
                              .update({'vergi_levhasi_yol': null, 'vergi_levhasi_adi': ''}).eq('id', id);
                        }
                        if (!hesapVar0 && g.isNotEmpty) {
                          await _hesapOlustur(id, g, s);
                        } else if (hesapVar0) {
                          if (s.isNotEmpty) {
                            await _db.rpc('musteri_sifre_degistir', params: {'p_firma_id': id, 'p_sifre': s});
                          }
                          if (girisAktif != mevcut!.girisAktif) {
                            await _db.rpc('musteri_erisim', params: {'p_firma_id': id, 'p_aktif': girisAktif});
                          }
                        }
                        await _depo.yukle();
                        if (mounted) setState(() {});
                        if (c.mounted) Navigator.pop(c);
                        if (mevcut == null && mounted) {
                          final yeni = _depo.liste.where((x) => x.id == id).firstOrNull;
                          if (yeni != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) acilisSihirbaziAc(context, yeni);
                            });
                          }
                        }
                      } on String catch (m) {
                        setD(() {
                          hata = m;
                          mesgul = false;
                        });
                      } on PostgrestException catch (ex) {
                        setD(() {
                          hata = ex.message;
                          mesgul = false;
                        });
                      } catch (ex) {
                        setD(() {
                          hata = '$ex';
                          mesgul = false;
                        });
                      }
                    },
              child: Text(mesgul ? 'Kaydediliyor...' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tumu = _yonetici ? _depo.liste : _depo.liste.where((f) => f.id == widget.firmaId).toList();
    final q = _firmaKatla(_sorgu.trim());
    final liste = q.isEmpty
        ? tumu
        : tumu
            .where((f) => [f.unvan, f.vergiNo, f.tcNo, f.vergiDairesi, f.sgkSicilNo, f.ticaretSicilNo]
                .any((a) => _firmaKatla(a).contains(q)))
            .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _yonetici
          ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              FloatingActionButton.extended(
                heroTag: 'luca-aktar',
                onPressed: () async {
                  if (await lucaFirmalariAktar(context)) await _yenile();
                },
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Luca\'dan aktar'),
              ),
              if (yoneticiOturumu) const SizedBox(height: 10),
              if (yoneticiOturumu)
                FloatingActionButton.extended(
                  heroTag: 'toplu-aktar',
                  onPressed: () async {
                    if (await topluAktar(context)) await _yenile();
                  },
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Toplu aktar (tel / ücret)'),
                ),
              if (yoneticiOturumu) const SizedBox(height: 10),
              if (yoneticiOturumu) FloatingActionButton.extended(
                heroTag: 'yedek-al',
                onPressed: () async {
                  try {
                    final n = await yedekAl();
                    _mesaj('Yedek indirildi ($n sayfa).');
                  } catch (e) {
                    _mesaj('Yedek alınamadı: $e');
                  }
                },
                icon: const Icon(Icons.save_alt),
                label: const Text('Yedek al (Excel)'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'firma-ekle',
                onPressed: () => _form(),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Firma ekle'),
              ),
            ])
          : null,
      body: Column(children: [
        if (_yonetici)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _aramaKutusu,
              focusNode: _aramaOdagi,
              onChanged: (v) => setState(() => _sorgu = v),
              decoration: InputDecoration(
                hintText: 'Firma ara (ünvan, vergi no, TC no)  —  Ctrl+F',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                suffixIcon: _sorgu.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _aramaKutusu.clear();
                          setState(() => _sorgu = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        Expanded(
          child: liste.isEmpty
          ? Center(child: Text(tumu.isEmpty ? 'Henüz firma yok. "Firma ekle" ile başla.' : 'Aramaya uyan firma yok.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: liste.length,
              itemBuilder: (c, i) {
                final f = liste[i];
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    onTap: _yonetici ? () => _firmaAc(f) : null,
                    title: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(f.unvan, style: const TextStyle(fontWeight: FontWeight.w600)),
                      _levhaButonu(f),
                      if (_yonetici)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            seciliFirmaId.value = f.id;
                            bolumIstegi.value = 'Personel';
                          },
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Aç'),
                        ),
                    ]),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 14, children: [
                          if (f.vergiDairesi.isNotEmpty) Text('Vergi dairesi: ${f.vergiDairesi}'),
                          if (f.vergiNo.isNotEmpty) Text('Vergi no: ${f.vergiNo}'),
                          if (f.tcNo.isNotEmpty) Text('TC kimlik no: ${f.tcNo}'),
                          if (f.sgkSicilNo.isNotEmpty) Text('SGK sicil no: ${f.sgkSicilNo}'),
                          if (f.ticaretSicilNo.isNotEmpty) Text('Ticaret sicil no: ${f.ticaretSicilNo}'),
                        ]),
                        if (f.faaliyetKodu.isNotEmpty || f.faaliyetAciklama.isNotEmpty)
                          Text('Faaliyet: ${[f.faaliyetKodu, f.faaliyetAciklama].where((e) => e.isNotEmpty).join(' - ')}'),
                        if (f.kurulus != null) Text('Kuruluş tarihi: ${_tarihYaz(f.kurulus!)}'),
                        if (_yonetici)
                          Row(children: [
                            Icon((f.erisimVar && f.girisAktif) ? Icons.lock_open : Icons.lock_outline,
                                size: 16, color: (f.erisimVar && f.girisAktif) ? Colors.green.shade700 : Colors.black87),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(!f.erisimVar
                                  ? 'Mükellef girişi yok'
                                  : (f.girisAktif ? 'Mükellef girişi açık, giriş adı: ${f.girisAdi}' : 'Mükellef girişi kapalı')),
                            ),
                          ]),
                      ]),
                    ),
                    trailing: _yonetici
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: 'Açılış kontrol listesi', icon: const Icon(Icons.checklist), onPressed: () => acilisSihirbaziAc(context, f)),
                            IconButton(tooltip: 'Düzenle', icon: const Icon(Icons.edit_outlined), onPressed: () => _form(mevcut: f)),
                          ])
                        : null,
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
