import 'marka.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ayarlar.dart';
import 'mfa.dart';
import 'beyanname_kontrol.dart';
import 'beyannameler.dart';
import 'bordro.dart';
import 'firmalar.dart';
import 'personel_takip.dart';
import 'ucret_takip.dart';
import 'yedek_sayfasi.dart';
import 'is_akislari.dart';
import 'kullanicilar.dart';
import 'personel_menu.dart';
import 'hizli_arama.dart';
import 'firma_sayfasi.dart';
import 'package:flutter/services.dart';
import 'secili_firma.dart';
import 'duyuru.dart';
import 'vergi_hesap.dart';
import 'dilekceler.dart';
import 'parametreler.dart';
import 'ekip.dart';
import 'mizan_analiz.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const MuhasebeApp());
}

// ---------- Renkler ----------
const kMurekkep = Color(0xFF12403C);
const kZemin = Color(0xFFF2F5F3);
const kVurgu = Color(0xFFC98A1B);

// ---------- Kullanıcı modeli ve kimlik servisi ----------
enum Rol { yonetici, musteri, yardimci }

class Kullanici {
  final String ad, firma;
  final Rol rol;
  final int? firmaId; // firma kullanıcısıysa bağlı olduğu firma, yöneticide boş
  final Set<String> izinler;
  const Kullanici(this.ad, this.firma, this.rol, {this.firmaId, this.izinler = const {}});
}

/// Supabase ile giriş. Kullanıcının rolü ve firması `profiller` tablosundan okunur.
class KimlikServisi {
  SupabaseClient get _db => Supabase.instance.client;

  /// Açık bir oturum varsa kullanıcıyı döndürür. Hesabın yetkisi yoksa null.
  Future<Kullanici?> oturumuYukle() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final p = await _db.from('profiller').select().eq('user_id', user.id).maybeSingle();
    if (p == null || p['aktif'] == false) {
      await _db.auth.signOut();
      return null;
    }
    yoneticiOturumu = p['rol'] == 'yonetici';
    await FirmaDeposu.ornek.yukle();
    if (p['rol'] == 'yonetici') return const Kullanici('Müşavir', 'Tüm firmalar', Rol.yonetici);
    if (p['rol'] == 'yardimci') {
      final ad = ((p['gorunen_ad'] ?? '') as String).isNotEmpty ? p['gorunen_ad'] as String : (p['giris_adi'] ?? 'Yardımcı') as String;
      final liste = ((p['izinler'] ?? const []) as List).map((e) => e.toString()).toSet();
      return Kullanici(ad, 'Yardımcı kullanıcı', Rol.yardimci, izinler: liste);
    }
    final firmaId = p['firma_id'] as int;
    final unvan = FirmaDeposu.ornek.bul(firmaId)?.unvan ?? 'Mükellef';
    return Kullanici(unvan, unvan, Rol.musteri, firmaId: firmaId);
  }

  Future<Kullanici?> girisYap(String eposta, String sifre, {Future<bool> Function()? mfaSor}) async {
    final anahtar = eposta.trim().toLowerCase();
    var kalan = 0;
    try {
      final r = await _db.rpc('giris_kilit_kontrol', params: {'p_anahtar': anahtar});
      kalan = (r as num?)?.toInt() ?? 0;
    } catch (_) {
      kalan = 0; // supabase_bildirim_kilit.sql çalıştırılmadıysa kilit yok sayılır
    }
    if (kalan > 0) throw GirisKilitli(kalan);
    try {
      await _db.auth.signInWithPassword(email: girisEposta(eposta), password: sifre);
    } on AuthException {
      try {
        await _db.rpc('giris_basarisiz', params: {'p_anahtar': anahtar});
      } catch (_) {}
      rethrow;
    }
    try {
      await _db.rpc('giris_basarili', params: {'p_anahtar': anahtar});
    } catch (_) {}
    if (await mfaKodGerekli()) {
      final ok = mfaSor == null ? false : await mfaSor();
      if (!ok) {
        await _db.auth.signOut();
        throw MfaIptal();
      }
    }
    return oturumuYukle();
  }

  Future<void> cikis() => _db.auth.signOut();
}

/// Otomatik çıkıştan sonra giriş ekranında gösterilecek mesaj.
final ValueNotifier<String?> girisMesaji = ValueNotifier<String?>(null);

/// Bu kadar süre hiçbir işlem yapılmazsa oturum kapatılır.
const _bostaSure = Duration(minutes: 30);

class MfaIptal implements Exception {}

class GirisKilitli implements Exception {
  final int saniye;
  GirisKilitli(this.saniye);
}

final GlobalKey<NavigatorState> _anaNavigator = GlobalKey<NavigatorState>();

/// Esc: açık pencere veya alt sayfa varsa kapatır. Kapatılması bilerek engellenmiş
/// pencerelerde (örn. doğrulama kodu, işlem sürerken) çalışmaz.
void _escIleKapat() {
  final n = _anaNavigator.currentState;
  if (n == null || !n.canPop()) return;
  Route<dynamic>? ust;
  n.popUntil((r) {
    ust = r;
    return true;
  });
  final r = ust;
  if (r is ModalRoute && !r.barrierDismissible && r is! MaterialPageRoute) return;
  n.maybePop();
}

class MuhasebeApp extends StatelessWidget {
  const MuhasebeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _anaNavigator,
        builder: (context, child) => CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escIleKapat},
          child: Focus(autofocus: true, child: child ?? const SizedBox()),
        ),
        title: 'Muhasebe Portalı',
        debugShowCheckedModeBanner: false,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: kZemin,
          colorScheme: ColorScheme.fromSeed(seedColor: kMurekkep, primary: kMurekkep, secondary: kVurgu),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const AcilisEkrani(),
      );
}

// ---------- Açılış: açık oturum varsa doğrudan içeri ----------
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key});
  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani> {
  @override
  void initState() {
    super.initState();
    _kontrol();
  }

  Future<void> _kontrol() async {
    Kullanici? k;
    try {
      if (Supabase.instance.client.auth.currentUser != null && await mfaKodGerekli()) {
        if (!mounted) return;
        final ok = await mfaKodSor(context);
        if (!ok) {
          await Supabase.instance.client.auth.signOut();
        }
      }
      k = await KimlikServisi().oturumuYukle();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => k == null ? const GirisEkrani() : AnaSayfa(kullanici: k)));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

// ---------- Giriş ----------
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key});
  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  final _ad = TextEditingController(), _sifre = TextEditingController();
  final _servis = KimlikServisi();
  bool _yukleniyor = false, _gizli = true;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _hata = girisMesaji.value;
    girisMesaji.value = null;
  }

  Future<void> _giris() async {
    setState(() { _yukleniyor = true; _hata = null; });
    Kullanici? k;
    try {
      k = await _servis.girisYap(_ad.text, _sifre.text, mfaSor: () => mfaKodSor(context));
      if (k == null) _hata = 'Giriş tamamlanamadı: hesap kapalı olabilir.';
    } on MfaIptal {
      _hata = 'İki adımlı doğrulama tamamlanmadı.';
    } on GirisKilitli catch (e) {
      final dk = (e.saniye / 60).ceil();
      _hata = 'Çok fazla hatalı deneme yapıldı. Yaklaşık $dk dakika sonra tekrar dene.';
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials' || e.message.toLowerCase().contains('invalid login')) {
        _hata = 'Firma adı veya şifre hatalı.';
      } else {
        _hata = 'Giriş yapılamadı: ${e.message} (${e.code ?? e.statusCode ?? '-'})';
      }
    } catch (e) {
      _hata = 'Bağlantı hatası: $e';
    }
    if (!mounted) return;
    if (k == null) {
      setState(() => _yukleniyor = false);
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => AnaSayfa(kullanici: k!)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Center(child: MarkaLogo(boyut: 56)),
                const SizedBox(height: 12),
                const Text('Muhasebe Portalı',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: kMurekkep)),
                const SizedBox(height: 4),
                Text('${marka.ad} - ${marka.unvan}',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 32),
                TextField(
                  controller: _ad,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Firma adı', prefixIcon: Icon(Icons.business_outlined)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _sifre,
                  obscureText: _gizli,
                  onSubmitted: (_) => _giris(),
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_gizli ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _gizli = !_gizli),
                    ),
                  ),
                ),
                if (_hata != null) ...[
                  const SizedBox(height: 12),
                  Text(_hata!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _yukleniyor ? null : _giris,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _yukleniyor
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Giriş yap'),
                ),
                const SizedBox(height: 16),
                const Text('Şifreni unuttuysan müşavirinle iletişime geç.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black87)),
              ]),
            ),
          ),
        ),
      );
}

// ---------- Ana menü ----------
class Bolum {
  final String ad;
  final IconData ikon;
  final String aciklama;
  const Bolum(this.ad, this.ikon, this.aciklama);
}

const _bolumler = [
  Bolum('Özet', Icons.dashboard_outlined, 'Genel durum'),
  Bolum('Firmalar', Icons.business_outlined, 'Mükellef firmalar ve uygulama erişimi'),
  Bolum('Beyannameler', Icons.description_outlined, 'Beyannameler ve tahakkuk fişleri'),
  Bolum('Kontrol listesi', Icons.fact_check_outlined, 'Beyanname onay ve gönderim kontrolü (sadece yönetici)'),
  Bolum('Personel', Icons.badge_outlined, 'Aylık izin, rapor ve devamsızlık takibi'),
  Bolum('Takvim', Icons.calendar_month_outlined, 'Yıllık takvim: son günler, hatırlatmalar, bitişler (sadece yönetici)'),
  Bolum('Ücret takibi', Icons.request_quote_outlined, 'Müşavirlik ücreti ve tahsilat takibi (sadece yönetici)'),
  Bolum('Duyurular', Icons.campaign_outlined, 'Mükelleflere toplu e-posta duyurusu (sadece yönetici)'),
  Bolum('Yedekler', Icons.backup_outlined, 'Otomatik ve elle yedekler (sadece yönetici)'),
  Bolum('Kullanıcılar', Icons.group_outlined, 'Yardımcı kullanıcılar (sadece yönetici)'),
  Bolum('İş akışları', Icons.checklist_outlined, 'Kuruluş, adres/ortak değişikliği, kapanış kontrol listeleri (sadece yönetici)'),
  Bolum('Vergi hesaplayıcı', Icons.functions, 'KDV, gelir vergisi, damga vergisi, net-brüt maaş, gecikme ve pişmanlık zammı, stopaj, kira, ücretli yıllık beyan'),
  Bolum('Dilekçeler', Icons.edit_note, 'Vergi dairesi, SGK ve personel dilekçe ile formları (sadece yönetici)'),
  Bolum('Mizan analizi', Icons.analytics_outlined, 'Mizan yükle: oranlar, süreler, dönem karşılaştırması ve PDF analiz raporu (sadece yönetici)'),
  Bolum('Büro kimliği', Icons.palette_outlined, 'Logo, antet, renkler ve e-posta imzası (sadece yönetici)'),
  Bolum('Parametreler', Icons.tune, 'Bordro, vergi ve tazminat hesaplarında kullanılan mevzuat değerleri (sadece yönetici)'),
  Bolum('Ekip', Icons.groups_outlined, 'Portföy atama, iş devri, onay talepleri ve ekip panosu'),
];

class AnaSayfa extends StatefulWidget {
  final Kullanici kullanici;
  const AnaSayfa({super.key, required this.kullanici});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

// Üst çubukta firma seçimi gereken bölümler (Luca'daki "seçili müşteri" gibi).
const _firmaBolumleri = {'Personel', 'Beyannameler'};

// Yalnızca yöneticinin gördüğü bölümler.
const _yoneticiBolumleri = {'İş akışları', 'Dilekçeler', 'Parametreler', 'Büro kimliği', 'Mizan analizi', 'Ekip', 'Takvim', 'Kontrol listesi', 'Ücret takibi', 'Duyurular', 'Yedekler', 'Kullanıcılar'};

// Yardımcı kullanıcıya verilebilecek bölümler.
const yardimciBolumleri = ['Özet', 'Firmalar', 'Beyannameler', 'Kontrol listesi', 'Personel', 'Takvim', 'İş akışları', 'Vergi hesaplayıcı', 'Dilekçeler', 'Ekip'];

List<Bolum> bolumleriSec(Kullanici k) {
  // Yöneticide Ekip, Kullanıcılar bölümünün içinde; ayrı menü satırı yalnızca yardımcıya görünür.
  if (k.rol == Rol.yonetici) return _bolumler.where((b) => b.ad != 'Ekip').toList();
  if (k.rol == Rol.yardimci) {
    return _bolumler.where((b) => yardimciBolumleri.contains(b.ad) && k.izinler.contains(b.ad)).toList();
  }
  return _bolumler.where((b) => !_yoneticiBolumleri.contains(b.ad)).toList();
}

class _AnaSayfaState extends State<AnaSayfa> {
  int _secili = 0;

  bool get _yonetici => widget.kullanici.rol != Rol.musteri;

  Timer? _bosta;

  @override
  void initState() {
    super.initState();
    bolumIstegi.addListener(_bolumIstendi);
    HardwareKeyboard.instance.addHandler(_tusAlgila);
    _sayaciSifirla();
    if (_yonetici) WidgetsBinding.instance.addPostFrameCallback((_) => _mfaOner());
    if (_yonetici) _firmalariYukle();
    markaYukle().then((_) {
      if (mounted) setState(() {});
    });
    parametreYukle().then((_) {
      if (!mounted || !_yonetici) return;
      final u = parametreUyarilari();
      if (u.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('Parametre kontrolü gerekiyor: ${u.first}${u.length > 1 ? ' (+${u.length - 1} uyarı daha)' : ''}'),
        ));
      }
    });
  }

  @override
  void dispose() {
    _bosta?.cancel();
    HardwareKeyboard.instance.removeHandler(_tusAlgila);
    bolumIstegi.removeListener(_bolumIstendi);
    super.dispose();
  }

  bool _tusAlgila(KeyEvent e) {
    _sayaciSifirla();
    return false;
  }

  void _sayaciSifirla() {
    _bosta?.cancel();
    _bosta = Timer(_bostaSure, _bostaCikis);
  }

  Future<void> _bostaCikis() async {
    if (!mounted) return;
    girisMesaji.value = 'Uzun süre işlem yapılmadığı için güvenlik amacıyla çıkış yapıldı.';
    try {
      await KimlikServisi().cikis();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const GirisEkrani()), (_) => false);
  }

  Future<void> _mfaOner() async {
    if (await mfaFaktor() != null || !mounted) return;
    final kur = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('İki adımlı doğrulamayı kur'),
        content: const Text('Hesabını korumak için girişte Google Authenticator kodu istensin. Kurulum yaklaşık bir dakika sürer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Daha sonra')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Şimdi kur')),
        ],
      ),
    );
    if (kur == true && mounted) await mfaKurulumAc(context);
  }

  Future<void> _digerCihazlardanCik() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Diğer cihazlardan çıkış yapılsın mı?'),
        content: const Text('Bu hesapla başka bilgisayar veya telefonlarda açık olan oturumlar kapatılır. Bu cihazdaki oturum devam eder.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çıkış yaptır')),
        ],
      ),
    );
    if (onay != true) return;
    final mesaj = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.others);
      mesaj.showSnackBar(const SnackBar(content: Text('Diğer cihazlardaki oturumlar kapatıldı.')));
    } catch (e) {
      mesaj.showSnackBar(SnackBar(content: Text('İşlem yapılamadı: $e')));
    }
  }

  Future<void> _firmalariYukle() async {
    try {
      await FirmaDeposu.ornek.yukle();
    } catch (_) {}
    final liste = FirmaDeposu.ornek.liste;
    if (liste.isNotEmpty && !liste.any((f) => f.id == seciliFirmaId.value)) {
      seciliFirmaId.value = liste.first.id;
    }
    if (mounted) setState(() {});
  }

  void _bolumIstendi() {
    final ad = bolumIstegi.value;
    if (ad == null) return;
    bolumIstegi.value = null;
    final i = bolumleriSec(widget.kullanici).indexWhere((b) => b.ad == ad);
    if (i >= 0 && mounted) setState(() => _secili = i);
  }

  Future<void> _hizliAra() async {
    if (widget.kullanici.rol == Rol.musteri) return;
    final bolumler = bolumleriSec(widget.kullanici);
    final s = await hizliAramaAc(context, [for (final b in bolumler) (ad: b.ad, ikon: b.ikon)]);
    if (s == null || !mounted) return;
    if (s.bolumIndex != null) {
      setState(() => _secili = s.bolumIndex!);
    } else if (s.firmaId != null) {
      seciliFirmaId.value = s.firmaId;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FirmaSayfasi(
          firmaId: s.firmaId!,
          duzenle: () async {
            Navigator.of(context).pop();
            bolumIstegi.value = 'Firmalar';
          },
        ),
      ));
    }
  }

  Widget _kisayol(Widget w) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _hizliAra,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): _hizliAra,
        },
        child: Focus(autofocus: true, child: w),
      );

  Future<void> _cikis() async {
    await KimlikServisi().cikis();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const GirisEkrani()));
  }

  Future<void> _sifreDegistir() async {
    final kontrol = TextEditingController();
    String? hata;
    final yeni = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Şifremi değiştir'),
          content: TextField(
            controller: kontrol,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Yeni şifre (en az 8 karakter)', errorText: hata),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (kontrol.text.length < 8) {
                  setD(() => hata = 'En az 8 karakter olmalı');
                } else {
                  Navigator.pop(c, kontrol.text);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (yeni == null) return;
    final mesaj = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: yeni));
      mesaj.showSnackBar(const SnackBar(content: Text('Şifren değiştirildi.')));
    } catch (e) {
      mesaj.showSnackBar(SnackBar(content: Text('Şifre değiştirilemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _sayaciSifirla(),
        onPointerMove: (_) => _sayaciSifirla(),
        onPointerSignal: (_) => _sayaciSifirla(),
        child: _anaGovde(context),
      );

  Widget _anaGovde(BuildContext context) {
    final genis = MediaQuery.of(context).size.width >= 800;
    final bolumler = bolumleriSec(widget.kullanici);
    if (bolumler.isEmpty) {
      return Scaffold(
        appBar: AppBar(backgroundColor: kMurekkep, foregroundColor: Colors.white, title: const Text('Muhasebe Portalı'), actions: [
          IconButton(tooltip: 'Çıkış yap', icon: const Icon(Icons.logout), onPressed: _cikis),
        ]),
        body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Bu hesaba henüz bir bölüm yetkisi verilmemiş. Müşavirinle iletişime geç.', textAlign: TextAlign.center))),
      );
    }
    final icerik = _BolumIcerigi(bolum: bolumler[_secili], kullanici: widget.kullanici);

    final appBar = AppBar(
      backgroundColor: kMurekkep,
      foregroundColor: Colors.white,
      title: Row(children: [const MarkaLogo(boyut: 28), const SizedBox(width: 10), Text(bolumler[_secili].ad)]),
      bottom: (_yonetici && _firmaBolumleri.contains(bolumler[_secili].ad))
          ? const PreferredSize(preferredSize: Size.fromHeight(64), child: _FirmaCubugu())
          : null,
      actions: [
        if (_yonetici) IconButton(tooltip: 'Ara (Cmd+K)', icon: const Icon(Icons.search), onPressed: _hizliAra),
        Center(child: Text(widget.kullanici.ad, style: const TextStyle(fontSize: 13))),
        IconButton(tooltip: 'Şifremi değiştir', icon: const Icon(Icons.key_outlined), onPressed: _sifreDegistir),
        if (_yonetici) IconButton(tooltip: 'İki adımlı doğrulama (Google Authenticator)', icon: const Icon(Icons.security), onPressed: () => mfaYonet(context)),
        IconButton(tooltip: 'Diğer cihazlardan çıkış yap', icon: const Icon(Icons.devices_other_outlined), onPressed: _digerCihazlardanCik),
        IconButton(tooltip: 'Çıkış yap', icon: const Icon(Icons.logout), onPressed: _cikis),
      ],
    );

    if (genis) {
      return _kisayol(Scaffold(
        appBar: appBar,
        body: Row(children: [
          LayoutBuilder(
            builder: (context, k) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: k.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    extended: true,
                    selectedIndex: _secili,
                    onDestinationSelected: (i) => setState(() => _secili = i),
                    destinations: [for (final b in bolumler) NavigationRailDestination(icon: Icon(b.ikon), label: Text(b.ad))],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: icerik),
        ]),
      ));
    }
    return _kisayol(Scaffold(
      appBar: appBar,
      body: icerik,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _secili,
        onDestinationSelected: (i) => setState(() => _secili = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final b in bolumler)
            NavigationDestination(icon: Icon(b.ikon), label: b.ad.split(' ').first),
        ],
      ),
));
  }
}

/// Luca'daki gibi üst çubukta seçili firma: yazarak ara, seçince bölümler o firmaya geçer.
class _FirmaCubugu extends StatelessWidget {
  const _FirmaCubugu();

  @override
  Widget build(BuildContext context) {
    final firmalar = FirmaDeposu.ornek.liste;
    return ValueListenableBuilder<int?>(
      valueListenable: seciliFirmaId,
      builder: (c, secili, _) => Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: LayoutBuilder(
          builder: (c, k) => DropdownMenu<int>(
            key: ValueKey('firma-$secili-${firmalar.length}'),
            width: k.maxWidth.isFinite ? k.maxWidth : 360,
            initialSelection: firmalar.any((f) => f.id == secili) ? secili : null,
            enableFilter: true,
            requestFocusOnTap: true,
            leadingIcon: const Icon(Icons.business_outlined),
            hintText: 'Firma seç (yazarak ara)',
            inputDecorationTheme: const InputDecorationTheme(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
            dropdownMenuEntries: [for (final f in firmalar) DropdownMenuEntry(value: f.id, label: f.unvan)],
            onSelected: (v) {
              if (v != null) seciliFirmaId.value = v;
            },
          ),
        ),
      ),
    );
  }
}

class _BolumIcerigi extends StatelessWidget {
  final Bolum bolum;
  final Kullanici kullanici;
  const _BolumIcerigi({required this.bolum, required this.kullanici});

  @override
  Widget build(BuildContext context) {
    if (bolum.ad == 'Özet') return OzetSayfasi(firmaId: kullanici.firmaId);
    if (bolum.ad == 'Personel') {
      return kullanici.rol == Rol.musteri ? PersonelTakipSayfasi(firmaId: kullanici.firmaId) : const PersonelMenuSayfasi();
    }
    if (bolum.ad == 'Firmalar') return FirmalarSayfasi(firmaId: kullanici.firmaId);
    if (bolum.ad == 'Beyannameler') return BeyannamelerSayfasi(firmaId: kullanici.firmaId);
    if (bolum.ad == 'Kontrol listesi' && kullanici.rol != Rol.musteri) return const BeyannameKontrolSayfasi();
    if (bolum.ad == 'Takvim' && kullanici.rol != Rol.musteri) return const TakvimSayfasi();
    if (bolum.ad == 'İş akışları' && kullanici.rol != Rol.musteri) return const IsAkislariSayfasi();
    if (bolum.ad == 'Vergi hesaplayıcı') return const VergiHesapSayfasi();
    if (bolum.ad == 'Dilekçeler' && kullanici.rol != Rol.musteri) return const DilekcelerSayfasi();
    if (bolum.ad == 'Parametreler' && kullanici.rol == Rol.yonetici) return const ParametrelerSayfasi();
    if (bolum.ad == 'Büro kimliği' && kullanici.rol == Rol.yonetici) return const MarkaSayfasi();
    if (bolum.ad == 'Mizan analizi' && kullanici.rol == Rol.yonetici) return const MizanAnaliziSayfasi();
    if (bolum.ad == 'Ekip' && kullanici.rol != Rol.musteri) return EkipSayfasi(yonetici: kullanici.rol == Rol.yonetici);
    if (bolum.ad == 'Ücret takibi' && kullanici.rol == Rol.yonetici) return const UcretTakipSayfasi();
    if (bolum.ad == 'Duyurular' && kullanici.rol == Rol.yonetici) return const DuyuruSayfasi();
    if (bolum.ad == 'Yedekler' && kullanici.rol == Rol.yonetici) return const YedekSayfasi();
    if (bolum.ad == 'Kullanıcılar' && kullanici.rol == Rol.yonetici) return const KullanicilarSayfasi();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ValueListenableBuilder<int?>(
          valueListenable: seciliFirmaId,
          builder: (c, id, _) => Text(
            kullanici.rol != Rol.musteri ? (FirmaDeposu.ornek.bul(id ?? -1)?.unvan ?? kullanici.firma) : kullanici.firma,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 4),
        Text(bolum.aciklama, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: kMurekkep)),
        const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(bolum.ikon, size: 56, color: kVurgu),
              const SizedBox(height: 12),
              const Text('Bu bölüm sıradaki adımda hazırlanacak.'),
            ]),
          ),
        ),
      ]),
    );
  }
}
