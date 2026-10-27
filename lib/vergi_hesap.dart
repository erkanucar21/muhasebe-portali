import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bordro_cikti.dart' show tl, bordroKaydet, bordroAylar;
import 'bordro_hesap.dart';
import 'firmalar.dart';
import 'hatirlatma.dart';
import 'hesap_cikti.dart';
import 'kar_belgeleri.dart';
import 'secili_firma.dart';
import 'maas_alani.dart';
import 'mizan_hesap.dart' show mizanOku, mizanOzetle, mizanTl;
import 'zam_hesap.dart';

typedef _Satir = (String, String);

class _Kalem {
  final ad = TextEditingController();
  final tutar = TextEditingController();
  _Kalem([String a = '']) {
    ad.text = a;
  }
}

class _Ortak {
  final ad = TextEditingController();
  final tc = TextEditingController(); // TC kimlik no / vergi no
  final pay = TextEditingController();
  bool stopajli = true; // gerçek kişi veya yabancı: kâr payı stopajı kesilir
}

/// KDV, gelir vergisi, damga vergisi ve net-brüt maaş hesaplayıcıları. Sadece yönetici.
class VergiHesapSayfasi extends StatefulWidget {
  const VergiHesapSayfasi({super.key});
  @override
  State<VergiHesapSayfasi> createState() => _VergiHesapSayfasiState();
}

class _VergiHesapSayfasiState extends State<VergiHesapSayfasi> {
  int _sekme = 0;

  // KDV
  final _kdvTutar = TextEditingController();
  final _kdvOzel = TextEditingController();
  double _kdvOran = 20;
  bool _kdvDahil = false;
  int _tevkifat = 0; // pay, 10 üzerinden

  // İki bilinmeyenli KDV
  final _ikiToplam = TextEditingController();
  final _ikiKdv = TextEditingController();
  final _ikiOran1 = TextEditingController(text: '10');
  final _ikiOran2 = TextEditingController(text: '20');
  bool _ikiOranBul = false;
  bool _ikiToplamlaBul = false;

  // Gelir vergisi
  final _gvMatrah = TextEditingController();
  late int _gvYil;
  bool _gvUcret = true; // true: ücret tarifesi, false: ücret dışı (dilimleri kendin gir)
  final List<TextEditingController> _gvUst = [for (var i = 0; i < 4; i++) TextEditingController()];
  final List<TextEditingController> _gvOranC = [for (var i = 0; i < 5; i++) TextEditingController()];

  // Ücretli yıllık beyan
  late int _ybYil;
  bool _ybDisTarife = false;
  final List<(TextEditingController, TextEditingController)> _ybIsv = [
    (TextEditingController(), TextEditingController()),
    (TextEditingController(), TextEditingController()),
  ];
  final _ybDiger = TextEditingController();
  final _ybIndirim = TextEditingController(); // diğer indirimler
  final _ybSigorta = TextEditingController();
  final _ybBagis = TextEditingController();
  final _ybEgitim = TextEditingController();
  final _ybSigLimit = TextEditingController();
  final _ybBagisPct = TextEditingController();
  final _ybKira = TextEditingController();
  final _ybKiraGider = TextEditingController();
  final _ybKiraIst = TextEditingController();
  bool _ybKiraGotur = true;
  final _ybIstisna = TextEditingController();
  final _ybStopaj = TextEditingController();

  // Kâr dağıtımı
  final _krKar = TextEditingController();
  final _krZarar = TextEditingController();
  final _krSermaye = TextEditingController();
  final _krYedek = TextEditingController();
  final _krEk = TextEditingController();
  final _krBirinciPct = TextEditingController(text: '5');
  final _krDagitPct = TextEditingController(text: '100');
  final _krStopaj = TextEditingController(text: '10');
  final _krGk = TextEditingController(); // genel kurul karar tarihi (metin)
  DateTime _krTarih = DateTime.now();
  bool _krYedek1 = true;
  bool _krYedek2 = true;
  final List<_Ortak> _krOrtaklar = [_Ortak()];

  final _krUnvan = TextEditingController();
  final _krDonem = TextEditingController(text: '${DateTime.now().year - 1}');

  // Ortak cari hesap faizi
  final _ofTutar = TextEditingController();
  final _ofOran = TextEditingController();
  final _ofEmsal = TextEditingController();
  DateTime _ofBas = DateTime(DateTime.now().year, 1, 1);
  DateTime _ofBit = DateTime.now();
  bool _ofSirketAlacakli = true;

  // Finansman gider kısıtlaması
  final _fgYk = TextEditingController();
  final _fgOk = TextEditingController();
  final _fgGider = TextEditingController();
  final _fgHaric = TextEditingController();
  final _fgOran = TextEditingController(text: '10');
  final _fgKv = TextEditingController();
  bool _fgOkNeg = false;
  bool _fgMuaf = false;

  // Kuruluş maliyeti
  final List<_Kalem> _kmKalemler = [
    _Kalem('Ticaret sicil tescil harcı'),
    _Kalem('Noter onay ve imza sirküleri'),
    _Kalem('Oda kayıt ücreti'),
    _Kalem('Ticaret sicil gazetesi ilanı'),
    _Kalem('Diğer resmî giderler'),
  ];
  final _kmHizmet = TextEditingController();
  final _kmKdv = TextEditingController(text: '20');

  // Personel ödemeleri: fazla mesai, raporlu gün ödeneği, yıllık izin ücreti
  int _ppMod = 0;
  bool _ppNet = true;
  final _ppMaas = TextEditingController();
  late int _ppYil;
  int _ppAy = DateTime.now().month;
  final _fmSaat = TextEditingController();
  final _fmBolen = TextEditingController(text: '225');
  final _fmZam = TextEditingController(text: '50');
  final _fmHt = TextEditingController();
  final _fmHtK = TextEditingController(text: '1,5');
  final _fmGt = TextEditingController();
  final _fmGtK = TextEditingController(text: '1');
  final _rpGun = TextEditingController();
  final _rpOran = TextEditingController(text: '66,67');
  final _rpBekleme = TextEditingController(text: '0');
  String _rpTur = 'İş kazası / meslek hastalığı';
  final _izGun = TextEditingController();

  static const _rpTurleri = <String, (String, String)>{
    'Hastalık (ayakta)': ('40', '2'),
    'Hastalık (yatarak)': ('50', '2'),
    'İş kazası / meslek hastalığı': ('66,67', '0'),
    'Analık (doğum izni)': ('66,67', '0'),
  };

  // Zam simülasyonu
  final _zmMaas = TextEditingController();
  final _zmDeger = TextEditingController();
  late int _zmYil;
  bool _zmNet = true;
  bool _zmYuzde = true;

  // Damga vergisi
  final _damgaTutar = TextEditingController();
  final _damgaOran = TextEditingController(text: '9,48');
  String _damgaTur = 'Sözleşme';

  // Stopaj
  final _stTutar = TextEditingController();
  final _stOran = TextEditingController(text: '20');
  bool _stNetten = false;

  // Serbest meslek makbuzu
  final _smTutar = TextEditingController();
  final _smKdv = TextEditingController(text: '20');
  final _smStopaj = TextEditingController(text: '20');
  bool _smNet = false;

  // Kira vergisi
  final _kiGelir = TextEditingController();
  final _kiGider = TextEditingController();
  final _kiIstisna = TextEditingController();
  final _kiMahsup = TextEditingController();
  late int _kiYil;
  bool _kiGotur = true;
  bool _kiKonut = true;

  // Emlak vergisi ve yeniden değerleme artışı
  final _emDeger = TextEditingController();
  final _emOran = TextEditingController(text: '1');
  final _emEski = TextEditingController();
  final _emArtis = TextEditingController();
  String _emTur = 'Konut binası';
  bool _emBuyuk = false;
  int _emMod = 0;

  // Değer artış kazancı
  final _daAlis = TextEditingController();
  final _daSatis = TextEditingController();
  final _daMasraf = TextEditingController();
  final _daEndA = TextEditingController();
  final _daEndS = TextEditingController();
  final _daEsik = TextEditingController(text: '10');
  final _daSure = TextEditingController(text: '5');
  final _daIstisna = TextEditingController();
  final _daDiger = TextEditingController();
  late int _daYil;
  DateTime _daAlisT = DateTime(DateTime.now().year - 3, 1, 1);
  DateTime _daSatisT = DateTime.now();

  // Tapu harcı ve alım-satım maliyeti
  final _tpBedel = TextEditingController();
  final _tpDeger = TextEditingController();
  final _tpHarcA = TextEditingController();
  final _tpHarcS = TextEditingController();
  final _tpDamga = TextEditingController();
  final _tpKomA = TextEditingController();
  final _tpKomS = TextEditingController();
  final _tpKdv = TextEditingController(text: '20');
  final _tpDigA = TextEditingController();
  final _tpDigS = TextEditingController();
  int _tpDamgaTaraf = 2; // 0 alıcı, 1 satıcı, 2 yarı yarıya

  // Vergi ceza hesaplayıcı
  final _vcVergi = TextEditingController();
  final _vcOran = TextEditingController(text: '4,5');
  final _vcKat = TextEditingController(text: '1');
  final _vcUsul = TextEditingController();
  final _vcOzel = TextEditingController();
  final _vcIndirim = TextEditingController();
  DateTime _vcVade = DateTime.now().subtract(const Duration(days: 180));
  DateTime _vcOdeme = DateTime.now();

  // Şirket türü karşılaştırma
  final _scKar = TextEditingController();
  final _scKv = TextEditingController();
  final _scStopaj = TextEditingController();
  final _scDagit = TextEditingController(text: '100');
  final _scPrimSahis = TextEditingController();
  final _scPrimLtd = TextEditingController();
  final _scPrimAs = TextEditingController();
  final _scEkSahis = TextEditingController();
  final _scEkLtd = TextEditingController();
  final _scEkAs = TextEditingController();
  late int _scYil;
  bool _scPrimIndir = true;

  List<TextEditingController> get _yeniAlanlar =>
      [..._gvUst, ..._gvOranC, for (final (a, b) in _ybIsv) ...[a, b], _ybDiger, _ybIndirim, _ybSigorta, _ybBagis, _ybEgitim, _ybSigLimit, _ybBagisPct, _ybKira, _ybKiraGider, _ybKiraIst, _ybIstisna, _ybStopaj, _krKar, _krZarar, _krSermaye, _krYedek, _krEk, _krBirinciPct, _krDagitPct, _krStopaj, _krUnvan, _krDonem, _ppMaas, _fmSaat, _fmBolen, _fmZam, _fmHt, _fmHtK, _fmGt, _fmGtK, _rpGun, _rpOran, _rpBekleme, _izGun, _ofTutar, _ofOran, _ofEmsal, _kmHizmet, _kmKdv, for (final k in _kmKalemler) ...[k.ad, k.tutar], for (final o in _krOrtaklar) ...[o.ad, o.tc, o.pay], _krGk, _zmMaas, _zmDeger, _stTutar, _stOran, _smTutar, _smKdv, _smStopaj, _kiGelir, _kiGider, _kiIstisna, _kiMahsup, _emDeger, _emOran, _emEski, _emArtis, _daAlis, _daSatis, _daMasraf, _daEndA, _daEndS, _daEsik, _daSure, _daIstisna, _daDiger, _tpBedel, _tpDeger, _tpHarcA, _tpHarcS, _tpDamga, _tpKomA, _tpKomS, _tpKdv, _tpDigA, _tpDigS, _vcVergi, _vcOran, _vcKat, _vcUsul, _vcOzel, _vcIndirim, _scKar, _scKv, _scStopaj, _scDagit, _scPrimSahis, _scPrimLtd, _scPrimAs, _scEkSahis, _scEkLtd, _scEkAs];

  static const _emTurleri = <String, String>{'Konut binası': '1', 'Diğer bina': '2', 'Arsa': '3', 'Arazi': '1'};

  // Net - brüt
  final _maas = TextEditingController();
  late int _maasYil;
  bool _maasNet = true;

  static const _damgaTurleri = <String, String>{
    'Sözleşme': '9,48',
    'Ücret ödemeleri': '7,59',
    'Kira sözleşmesi': '1,89',
    'İhale kararı': '5,69',
    'Özel': '',
  };

  @override
  void initState() {
    super.initState();
    final yillar = bordroYillari();
    _gvYil = yillar.contains(DateTime.now().year) ? DateTime.now().year : yillar.last;
    _maasYil = _gvYil;
    _kiYil = _gvYil;
    _daYil = _gvYil;
    _scYil = _gvYil;
    _zmYil = _gvYil;
    _ybYil = _gvYil;
    _ppYil = _gvYil;
    _krUnvan.text = FirmaDeposu.ornek.bul(seciliFirmaId.value ?? -1)?.unvan ?? '';
    for (final o in _krOrtaklar) {
      o.pay.addListener(() => setState(() {}));
    }
    for (final (a, b) in _ybIsv) {
      a.addListener(() => setState(() {}));
      b.addListener(() => setState(() {}));
    }
    _gvOzelDoldur();
    for (final c in [_kdvTutar, _kdvOzel, _ikiToplam, _ikiKdv, _ikiOran1, _ikiOran2, _gvMatrah, _damgaTutar, _damgaOran, _maas, ..._yeniAlanlar]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_kdvTutar, _kdvOzel, _ikiToplam, _ikiKdv, _ikiOran1, _ikiOran2, _gvMatrah, _damgaTutar, _damgaOran, _maas, ..._yeniAlanlar]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Ücret dışı tarife alanlarını seçili yılın ücret tarifesiyle doldurur; sınırları sen değiştirirsin.
  void _gvOzelDoldur() {
    final p = bordroParam(_gvYil);
    if (p == null) return;
    for (var i = 0; i < 5; i++) {
      final (ust, oran) = p.dilimler[i];
      if (i < 4) _gvUst[i].text = ust.round().toString();
      _gvOranC[i].text = _yz(oran * 100);
    }
  }

  double? _sayi(String s) => double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

  void _bilgi(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _kopyala(List<_Satir> s) async {
    await Clipboard.setData(ClipboardData(text: [for (final x in s) x.$2.isEmpty ? x.$1 : '${x.$1.startsWith('>') ? x.$1.substring(1) : x.$1}: ${x.$2}'].join('\n')));
    _bilgi('Kopyalandı.');
  }

  Future<void> _pdf(String ad, String baslik, List<_Satir> s) async {
    try {
      await hesapPdfKaydet(ad, baslik, s);
      _bilgi('PDF indirildi.');
    } catch (e) {
      _bilgi('PDF hazırlanamadı: $e');
    }
  }

  Future<void> _excel(String ad, Uint8List Function() yap) async {
    try {
      await bordroKaydet(ad, yap(), 'xlsx');
      _bilgi('Excel indirildi. Sarı hücreleri değiştirirsen sonuçlar güncellenir.');
    } catch (e) {
      _bilgi('Excel hazırlanamadı: $e');
    }
  }

  Future<void> _vadeEkle(String baslik, DateTime t) async {
    try {
      await vadeIcsKaydet(baslik, t);
      _bilgi('Takvim dosyası indirildi. Mac\'te çift tıklayıp takvime ekle. Bildirim bir gün önce ve o gün 09:00\'da çalar.');
    } catch (e) {
      _bilgi('Dosya hazırlanamadı: $e');
    }
  }

  Future<void> _hatirlatmaDialog(String onerilen) async {
    final baslik = TextEditingController(text: onerilen);
    var tarih = DateTime.now().add(const Duration(days: 1));
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Hatırlatma ekle'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: baslik, decoration: const InputDecoration(labelText: 'Hatırlatma metni')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(context: c, initialDate: tarih, firstDate: DateTime(2000), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                if (d != null) setD(() => tarih = d);
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text('Tarih: ${_tr(tarih)}'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                _vadeEkle(baslik.text.trim().isEmpty ? onerilen : baslik.text.trim(), tarih);
              },
              child: const Text('Takvim dosyası indir'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sonuc(List<_Satir> s, String ad, String baslik, {Uint8List Function()? xlsx, List<(String, DateTime)> vadeler = const []}) => Card(
        elevation: 0,
        color: const Color(0xFFE8F5E9),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final x in s)
              x.$2.isEmpty
                  ? Padding(padding: const EdgeInsets.only(top: 8, bottom: 2), child: Text(x.$1, style: const TextStyle(fontWeight: FontWeight.w700)))
                  : (x.$1.startsWith('>')
                      ? Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(color: const Color(0xFFC8E6C9), borderRadius: BorderRadius.circular(6)),
                          child: Row(children: [
                            Expanded(child: Text(x.$1.substring(1), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1B5E20)))),
                            Text(x.$2, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1B5E20))),
                          ]),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [Expanded(child: Text(x.$1)), Text(x.$2, style: const TextStyle(fontWeight: FontWeight.w600))]),
                        )),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: () => _kopyala(s), icon: const Icon(Icons.copy, size: 18), label: const Text('Kopyala')),
              OutlinedButton.icon(onPressed: () => _pdf(ad, baslik, s), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('PDF indir')),
              if (xlsx != null)
                OutlinedButton.icon(onPressed: () => _excel(ad, xlsx), icon: const Icon(Icons.table_chart_outlined, size: 18), label: const Text('Excel indir (formüllü)')),
              for (final (e, t) in vadeler)
                OutlinedButton.icon(
                  onPressed: () => _vadeEkle(e, t),
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: Text('Takvime ekle: $e (${_tr(t)})'),
                ),
              OutlinedButton.icon(onPressed: () => _hatirlatmaDialog(baslik), icon: const Icon(Icons.alarm_add_outlined, size: 18), label: const Text('Hatırlatma ekle')),
            ]),
          ]),
        ),
      );

  // ---------------------------------------------------------------- KDV
  Widget _kdv() {
    final tutar = _sayi(_kdvTutar.text);
    final oran = _kdvOzel.text.trim().isNotEmpty ? _sayi(_kdvOzel.text) : _kdvOran;
    Widget sonuc = const Text('Tutarı gir.');
    if (tutar != null && tutar > 0 && oran != null && oran >= 0) {
      final r = 1 + oran / 100;
      final matrah = kurus(_kdvDahil ? tutar / r : tutar);
      final kdv = kurus(_kdvDahil ? tutar - matrah : tutar * oran / 100);
      final toplam = kurus(matrah + kdv);
      final tev = kurus(kdv * _tevkifat / 10);
      final satirlar = <_Satir>[
        ('KDV hesabı (%${oran.toString().replaceAll('.', ',')})', ''),
        ('KDV hariç tutar (matrah)', tl(matrah)),
        ('KDV', tl(kdv)),
        ('KDV dahil toplam', tl(toplam)),
        if (_tevkifat > 0) ...[
          ('Tevkifat ($_tevkifat/10)', ''),
          ('Alıcının sorumlu olduğu KDV', tl(tev)),
          ('Satıcının beyan edeceği KDV', tl(kurus(kdv - tev))),
          ('Satıcıya ödenecek (matrah + kalan KDV)', tl(kurus(matrah + kdv - tev))),
        ],
      ];
      sonuc = _sonuc(satirlar, 'kdv_hesabi', 'KDV hesabı',
          xlsx: () => kdvXlsx(dahil: _kdvDahil, tutar: tutar, oran: oran, tevkifat: _tevkifat));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: false, label: Text('Tutar KDV hariç')), ButtonSegment(value: true, label: Text('Tutar KDV dahil'))],
        selected: {_kdvDahil},
        onSelectionChanged: (v) => setState(() => _kdvDahil = v.first),
      ),
      const SizedBox(height: 12),
      MaasAlani(controller: _kdvTutar, etiket: 'Tutar (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        for (final o in [1.0, 10.0, 20.0])
          ChoiceChip(
            label: Text('%${o.toInt()}'),
            selected: _kdvOzel.text.trim().isEmpty && _kdvOran == o,
            onSelected: (_) => setState(() {
              _kdvOran = o;
              _kdvOzel.clear();
            }),
          ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: 220,
        child: TextField(controller: _kdvOzel, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Diğer oran (%)', isDense: true)),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: 260,
        child: DropdownButtonFormField<int>(
          initialValue: _tevkifat,
          decoration: const InputDecoration(labelText: 'KDV tevkifatı', isDense: true),
          items: [
            const DropdownMenuItem(value: 0, child: Text('Yok')),
            for (final p in [2, 3, 4, 5, 7, 9, 10]) DropdownMenuItem(value: p, child: Text('$p/10')),
          ],
          onChanged: (v) => setState(() => _tevkifat = v ?? 0),
        ),
      ),
      const SizedBox(height: 14),
      sonuc,
      const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Genel oran %20, indirimli oranlar %10 ve %1\'dir. Hangi işleme hangi tevkifat oranının uygulanacağını KDV Genel Uygulama Tebliği\'nden kontrol et.',
            style: TextStyle(fontSize: 12, color: Colors.black87)),
      ),
    ]);
  }

  // ---------------------------------------------------------------- İki bilinmeyenli KDV
  Widget _ikiBilinmeyenli() {
    final t = _sayi(_ikiToplam.text);
    final k = _sayi(_ikiKdv.text);
    Widget sonuc = const Text('Tutarları gir.');
    if (!_ikiOranBul) {
      final r1 = _sayi(_ikiOran1.text);
      final r2 = _sayi(_ikiOran2.text);
      if (t != null && t > 0 && k != null && k >= 0 && r1 != null && r2 != null) {
        if (r1 == r2) {
          sonuc = const Text('İki oran farklı olmalı.', style: TextStyle(color: Color(0xFFC62828)));
        } else {
          final a = r1 / 100, b = r2 / 100;
          final m = t - k; // toplam matrah
          final y = (k - m * a) / (b - a); // 2. orandaki matrah
          final x = m - y; // 1. orandaki matrah
          if (x < -0.005 || y < -0.005 || m <= 0) {
            sonuc = const Text('Girilen toplam ve KDV bu iki oranla tutmuyor. Tutarları ve oranları kontrol et.', style: TextStyle(color: Color(0xFFC62828)));
          } else {
            final x1 = kurus(x < 0 ? 0 : x), y1 = kurus(y < 0 ? 0 : y);
            final xk = kurus(x1 * a), yk = kurus(y1 * b);
            String o(double r) => r.toString().replaceAll('.', ',').replaceAll(RegExp(r',0$'), '');
            sonuc = _sonuc([
              ('Karışık oranlı fiş / fatura', ''),
              ('%${o(r1)} oranlı matrah', tl(x1)),
              ('%${o(r1)} KDV', tl(xk)),
              ('>%${o(r1)} oranlı genel toplam (matrah + KDV)', tl(kurus(x1 + xk))),
              ('%${o(r2)} oranlı matrah', tl(y1)),
              ('%${o(r2)} KDV', tl(yk)),
              ('>%${o(r2)} oranlı genel toplam (matrah + KDV)', tl(kurus(y1 + yk))),
              ('Toplam matrah', tl(kurus(x1 + y1))),
              ('Toplam KDV', tl(kurus(xk + yk))),
              ('>Genel toplam', tl(kurus(x1 + y1 + xk + yk))),
            ], 'iki_oranli_kdv', 'İki oranlı KDV dağılımı', xlsx: () => ikiOranliKdvXlsx(toplam: t, kdv: k, oran1: r1, oran2: r2));
          }
        }
      }
    } else {
      if (t != null && t > 0 && k != null && k >= 0) {
        final m = _ikiToplamlaBul ? t - k : t;
        if (m <= 0) {
          sonuc = const Text('KDV, toplamdan küçük olmalı.', style: TextStyle(color: Color(0xFFC62828)));
        } else {
          final oran = k / m * 100;
          final yakin = [1.0, 10.0, 20.0].reduce((a, b) => (oran - a).abs() < (oran - b).abs() ? a : b);
          sonuc = _sonuc([
            ('KDV oranı bulma', ''),
            ('KDV hariç tutar (matrah)', tl(kurus(m))),
            ('KDV', tl(k)),
            ('Hesaplanan oran', '%${oran.toStringAsFixed(2).replaceAll('.', ',')}'),
            ('En yakın yasal oran', '%${yakin.toInt()}${(oran - yakin).abs() < 0.05 ? '' : ' (fark var, tutarları kontrol et)'}'),
          ], 'kdv_orani', 'KDV oranı bulma', xlsx: () => kdvOraniBulXlsx(toplamla: _ikiToplamlaBul, tutar: t, kdv: k));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: false, label: Text('Karışık oranlı fiş')), ButtonSegment(value: true, label: Text('Oranı bul'))],
        selected: {_ikiOranBul},
        onSelectionChanged: (v) => setState(() => _ikiOranBul = v.first),
      ),
      const SizedBox(height: 6),
      Text(
        _ikiOranBul
            ? 'Matrah (veya toplam) ile KDV tutarını bilip hangi oranla çıktığını bulursun.'
            : 'Aynı fişte iki farklı KDV oranı varsa, genel toplam ve toplam KDV tutarından her oranın matrahını bulursun (iki bilinmeyenli denklem).',
        style: const TextStyle(fontSize: 12, color: Colors.black87),
      ),
      const SizedBox(height: 12),
      if (_ikiOranBul)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: false, label: Text('Matrah + KDV')), ButtonSegment(value: true, label: Text('Toplam + KDV'))],
            selected: {_ikiToplamlaBul},
            onSelectionChanged: (v) => setState(() => _ikiToplamlaBul = v.first),
          ),
        ),
      MaasAlani(
        controller: _ikiToplam,
        etiket: !_ikiOranBul ? 'Genel toplam, KDV dahil (TL)' : (_ikiToplamlaBul ? 'Toplam, KDV dahil (TL)' : 'KDV hariç tutar / matrah (TL)'),
        ipucu: '0,00',
      ),
      const SizedBox(height: 10),
      MaasAlani(controller: _ikiKdv, etiket: 'Toplam KDV tutarı (TL)', ipucu: '0,00'),
      if (!_ikiOranBul) ...[
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 140, child: TextField(controller: _ikiOran1, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '1. oran (%)', isDense: true))),
          const SizedBox(width: 10),
          SizedBox(width: 140, child: TextField(controller: _ikiOran2, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '2. oran (%)', isDense: true))),
        ]),
      ],
      const SizedBox(height: 14),
      sonuc,
      const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Kuruş yuvarlamaları nedeniyle sonuçta birkaç kuruşluk fark çıkabilir.', style: TextStyle(fontSize: 12, color: Colors.black87)),
      ),
    ]);
  }

  // ---------------------------------------------------------------- Gelir vergisi
  Widget _gelirVergisi() {
    final p = bordroParam(_gvYil)!;
    final m = _sayi(_gvMatrah.text);
    var dilimler = p.dilimler;
    String? tarifeHata;
    if (!_gvUcret) {
      final ust = [for (final c in _gvUst) _sayi(c.text)];
      final oran = [for (final c in _gvOranC) _sayi(c.text)];
      if (ust.any((e) => e == null || e <= 0) || oran.any((e) => e == null || e < 0 || e >= 100)) {
        tarifeHata = 'Dilim sınırlarını ve oranlarını doldur.';
      } else {
        var artan = true;
        for (var i = 1; i < 4; i++) {
          if (ust[i]! <= ust[i - 1]!) artan = false;
        }
        if (!artan) {
          tarifeHata = 'Dilim sınırları artan sırada olmalı.';
        } else {
          dilimler = [for (var i = 0; i < 5; i++) (i < 4 ? ust[i]! : 1e18, oran[i]! / 100)];
        }
      }
    }
    final tarifeAdi = _gvUcret ? 'ücret tarifesi' : 'ücret dışı tarife (elle girilen)';
    Widget sonuc = const Text('Yıllık gelir vergisi matrahını gir.');
    if (tarifeHata != null) {
      sonuc = Text(tarifeHata, style: const TextStyle(color: Colors.red));
    } else if (m != null && m > 0) {
      final satirlar = <_Satir>[('$_gvYil gelir vergisi ($tarifeAdi)', '')];
      var alt = 0.0, kalan = m, toplam = 0.0;
      double sonOran = 0;
      for (final (ust, oran) in dilimler) {
        if (kalan <= 0) break;
        final genislik = ust >= 1e17 ? double.infinity : ust - alt;
        final dilimde = kalan < genislik ? kalan : genislik;
        final v = kurus(dilimde * oran);
        toplam += v;
        kalan -= dilimde;
        sonOran = oran;
        satirlar.add(('${tl(alt)} - ${ust >= 1e17 ? 'üzeri' : tl(ust)}  (%${(oran * 100).round()})', '${tl(dilimde)} → ${tl(v)}'));
        alt = ust;
      }
      satirlar.addAll([
        ('Sonuç', ''),
        ('Toplam gelir vergisi', tl(kurus(toplam))),
        ('Ortalama oran', '%${(toplam / m * 100).toStringAsFixed(2).replaceAll('.', ',')}'),
        ('Son dilim oranı', '%${(sonOran * 100).round()}'),
        ('Vergi sonrası kalan', tl(kurus(m - toplam))),
      ]);
      final d = dilimler;
      sonuc = _sonuc(satirlar, 'gelir_vergisi_$_gvYil', 'Gelir vergisi hesabı $_gvYil',
          xlsx: () => gelirVergisiXlsx(yil: _gvYil, matrah: m, dilimler: d, tarife: _gvUcret ? 'ÜCRET TARİFESİ' : 'ÜCRET DIŞI, ELLE GİRİLEN TARİFE'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Ücret geliri')), ButtonSegment(value: false, label: Text('Ücret dışı gelir'))],
        selected: {_gvUcret},
        onSelectionChanged: (v) => setState(() => _gvUcret = v.first),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<int>(
          initialValue: _gvYil,
          decoration: const InputDecoration(labelText: 'Yıl', isDense: true),
          items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() {
            _gvYil = v ?? _gvYil;
            _gvOzelDoldur();
          }),
        ),
      ),
      if (!_gvUcret) ...[
        const SizedBox(height: 10),
        const Text('Ücret dışı tarife (ticari kazanç, serbest meslek, kira vb.). Alanlar ücret tarifesiyle dolu gelir; sınırları güncel tarifeye göre değiştir.',
            style: TextStyle(fontSize: 12, color: Colors.black87)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 8, children: [
          for (var i = 0; i < 5; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (i < 4) SizedBox(width: 150, child: MaasAlani(controller: _gvUst[i], etiket: '${i + 1}. dilim üst sınır (TL)', ipucu: '0')) else const SizedBox(width: 150, child: Text('5. dilim: sınırsız')),
              const SizedBox(width: 6),
              SizedBox(width: 80, child: TextField(controller: _gvOranC[i], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Oran %', isDense: true))),
            ]),
        ]),
      ],
      const SizedBox(height: 10),
      MaasAlani(controller: _gvMatrah, etiket: 'Yıllık gelir vergisi matrahı (TL)', ipucu: '0,00'),
      const SizedBox(height: 14),
      sonuc,
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          _gvUcret
              ? 'Dilimler bordro hesabında kullanılan ücret geliri tarifesidir. Ücret dışı gelirler için yukarıdan "Ücret dışı gelir"i seç. Mahsup edilecek stopaj ve indirimler dahil değildir.'
              : 'Tarife senin girdiğin sınır ve oranlarla hesaplanır, kontrol et. Mahsup edilecek stopaj ve indirimler dahil değildir.',
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- Damga vergisi
  Widget _damga() {
    final tutar = _sayi(_damgaTutar.text);
    final oran = _sayi(_damgaOran.text);
    Widget sonuc = const Text('Tutarı ve oranı gir.');
    if (tutar != null && tutar > 0 && oran != null && oran >= 0) {
      final v = kurus(tutar * oran / 1000);
      sonuc = _sonuc([
        ('Damga vergisi ($_damgaTur)', ''),
        ('Tutar', tl(tutar)),
        ('Oran', 'binde ${oran.toString().replaceAll('.', ',')}'),
        ('Damga vergisi', tl(v)),
      ], 'damga_vergisi', 'Damga vergisi hesabı', xlsx: () => damgaXlsx(tur: _damgaTur, tutar: tutar, binde: oran));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final e in _damgaTurleri.entries)
          ChoiceChip(
            label: Text(e.value.isEmpty ? e.key : '${e.key} (binde ${e.value})'),
            selected: _damgaTur == e.key,
            onSelected: (_) => setState(() {
              _damgaTur = e.key;
              if (e.value.isNotEmpty) _damgaOran.text = e.value;
            }),
          ),
      ]),
      const SizedBox(height: 10),
      MaasAlani(controller: _damgaTutar, etiket: 'Kâğıdın parasal tutarı (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      SizedBox(
        width: 220,
        child: TextField(controller: _damgaOran, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Oran (binde)', isDense: true)),
      ),
      const SizedBox(height: 14),
      sonuc,
      const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'Oranlar değiştirilebilir. Yıllık azami tutar sınırları, maktu vergiler ve istisnalar uygulanmaz; '
          '(298 s. Kanun ekli (1) sayılı tablo ve yıllık sınırlar) güncel tutarları ayrıca kontrol et.',
          style: TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------- Net - brüt maaş
  Widget _maasHesap() {
    final p = bordroParam(_maasYil)!;
    final u = _sayi(_maas.text);
    Widget sonuc = const Text('Maaşı gir.');
    if (u != null && u > 0) {
      final liste = yillikBordro(p, BordroGirdi(ucret: u, net: _maasNet, asgari: false, giris: DateTime(_maasYil, 1, 1)), 12);
      final satirlar = <_Satir>[('$_maasYil net - brüt maaş (yıl başından çalışan, kümülatif matrah)', '')];
      for (final b in liste) {
        satirlar.add((bordroAylar[b.ay - 1], 'Brüt ${tl(b.brut)}  Net ${tl(b.net)}  GV ${tl(b.gelirVergisi)}  Damga ${tl(b.damga)}'));
      }
      sonuc = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sonuc([
          (_maasNet ? 'Net ${tl(u)} için brüt' : 'Brüt ${tl(u)} için net', ''),
          ('Ocak', _maasNet ? 'Brüt ${tl(liste.first.brut)}' : 'Net ${tl(liste.first.net)}'),
          ('Aralık', _maasNet ? 'Brüt ${tl(liste.last.brut)}' : 'Net ${tl(liste.last.net)}'),
          ('Yıllık işveren maliyeti', tl(kurus(liste.fold(0.0, (a, b) => a + b.maliyet)))),
        ], 'maas_$_maasYil', 'Net - brüt maaş $_maasYil',
            xlsx: () => maasXlsx(
                yil: _maasYil,
                netGirildi: _maasNet,
                maas: u,
                aylar: [for (final b in liste) [b.brut, b.sgkIsci + b.issizlikIsci, b.gelirVergisi, b.damga, b.net, b.maliyet]])),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 38,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 34,
            columns: const [
              DataColumn(label: Text('Ay')),
              DataColumn(label: Text('Brüt'), numeric: true),
              DataColumn(label: Text('SGK+İşsizlik'), numeric: true),
              DataColumn(label: Text('Gelir vergisi'), numeric: true),
              DataColumn(label: Text('Damga'), numeric: true),
              DataColumn(label: Text('Net'), numeric: true),
              DataColumn(label: Text('İşveren maliyeti'), numeric: true),
            ],
            rows: [
              for (final b in liste)
                DataRow(cells: [
                  DataCell(Text(bordroAylar[b.ay - 1])),
                  DataCell(Text(tl(b.brut))),
                  DataCell(Text(tl(b.sgkIsci + b.issizlikIsci))),
                  DataCell(Text(tl(b.gelirVergisi))),
                  DataCell(Text(tl(b.damga))),
                  DataCell(Text(tl(b.net))),
                  DataCell(Text(tl(b.maliyet))),
                ]),
            ],
          ),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Net maaştan brüte')), ButtonSegment(value: false, label: Text('Brüt maaştan nete'))],
        selected: {_maasNet},
        onSelectionChanged: (v) => setState(() => _maasNet = v.first),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<int>(
          initialValue: _maasYil,
          decoration: const InputDecoration(labelText: 'Yıl', isDense: true),
          items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _maasYil = v ?? _maasYil),
        ),
      ),
      const SizedBox(height: 10),
      MaasAlani(controller: _maas, etiket: _maasNet ? 'Net maaş (TL)' : 'Brüt maaş (TL)', ipucu: '0,00'),
      const SizedBox(height: 14),
      sonuc,
      const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'Bordro modülündeki hesap motoruyla aynıdır: yıl başından itibaren çalışan, kümülatif gelir vergisi matrahı, asgari ücret gelir ve damga vergisi istisnası, '
          'varsayılan işveren SGK indirimi. Yıl içinde başlayan veya eksik gün olan personel için Bordro bölümünü kullan.',
          style: TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
    ]);
  }

  String _yz(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');

  Widget _oranAlani(TextEditingController c, String etiket, {double genislik = 200}) => SizedBox(
        width: genislik,
        child: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: etiket, isDense: true)),
      );

  Widget _not(String m) => Padding(padding: const EdgeInsets.only(top: 10), child: Text(m, style: const TextStyle(fontSize: 12, color: Colors.black87)));

  // ---------------------------------------------------------------- Ücretli yıllık beyan
  void _ybSatirEkle() {
    final a = TextEditingController(), b = TextEditingController();
    a.addListener(() => setState(() {}));
    b.addListener(() => setState(() {}));
    setState(() => _ybIsv.add((a, b)));
  }

  void _ybSatirSil(int i) {
    final (a, b) = _ybIsv[i];
    setState(() => _ybIsv.removeAt(i));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      a.dispose();
      b.dispose();
    });
  }

  Widget _ybBeyan() {
    final p = bordroParam(_ybYil)!;
    var dilimler = p.dilimler;
    String? hata;
    if (_ybDisTarife) {
      final ust = [for (final c in _gvUst) _sayi(c.text)];
      final oran = [for (final c in _gvOranC) _sayi(c.text)];
      var ok = !ust.any((e) => e == null || e <= 0) && !oran.any((e) => e == null || e < 0 || e >= 100);
      for (var i = 1; ok && i < 4; i++) {
        if (ust[i]! <= ust[i - 1]!) ok = false;
      }
      if (!ok) {
        hata = 'Ücret dışı tarife sınırları eksik veya hatalı. Gelir vergisi sekmesinde "Ücret dışı gelir"i seçip düzelt.';
      } else {
        dilimler = [for (var i = 0; i < 5; i++) (i < 4 ? ust[i]! : 1e18, oran[i]! / 100)];
      }
    }
    var ucretMatrah = 0.0, kesilen = 0.0;
    var doldu = false;
    for (final (a, b) in _ybIsv) {
      final m = _sayi(a.text), k = _sayi(b.text);
      if (m != null && m > 0) {
        ucretMatrah += m;
        doldu = true;
      }
      if (k != null && k > 0) kesilen += k;
    }
    // Kira: istisnayı aşan tutardan götürü (%15) veya gerçek gider (istisnaya isabet eden kısım hariç) düşülür
    final kiraGelir = _sayi(_ybKira.text) ?? 0;
    var kiraSafi = 0.0;
    if (kiraGelir > 0) {
      final ist = _sayi(_ybKiraIst.text) ?? 0;
      final asan = kiraGelir > ist ? kiraGelir - ist : 0.0;
      final gider = _ybKiraGotur ? kurus(asan * 0.15) : kurus((_sayi(_ybKiraGider.text) ?? 0) * asan / kiraGelir);
      kiraSafi = asan - gider;
    }
    final diger = (_sayi(_ybDiger.text) ?? 0) + kiraSafi;
    final sigorta = _sayi(_ybSigorta.text) ?? 0, sigLimit = _sayi(_ybSigLimit.text);
    final sigortaInd = sigLimit != null && sigLimit >= 0 && sigorta > sigLimit ? sigLimit : sigorta;
    final bagis = _sayi(_ybBagis.text) ?? 0, bagisPct = _sayi(_ybBagisPct.text);
    final gelirOnce = ucretMatrah + diger;
    final bagisInd = bagisPct != null && bagisPct >= 0 && bagis > gelirOnce * bagisPct / 100 ? kurus(gelirOnce * bagisPct / 100) : bagis;
    final egitim = _sayi(_ybEgitim.text) ?? 0;
    final indirim = sigortaInd + bagisInd + egitim + (_sayi(_ybIndirim.text) ?? 0);
    final istisna = _sayi(_ybIstisna.text) ?? 0;
    final stopaj = _sayi(_ybStopaj.text) ?? 0;

    Widget sonuc = const Text('İşverenlerden alınan ücretin yıllık matrahını gir.');
    if (hata != null) {
      sonuc = Text(hata, style: const TextStyle(color: Colors.red));
    } else if (doldu || diger > 0 || kiraGelir > 0) {
      final toplam = ucretMatrah + diger;
      final matrah = toplam > indirim ? toplam - indirim : 0.0;
      final satirlar = <_Satir>[('$_ybYil ücretli yıllık beyan', '')];
      var alt = 0.0, kalan = matrah, vergi = 0.0;
      for (final (ust, oran) in dilimler) {
        if (kalan <= 0) break;
        final genislik = ust >= 1e17 ? double.infinity : ust - alt;
        final dilimde = kalan < genislik ? kalan : genislik;
        final v = kurus(dilimde * oran);
        vergi += v;
        kalan -= dilimde;
        satirlar.add(('${tl(alt)} - ${ust >= 1e17 ? 'üzeri' : tl(ust)}  (%${(oran * 100).round()})', '${tl(dilimde)} → ${tl(v)}'));
        alt = ust;
      }
      vergi = kurus(vergi);
      final mahsup = kurus(kesilen + stopaj);
      final fark = kurus(vergi - istisna - mahsup);
      satirlar.addAll([
        ('Beyan', ''),
        ('İşverenlerden ücret matrahı toplamı', tl(ucretMatrah)),
        if (kiraSafi > 0) ('Kira geliri (istisna ve gider sonrası)', tl(kiraSafi)),
        if (diger - kiraSafi > 0) ('Diğer gelirler', tl(diger - kiraSafi)),
        if (sigortaInd > 0) ('İndirim: sigorta primleri', '-${tl(sigortaInd)}'),
        if (bagisInd > 0) ('İndirim: bağış ve yardımlar', '-${tl(bagisInd)}'),
        if (egitim > 0) ('İndirim: eğitim ve sağlık harcamaları', '-${tl(egitim)}'),
        if ((_sayi(_ybIndirim.text) ?? 0) > 0) ('İndirim: diğer', '-${tl(_sayi(_ybIndirim.text)!)}'),
        if (indirim > 0) ('Toplam indirim', '-${tl(kurus(indirim))}'),
        ('Gelir vergisi matrahı', tl(matrah)),
        ('Hesaplanan gelir vergisi', tl(vergi)),
        if (istisna > 0) ('Asgari ücret gelir vergisi istisnası', '-${tl(istisna)}'),
        ('İşverenlerce kesilen gelir vergisi', '-${tl(kurus(kesilen))}'),
        if (stopaj > 0) ('Diğer stopaj kesintisi', '-${tl(stopaj)}'),
        (fark >= 0 ? '>Ek ödenecek vergi' : '>Mahsup sonrası iade / sonraki mahsup', tl(fark.abs())),
        ('Efektif vergi oranı', '%${(matrah > 0 ? vergi / matrah * 100 : 0).toStringAsFixed(2).replaceAll('.', ',')}'),
      ]);
      sonuc = _sonuc(satirlar, 'ucretli_yillik_beyan_$_ybYil', 'Ücretli yıllık beyan $_ybYil',
          vadeler: [('Yıllık gelir vergisi beyanı son günü', DateTime(_ybYil + 1, 3, 31))]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<int>(
          initialValue: _ybYil,
          decoration: const InputDecoration(labelText: 'Yıl (tarife)', isDense: true),
          items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _ybYil = v ?? _ybYil),
        ),
      ),
      const SizedBox(height: 10),
      const Text('İşverenler', style: TextStyle(fontWeight: FontWeight.w700)),
      const Text('Her işveren için yıllık gelir vergisi matrahını ve işverenin kestiği toplam gelir vergisini bordrolardan gir.', style: TextStyle(fontSize: 12, color: Colors.black87)),
      const SizedBox(height: 6),
      for (var i = 0; i < _ybIsv.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 260, child: MaasAlani(controller: _ybIsv[i].$1, etiket: '${i + 1}. işveren: yıllık GV matrahı (TL)', ipucu: '0,00')),
            SizedBox(width: 260, child: MaasAlani(controller: _ybIsv[i].$2, etiket: '${i + 1}. işveren: kesilen gelir vergisi (TL)', ipucu: '0,00')),
            if (_ybIsv.length > 1) IconButton(tooltip: 'Satırı sil', onPressed: () => _ybSatirSil(i), icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _ybSatirEkle, icon: const Icon(Icons.add), label: const Text('İşveren ekle'))),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(width: 260, child: MaasAlani(controller: _ybDiger, etiket: 'Diğer gelirler, safi tutar (TL)', ipucu: '0,00')),
      ]),
      const SizedBox(height: 8),
      const Text('Kira geliri (varsa)', style: TextStyle(fontWeight: FontWeight.w700)),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Götürü gider (%15)')), ButtonSegment(value: false, label: Text('Gerçek gider'))],
        selected: {_ybKiraGotur},
        onSelectionChanged: (v) => setState(() => _ybKiraGotur = v.first),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(width: 260, child: MaasAlani(controller: _ybKira, etiket: 'Yıllık brüt kira geliri (TL)', ipucu: '0,00')),
        if (!_ybKiraGotur) SizedBox(width: 260, child: MaasAlani(controller: _ybKiraGider, etiket: 'Belgeli giderler toplamı (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _ybKiraIst, etiket: 'Konut kira istisnası tutarı (TL, varsa)', ipucu: '0,00')),
      ]),
      const SizedBox(height: 8),
      const Text('İndirimler', style: TextStyle(fontWeight: FontWeight.w700)),
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(width: 260, child: MaasAlani(controller: _ybSigorta, etiket: 'Hayat / şahıs sigortası primleri (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _ybSigLimit, etiket: 'Sigorta indirimi üst sınırı (TL, boşsa sınırsız)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _ybBagis, etiket: 'Bağış ve yardımlar (TL)', ipucu: '0,00')),
        _oranAlani(_ybBagisPct, 'Bağış sınırı (% gelir, boşsa sınırsız)', genislik: 260),
        SizedBox(width: 260, child: MaasAlani(controller: _ybEgitim, etiket: 'Eğitim ve sağlık harcamaları (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _ybIndirim, etiket: 'Diğer indirimler (TL)', ipucu: '0,00')),
      ]),
      const SizedBox(height: 8),
      const Text('Mahsup', style: TextStyle(fontWeight: FontWeight.w700)),
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(width: 260, child: MaasAlani(controller: _ybIstisna, etiket: 'Uygulanan asgari ücret GV istisnası toplamı (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _ybStopaj, etiket: 'Kesilen diğer stopajlar, örn. kira (TL)', ipucu: '0,00')),
      ]),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _ybDisTarife,
        onChanged: (v) => setState(() => _ybDisTarife = v ?? false),
        title: const Text('Ücret dışı tarifeyi kullan (Gelir vergisi sekmesindeki elle girilen sınırlar)'),
      ),
      const SizedBox(height: 8),
      sonuc,
      _not('İşveren matrahları ve kesilen vergiler bordrolardan alınır. Asgari ücret istisnası bordroda zaten düşülmüş olduğundan buraya ayrıca yazılır. '
          'Beyan zorunluluğu sınırları, indirim türleri ve üst sınırları (bağış, eğitim, sağlık, sigorta primi) ve indirimin hangi gelirden düşüleceği bu araçta kontrol edilmez, güncel mevzuattan doğrula.'),
    ]);
  }

  // ---------------------------------------------------------------- Kâr dağıtımı
  void _krOrtakEkle() {
    final o = _Ortak();
    o.ad.addListener(() => setState(() {}));
    o.pay.addListener(() => setState(() {}));
    setState(() => _krOrtaklar.add(o));
  }

  void _krOrtakSil(int i) {
    final o = _krOrtaklar[i];
    setState(() => _krOrtaklar.removeAt(i));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      o.ad.dispose();
      o.tc.dispose();
      o.pay.dispose();
    });
  }

  String _tr(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Widget _karDagitimi() {
    final kar = _sayi(_krKar.text);
    final zarar = _sayi(_krZarar.text) ?? 0;
    final sermaye = _sayi(_krSermaye.text) ?? 0;
    final mevcutYedek = _sayi(_krYedek.text) ?? 0;
    final ek = _sayi(_krEk.text) ?? 0;
    final birPct = _sayi(_krBirinciPct.text) ?? 0;
    final dagPct = _sayi(_krDagitPct.text) ?? 100;
    final stopajPct = _sayi(_krStopaj.text) ?? 0;
    Widget sonuc = const Text('Net dönem kârını gir.');
    KarBelgeVeri? belge;
    DateTime? muhtasarGun;
    if (kar != null && kar > 0) {
      final zararSonrasi = kar > zarar ? kar - zarar : 0.0;
      var yedek1 = 0.0;
      if (_krYedek1) {
        var tavan = sermaye > 0 ? sermaye * 0.20 - mevcutYedek : double.infinity;
        if (tavan < 0) tavan = 0;
        final onBes = kurus(zararSonrasi * 0.05);
        yedek1 = onBes < tavan ? onBes : tavan;
      }
      final dagitilabilir = kurus(zararSonrasi - yedek1 + ek);
      final birinciTavan = kurus(sermaye * birPct / 100);
      final birinci = dagitilabilir < birinciTavan ? dagitilabilir : birinciTavan;
      final kalan = kurus(dagitilabilir - birinci);
      final havuz = kurus(kalan * dagPct / 100);
      final ikinci = _krYedek2 ? kurus(havuz / 1.1) : havuz;
      final yedek2 = kurus(havuz - ikinci);
      final toplamPay = kurus(birinci + ikinci);
      final olaganustu = kurus(kalan - havuz);
      final satirlar = <_Satir>[
        ('Kâr dağıtım tablosu', ''),
        ('Net dönem kârı', tl(kar)),
        if (zarar > 0) ('Geçmiş yıl zararları', '-${tl(zarar > kar ? kar : zarar)}'),
        if (zarar > 0) ('Zarar mahsubundan sonra kâr', tl(zararSonrasi)),
        if (yedek1 > 0) ('Genel kanuni yedek akçe (%5)', '-${tl(yedek1)}'),
        if (ek > 0) ('Eklenen geçmiş yıl kârı / dağıtılabilir yedek', tl(ek)),
        ('>Dağıtılabilir kâr', tl(dagitilabilir)),
        ('Birinci kâr payı (sermayenin %${_yz(birPct)}\'i)', tl(birinci)),
        ('İkinci kâr payı', tl(ikinci)),
        if (yedek2 > 0) ('İkinci tertip yedek akçe', tl(yedek2)),
        if (olaganustu > 0) ('Olağanüstü yedeğe / geçmiş kâra bırakılan', tl(olaganustu)),
        ('>Toplam dağıtılacak brüt kâr payı', tl(toplamPay)),
      ];
      var payToplam = 0.0, stopajToplam = 0.0, netToplam = 0.0, stopajMatrah = 0.0, stopajsiz = 0.0;
      final ortakSatir = <_Satir>[];
      for (var i = 0; i < _krOrtaklar.length; i++) {
        final o = _krOrtaklar[i];
        final pay = _sayi(o.pay.text);
        if (pay == null || pay <= 0) continue;
        payToplam += pay;
        final brut = kurus(toplamPay * pay / 100);
        final st = o.stopajli ? kurus(brut * stopajPct / 100) : 0.0;
        if (o.stopajli) {
          stopajMatrah += brut;
        } else {
          stopajsiz += brut;
        }
        stopajToplam += st;
        netToplam += brut - st;
        final ad = o.ad.text.trim().isEmpty ? '${i + 1}. ortak' : o.ad.text.trim();
        final kimlik = o.tc.text.trim().isEmpty ? '' : ' - ${o.tc.text.trim()}';
        ortakSatir.add(('$ad$kimlik (%${_yz(pay)})', 'Brüt ${tl(brut)}  Stopaj ${tl(st)}  Net ${tl(kurus(brut - st))}'));
        if (o.stopajli) {
          ortakSatir.add(('   Beyanda gösterilecek kâr payı (yarısı) / mahsup stopaj', '${tl(kurus(brut / 2))} / ${tl(st)}'));
        }
      }
      if (ortakSatir.isNotEmpty) {
        satirlar.add(('Kâr payı bilgileri', ''));
        satirlar.add(('Dağıtım / ödeme tarihi', _tr(_krTarih)));
        if (_krGk.text.trim().isNotEmpty) satirlar.add(('Genel kurul karar tarihi', _krGk.text.trim()));
        satirlar.add(('Brüt dağıtılan kâr payı', tl(toplamPay)));
        satirlar.add(('Net ödenen kâr payı', tl(kurus(netToplam))));
        satirlar.add(('Ortaklara dağıtım', ''));
        satirlar.addAll(ortakSatir);
        final sonGun = DateTime(_krTarih.year, _krTarih.month + 1, 26);
        muhtasarGun = sonGun;
        satirlar.add(('Muhtasar beyanname bildirimi (kâr payı stopajı)', ''));
        satirlar.add(('Stopaja tabi brüt kâr payı (matrah)', tl(kurus(stopajMatrah))));
        satirlar.add(('Stopaj oranı', '%${_yz(stopajPct)}'));
        satirlar.add(('>Kesilecek ve bildirilecek stopaj', tl(kurus(stopajToplam))));
        if (stopajsiz > 0) satirlar.add(('Stopaj kesilmeyen kâr payı (kurum ortaklar vb.)', tl(kurus(stopajsiz))));
        satirlar.add(('Beyan ve ödeme için son gün (ertesi ayın 26\'sı)', _tr(sonGun)));
        if ((payToplam - 100).abs() > 0.005) satirlar.add(('Uyarı: pay oranları toplamı', '%${_yz(payToplam)} (100 olmalı)'));
      }
      sonuc = _sonuc(satirlar, 'kar_dagitimi', 'Kâr dağıtımı hesabı',
          vadeler: [if (muhtasarGun != null && stopajToplam > 0) ('Kâr payı stopajı muhtasar son günü', muhtasarGun)]);
      if (ortakSatir.isNotEmpty && toplamPay > 0) {
        belge = KarBelgeVeri(
          unvan: _krUnvan.text.trim().isEmpty ? 'ŞİRKET' : _krUnvan.text.trim(),
          donem: _krDonem.text.trim().isEmpty ? '${DateTime.now().year - 1}' : _krDonem.text.trim(),
          genelKurulTarihi: _krGk.text,
          odemeTarihi: _krTarih,
          kar: kar,
          zarar: zarar,
          yedek1: yedek1,
          dagitilabilir: dagitilabilir,
          birinci: birinci,
          ikinci: ikinci,
          yedek2: yedek2,
          olaganustu: olaganustu,
          toplamPay: toplamPay,
          stopajOrani: stopajPct,
          ortaklar: [
            for (final o in _krOrtaklar)
              if ((_sayi(o.pay.text) ?? 0) > 0)
                () {
                  final pay = _sayi(o.pay.text)!;
                  final brut = kurus(toplamPay * pay / 100);
                  final st = o.stopajli ? kurus(brut * stopajPct / 100) : 0.0;
                  return OrtakPayi(
                    ad: o.ad.text.trim().isEmpty ? '${_krOrtaklar.indexOf(o) + 1}. ortak' : o.ad.text.trim(),
                    tc: o.tc.text.trim(),
                    pay: pay,
                    brut: brut,
                    stopaj: st,
                    net: kurus(brut - st),
                  );
                }(),
          ],
        );
      }
    } else if (kar != null && kar <= 0) {
      sonuc = const Text('Dönem zararı varsa kâr dağıtımı yapılamaz.', style: TextStyle(color: Colors.red));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(width: 260, child: MaasAlani(controller: _krKar, etiket: 'Net dönem kârı, vergi sonrası (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _krZarar, etiket: 'Geçmiş yıl zararları (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _krSermaye, etiket: 'Ödenmiş sermaye (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _krYedek, etiket: 'Mevcut genel kanuni yedek akçe (TL)', ipucu: '0,00')),
        SizedBox(width: 260, child: MaasAlani(controller: _krEk, etiket: 'Dağıtıma eklenecek geçmiş yıl kârı / yedek (TL)', ipucu: '0,00')),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_krBirinciPct, 'Birinci kâr payı (sermayenin %)', genislik: 260),
        _oranAlani(_krDagitPct, 'Kalandan dağıtılacak oran (%)', genislik: 260),
        _oranAlani(_krStopaj, 'Kâr payı stopaj oranı (%)', genislik: 260),
      ]),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _krYedek1,
        onChanged: (v) => setState(() => _krYedek1 = v ?? true),
        title: const Text('Genel kanuni yedek akçe ayır (%5, sermayenin %20\'sine kadar)'),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _krYedek2,
        onChanged: (v) => setState(() => _krYedek2 = v ?? true),
        title: const Text('İkinci tertip yedek akçe ayır (birinci kâr payı sonrası dağıtımın %10\'u)'),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(width: 340, child: TextField(controller: _krUnvan, decoration: const InputDecoration(labelText: 'Şirket unvanı (belgelerde yazar)', isDense: true))),
        SizedBox(width: 140, child: TextField(controller: _krDonem, decoration: const InputDecoration(labelText: 'Kâr dönemi (yıl)', isDense: true))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _krTarih, firstDate: DateTime(2000), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
            if (d != null) setState(() => _krTarih = d);
          },
          icon: const Icon(Icons.event, size: 18),
          label: Text('Dağıtım / ödeme tarihi: ${_tr(_krTarih)}'),
        ),
        SizedBox(width: 260, child: TextField(controller: _krGk, decoration: const InputDecoration(labelText: 'Genel kurul karar tarihi (isteğe bağlı)', isDense: true))),
      ]),
      const SizedBox(height: 6),
      const Text('Ortaklar', style: TextStyle(fontWeight: FontWeight.w700)),
      for (var i = 0; i < _krOrtaklar.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 200, child: TextField(controller: _krOrtaklar[i].ad, decoration: const InputDecoration(labelText: 'Ortak adı', isDense: true))),
            SizedBox(width: 150, child: TextField(controller: _krOrtaklar[i].tc, decoration: const InputDecoration(labelText: 'TC / vergi no', isDense: true))),
            _oranAlani(_krOrtaklar[i].pay, 'Pay oranı (%)', genislik: 120),
            FilterChip(
              label: const Text('Stopaj kesilir'),
              selected: _krOrtaklar[i].stopajli,
              onSelected: (v) => setState(() => _krOrtaklar[i].stopajli = v),
            ),
            if (_krOrtaklar.length > 1) IconButton(tooltip: 'Ortağı sil', onPressed: () => _krOrtakSil(i), icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _krOrtakEkle, icon: const Icon(Icons.add), label: const Text('Ortak ekle'))),
      const SizedBox(height: 8),
      sonuc,
      if (belge != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await genelKurulKarariPdf(belge!);
                } catch (e) {
                  _bilgi('PDF hazırlanamadı: $e');
                }
              },
              icon: const Icon(Icons.gavel_outlined, size: 18),
              label: const Text('Genel kurul karar taslağı (PDF)'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await karPayiMakbuzlariPdf(belge!);
                } catch (e) {
                  _bilgi('PDF hazırlanamadı: $e');
                }
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Kâr payı makbuzları (PDF)'),
            ),
          ]),
        ),
      _not('Genel akış TTK m.519 mantığıyla kurulmuştur: zararlar düşülür, %5 genel yedek ayrılır, birinci kâr payı ödenir, kalandan dağıtım yapılır. '
          'Esas sözleşmede farklı oran, imtiyaz veya yedek hükmü varsa alanları ona göre değiştir (Ltd. için birinci kâr payı yoksa oranı 0 yaz). '
          'Stopaj oranını güncel karardan kontrol et; tam mükellef kurum ortaklarda stopaj kesilmez, o satırda "Stopaj kesilir"i kapat. '
          'Muhtasar son günü ödeme tarihinden sonraki ayın 26\'sı olarak alınır, hafta sonu ve tatil kaydırması yapılmaz. Gerçek kişi ortakta beyan edilecek tutar kâr payının yarısı olarak gösterilir; beyan sınırı ve istisna durumunu ayrıca kontrol et. Dağıtım için genel kurul kararı ve defter kayıtları ayrıca gerekir.'),
    ]);
  }

  // ---------------------------------------------------------------- Finansman gider kısıtlaması
  Future<void> _fgMizan() async {
    final r = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    try {
      final m = mizanOku(r.files.first.bytes!);
      final o = mizanOzetle(m);
      double topla(String onek) {
        var t = 0.0;
        for (final x in m.satirlar) {
          if (x.kod.startsWith(onek)) t += x.net;
        }
        return t;
      }

      final g66 = topla('66'), g78 = topla('78');
      setState(() {
        _fgYk.text = mizanTl(o.kv + o.uv);
        _fgOkNeg = o.ozk < 0;
        _fgOk.text = mizanTl(o.ozk.abs());
        _fgGider.text = mizanTl(g66 > 0 ? g66 : (g78 > 0 ? g78 : 0));
      });
      _bilgi('Mizandan dolduruldu. Finansman gideri 66 (yoksa 78) hesaplarından alındı; kur farkı gideri (656 vb.) ve kısıtlama dışı tutulacak tutarları ayrıca kontrol et.');
    } catch (e) {
      _bilgi('Mizan okunamadı: $e');
    }
  }

  Widget _finansmanKisit() {
    final yk = _sayi(_fgYk.text), okAbs = _sayi(_fgOk.text), gider = _sayi(_fgGider.text);
    final haric = _sayi(_fgHaric.text) ?? 0, kisit = _sayi(_fgOran.text), kvOran = _sayi(_fgKv.text);
    Widget sonuc = const Text('Yabancı kaynak, öz kaynak ve finansman giderini gir.');
    if (_fgMuaf) {
      sonuc = _sonuc([
        ('Kısıtlama uygulanmaz', ''),
        ('Kapsam dışı kuruluş', '-'),
        ('>Kanunen kabul edilmeyen gider (KKEG)', tl(0)),
      ], 'finansman_gider_kisitlamasi', 'Finansman gider kısıtlaması');
    } else if (yk != null && yk > 0 && okAbs != null && gider != null && kisit != null && kisit >= 0) {
      final ok = _fgOkNeg ? -okAbs : okAbs;
      final asan = yk - ok;
      final satirlar = <_Satir>[
        ('Bilanço karşılaştırması (vergi öncesi, VUK bilançosu)', ''),
        ('Yabancı kaynak toplamı', tl(yk)),
        ('Öz kaynak toplamı', tl(ok)),
        ('Aşan kısım (yabancı kaynak - öz kaynak)', asan > 0 ? tl(asan) : '-'),
      ];
      if (asan <= 0) {
        satirlar.addAll([
          ('Yabancı kaynak öz kaynağı aşmıyor, kısıtlama yok', '-'),
          ('>Kanunen kabul edilmeyen gider (KKEG)', tl(0)),
        ]);
      } else {
        final ham = asan / yk;
        final oran = ham > 1 ? 1.0 : ham;
        final esas = (gider - haric) > 0 ? kurus(gider - haric) : 0.0;
        final isabet = kurus(esas * oran);
        final kkeg = kurus(isabet * kisit / 100);
        satirlar.addAll([
          ('Aşan kısmın yabancı kaynağa oranı', '%${_yz(double.parse((oran * 100).toStringAsFixed(2)))}'),
          if (ham > 1) ('Öz kaynak negatif: oran %100 ile sınırlandı, ayrıca kontrol et', ''),
          ('Finansman giderleri (toplam)', tl(gider)),
          ('Kısıtlama dışında tutulan giderler', tl(haric)),
          ('Kısıtlamaya esas finansman gideri', tl(esas)),
          ('Aşan kısma isabet eden gider', tl(isabet)),
          ('Kısıtlama oranı', '%${_yz(kisit)}'),
          ('>Kanunen kabul edilmeyen gider (KKEG)', tl(kkeg)),
          ('Beyannameye göre indirilebilecek finansman gideri', tl(kurus(gider - kkeg))),
          if (kvOran != null && kvOran > 0) ('Ek kurumlar vergisi (%${_yz(kvOran)})', tl(kurus(kkeg * kvOran / 100))),
        ]);
      }
      sonuc = _sonuc(satirlar, 'finansman_gider_kisitlamasi', 'Finansman gider kısıtlaması');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _fgMuaf,
        onChanged: (v) => setState(() => _fgMuaf = v ?? false),
        title: const Text('Kapsam dışı kuruluş (kredi kuruluşu, finansal kiralama, faktoring, finansman şirketi vb.)'),
      ),
      const SizedBox(height: 4),
      OutlinedButton.icon(onPressed: _fgMizan, icon: const Icon(Icons.upload_file), label: const Text('Mizandan doldur')),
      const SizedBox(height: 12),
      MaasAlani(controller: _fgYk, etiket: 'Yabancı kaynak toplamı (kısa + uzun vadeli, TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _fgOk, etiket: 'Öz kaynak toplamı (dönem kârı vergi öncesi dahil, TL)', ipucu: '0,00'),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _fgOkNeg,
        onChanged: (v) => setState(() => _fgOkNeg = v ?? false),
        title: const Text('Öz kaynak toplamı negatif (eksi)'),
      ),
      MaasAlani(controller: _fgGider, etiket: 'Dönem finansman giderleri (faiz, komisyon, vade farkı, kur farkı vb., TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _fgHaric, etiket: 'Kısıtlama dışında tutulacak giderler (yatırım maliyetine eklenen vb., TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_fgOran, 'Kısıtlama oranı (%)', genislik: 200),
        _oranAlani(_fgKv, 'Kurumlar vergisi oranı (%, isteğe bağlı)', genislik: 260),
      ]),
      const SizedBox(height: 14),
      sonuc,
      _not('Dayanak: KVK m.11/1-i. Her geçici vergilendirme döneminin sonunda ve yıl sonunda, finansman gider kısıtlaması öncesi (vergi öncesi) VUK bilançosundaki yabancı kaynak ile öz kaynak karşılaştırılır; '
          'yabancı kaynak öz kaynağı aşıyorsa finansman giderinin aşan kısma isabet eden bölümünün kısıtlama oranı kadarı kanunen kabul edilmeyen gider olarak beyannameye eklenir. '
          'Geçici vergi dönemlerinde tutarları o dönem sonuna kadar kümülatif gir. Finansman geliri finansman giderinden mahsup edilmez.'),
      _not('Kısıtlama oranı: Kanun, oranı %10\'u aşmamak üzere Cumhurbaşkanı kararına bırakır; 1/1/2021 başlangıçlı dönemlerden itibaren kararla %10 belirlenmiştir. Güncel kararı kontrol edip gerekirse oranı değiştir.'),
      _not('Genellikle kısıtlama dışında tutulan giderler: yatırım maliyetine eklenen finansman giderleri, uzun vadeli inşaat ve onarma işlerine ilişkin giderler, yabancı kaynak kullanımıyla ilgisi olmayan giderler (teminat mektubu komisyonu, kredi sözleşmesi damga vergisi gibi). Kredi kuruluşları, finansal kiralama, faktoring ve finansman şirketleri kapsam dışındadır. '
          'Taşıt kiralama, örtülü sermaye ve transfer fiyatlandırması gibi başka sınırlamalarla zaten kabul edilmeyen tutarlar da hariç tutulur; hepsini kontrol edip "dışında tutulan" alanına yaz.'),
    ]);
  }

  // ---------------------------------------------------------------- Ortak cari hesap faizi
  Widget _ortakFaiz() {
    final t = _sayi(_ofTutar.text), o = _sayi(_ofOran.text), emsal = _sayi(_ofEmsal.text);
    final gun = _ofBit.difference(_ofBas).inDays;
    Widget sonuc = const Text('Tutarı, faiz oranını ve tarihleri gir.');
    if (t != null && t > 0 && o != null && o >= 0 && gun > 0) {
      final faiz = kurus(t * o / 100 * gun / 365);
      final satirlar = <_Satir>[
        (_ofSirketAlacakli ? 'Ortağın şirketten çektiği tutar: şirket alacaklı' : 'Ortağın şirkete borç verdiği tutar: şirket borçlu', ''),
        ('Anapara', tl(t)),
        ('Dönem', '${_tr(_ofBas)} - ${_tr(_ofBit)} ($gun gün)'),
        ('Uygulanan yıllık faiz', '%${_yz(o)}'),
        ('>Hesaplanan faiz (basit, yıl 365 gün)', tl(faiz)),
        ('Anapara + faiz', tl(kurus(t + faiz))),
      ];
      if (emsal != null && emsal > 0) {
        final emsalFaiz = kurus(t * emsal / 100 * gun / 365);
        final fark = kurus(emsalFaiz - faiz);
        satirlar.addAll([
          ('Emsal faiz karşılaştırması', ''),
          ('Emsal yıllık faiz', '%${_yz(emsal)}'),
          ('Emsal faizle tutar', tl(emsalFaiz)),
          if (_ofSirketAlacakli)
            (fark > 0 ? '>Eksik hesaplanan faiz (örtülü kazanç riski)' : 'Uygulanan faiz emsalin altında değil', fark > 0 ? tl(fark) : '-')
          else
            (fark < 0 ? '>Emsali aşan faiz (gider kabul edilmeme riski)' : 'Uygulanan faiz emsali aşmıyor', fark < 0 ? tl(-fark) : '-'),
        ]);
      }
      sonuc = _sonuc(satirlar, 'ortak_cari_faiz', 'Ortak cari hesap faizi');
    }
    Widget tarih(String e, DateTime d, void Function(DateTime) ata) => OutlinedButton.icon(
          onPressed: () async {
            final x = await showDatePicker(context: context, initialDate: d, firstDate: DateTime(2000), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
            if (x != null) setState(() => ata(x));
          },
          icon: const Icon(Icons.event, size: 18),
          label: Text('$e: ${_tr(d)}'),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Ortak şirketten çekti')), ButtonSegment(value: false, label: Text('Ortak şirkete borç verdi'))],
        selected: {_ofSirketAlacakli},
        onSelectionChanged: (v) => setState(() => _ofSirketAlacakli = v.first),
      ),
      const SizedBox(height: 12),
      MaasAlani(controller: _ofTutar, etiket: 'Tutar (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_ofOran, 'Uygulanan yıllık faiz (%)', genislik: 240),
        _oranAlani(_ofEmsal, 'Emsal yıllık faiz (%, isteğe bağlı)', genislik: 260),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        tarih('Başlangıç', _ofBas, (x) => _ofBas = x),
        tarih('Bitiş', _ofBit, (x) => _ofBit = x),
      ]),
      const SizedBox(height: 14),
      sonuc,
      _not('Tek tutar ve tek dönem için basit faiz hesaplar. Tutar dönem içinde değişiyorsa her dönemi ayrı hesaplayıp topla. Emsal faiz oranını sen girersin '
          '(örneğin bankaların aynı tür kredide uyguladığı oran). KDV, BSMV, stopaj ve örtülü sermaye hükümlerinin ayrıntıları bu araçta hesaplanmaz.'),
    ]);
  }

  // ---------------------------------------------------------------- Şirket kuruluş maliyeti
  void _kmEkle() {
    final k = _Kalem();
    k.ad.addListener(() => setState(() {}));
    k.tutar.addListener(() => setState(() {}));
    setState(() => _kmKalemler.add(k));
  }

  void _kmSil(int i) {
    final k = _kmKalemler[i];
    setState(() => _kmKalemler.removeAt(i));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      k.ad.dispose();
      k.tutar.dispose();
    });
  }

  Widget _kurulus() {
    var resmi = 0.0;
    final satirlar = <_Satir>[('Şirket kuruluş maliyeti', '')];
    for (final k in _kmKalemler) {
      final t = _sayi(k.tutar.text);
      if (t != null && t > 0) {
        resmi += t;
        satirlar.add((k.ad.text.trim().isEmpty ? 'Kalem' : k.ad.text.trim(), tl(t)));
      }
    }
    final hizmet = _sayi(_kmHizmet.text) ?? 0;
    final kdvOran = _sayi(_kmKdv.text) ?? 0;
    Widget sonuc = const Text('Resmî gider tutarlarını gir.');
    if (resmi > 0 || hizmet > 0) {
      final kdv = kurus(hizmet * kdvOran / 100);
      satirlar.add(('>Resmî giderler toplamı', tl(kurus(resmi))));
      if (hizmet > 0) {
        satirlar.addAll([
          ('Hizmet bedeli (KDV hariç)', tl(hizmet)),
          ('KDV (%${_yz(kdvOran)})', tl(kdv)),
          ('Hizmet bedeli toplamı', tl(kurus(hizmet + kdv))),
        ]);
      }
      satirlar.add(('>Genel toplam (müşteriye teklif)', tl(kurus(resmi + hizmet + kdv))));
      sonuc = _sonuc(satirlar, 'kurulus_maliyeti', 'Şirket kuruluş maliyeti');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Resmî giderler', style: TextStyle(fontWeight: FontWeight.w700)),
      const Text('Harç ve ücret tutarlarını güncel tarifeden sen yaz; ad alanlarını da değiştirebilirsin.', style: TextStyle(fontSize: 12, color: Colors.black87)),
      const SizedBox(height: 6),
      for (var i = 0; i < _kmKalemler.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 280, child: TextField(controller: _kmKalemler[i].ad, decoration: const InputDecoration(labelText: 'Kalem', isDense: true))),
            SizedBox(width: 180, child: MaasAlani(controller: _kmKalemler[i].tutar, etiket: 'Tutar (TL)', ipucu: '0,00')),
            IconButton(tooltip: 'Kalemi sil', onPressed: () => _kmSil(i), icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _kmEkle, icon: const Icon(Icons.add), label: const Text('Kalem ekle'))),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 8, children: [
        SizedBox(width: 260, child: MaasAlani(controller: _kmHizmet, etiket: 'Müşavirlik hizmet bedeli, KDV hariç (TL)', ipucu: '0,00')),
        _oranAlani(_kmKdv, 'KDV oranı (%)', genislik: 140),
      ]),
      const SizedBox(height: 14),
      sonuc,
      _not('Tutarlar senin girdiğin değerlerdir; harç, ilan ve oda ücretleri her yıl ve her sicil müdürlüğünde değişebilir, güncel tarifeden kontrol et. Sermaye ve diğer şirket türü giderleri bu listede yok, kalem ekleyerek yaz.'),
    ]);
  }

  // ---------------------------------------------------------------- Personel ödemeleri
  /// Seçili ayın bordrosunun üstüne eklenen brüt tutarın yaklaşık net etkisi (SGK tavanı ve asgari ücret istisnası hesaba katılmaz).
  ({double sgk, double gv, double damga, double net}) _ekNet(YilParam p, AyBordro b, double ek) {
    final sgk = kurus(ek * (isciSgkOrani + isciIssizlikOrani));
    final gv = kurus(gelirVergisiTarife(p, b.kumMatrah + (ek - sgk)) - gelirVergisiTarife(p, b.kumMatrah));
    final damga = kurus(ek * damgaOrani);
    return (sgk: sgk, gv: gv, damga: damga, net: kurus(ek - sgk - gv - damga));
  }

  Widget _ppChips() => Wrap(spacing: 8, children: [
        for (final (i, m) in const ['Fazla mesai', 'Raporlu gün ödeneği', 'Yıllık izin ücreti', 'Zam simülasyonu'].indexed)
          ChoiceChip(label: Text(m), selected: _ppMod == i, onSelected: (_) => setState(() => _ppMod = i)),
      ]);

  Widget _personelOdeme() {
    if (_ppMod == 3) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_ppChips(), const SizedBox(height: 10), _zamSim()]);
    final p = bordroParam(_ppYil)!;
    final u = _sayi(_ppMaas.text);
    Widget sonuc = const Text('Maaşı gir.');
    if (u != null && u > 0) {
      final liste = yillikBordro(p, BordroGirdi(ucret: u, net: _ppNet, asgari: false, giris: DateTime(_ppYil, 1, 1)), _ppAy);
      final b = liste.last;
      final donem = '${bordroAylar[_ppAy - 1]} $_ppYil';
      final gunluk = kurus(b.brut / 30);
      final satirlar = <_Satir>[];
      String ad = 'personel_odeme', baslik = 'Personel ödemesi';
      if (_ppMod == 0) {
        final saat = _sayi(_fmSaat.text) ?? 0, bolen = _sayi(_fmBolen.text) ?? 225, zam = _sayi(_fmZam.text) ?? 50;
        final htGun = _sayi(_fmHt.text) ?? 0, htK = _sayi(_fmHtK.text) ?? 1.5, gtGun = _sayi(_fmGt.text) ?? 0, gtK = _sayi(_fmGtK.text) ?? 1;
        final saatlik = bolen > 0 ? b.brut / bolen : 0.0;
        final fm = kurus(saat * saatlik * (1 + zam / 100));
        final ht = kurus(htGun * gunluk * htK);
        final gt = kurus(gtGun * gunluk * gtK);
        final ek = kurus(fm + ht + gt);
        if (ek > 0) {
          final n = _ekNet(p, b, ek);
          satirlar.addAll([
            ('Fazla mesai ve tatil çalışması ($donem)', ''),
            ('Aylık brüt maaş', tl(b.brut)),
            ('Günlük brüt ücret (maaş / 30)', tl(gunluk)),
            ('Saatlik brüt ücret (maaş / ${_yz(bolen)})', tl(kurus(saatlik))),
            if (fm > 0) ('Fazla mesai: ${_yz(saat)} saat x %${_yz(zam)} zamlı', tl(fm)),
            if (ht > 0) ('Hafta tatili çalışması: ${_yz(htGun)} gün x ${_yz(htK)} günlük', tl(ht)),
            if (gt > 0) ('Genel tatil çalışması: ${_yz(gtGun)} gün x ${_yz(gtK)} günlük', tl(gt)),
            ('>Ek brüt ödeme', tl(ek)),
            ('SGK + işsizlik işçi payı', '-${tl(n.sgk)}'),
            ('Gelir vergisi (kümülatif matrahın üstüne)', '-${tl(n.gv)}'),
            ('Damga vergisi', '-${tl(n.damga)}'),
            ('>Ek net ödeme (yaklaşık)', tl(n.net)),
            ('Ayın toplam brütü', tl(kurus(b.brut + ek))),
          ]);
          ad = 'fazla_mesai';
          baslik = 'Fazla mesai hesabı';
        }
      } else if (_ppMod == 1) {
        final gun = (_sayi(_rpGun.text) ?? 0).clamp(0, 30).toInt();
        final oran = _sayi(_rpOran.text) ?? 0, bekleme = (_sayi(_rpBekleme.text) ?? 0).toInt();
        if (gun > 0) {
          final g2 = liste.length == _ppAy ? yillikBordro(p, BordroGirdi(ucret: u, net: _ppNet, asgari: false, giris: DateTime(_ppYil, 1, 1)), _ppAy, gelmedi: {_ppAy: gun}).last : b;
          final odenir = gun > bekleme ? gun - bekleme : 0;
          final odenek = kurus(gunluk * oran / 100 * odenir);
          satirlar.addAll([
            ('$_rpTur: $gun gün raporlu ($donem)', ''),
            ('Aylık brüt maaş', tl(b.brut)),
            ('Günlük brüt kazanç (maaş / 30)', tl(gunluk)),
            ('Maaştan düşülen gün', '$gun gün = ${tl(kurus(gunluk * gun))}'),
            ('Bordro: ücret ödenen gün', '${g2.gun} / 30'),
            ('Bordro net maaşı (raporlu günler düşülmüş)', tl(g2.net)),
            ('SGK ödeneği (%${_yz(oran)}, ${odenir} gün ödenir, $bekleme gün bekleme)', tl(odenek)),
            ('>Çalışanın toplam eline geçen (net maaş + ödenek)', tl(kurus(g2.net + odenek))),
            ('Normal aylık net maaşa göre fark', tl(kurus(g2.net + odenek - b.net))),
          ]);
          ad = 'raporlu_gun_odenegi';
          baslik = 'Raporlu gün ve ödenek hesabı';
        }
      } else {
        final gun = _sayi(_izGun.text) ?? 0;
        final ek = kurus(gunluk * gun);
        if (ek > 0) {
          final n = _ekNet(p, b, ek);
          satirlar.addAll([
            ('Kullanılmayan yıllık izin ücreti ($donem)', ''),
            ('Aylık brüt maaş', tl(b.brut)),
            ('Günlük brüt ücret (maaş / 30)', tl(gunluk)),
            ('İzin günü', _yz(gun)),
            ('>Brüt izin ücreti', tl(ek)),
            ('SGK + işsizlik işçi payı', '-${tl(n.sgk)}'),
            ('Gelir vergisi (kümülatif matrahın üstüne)', '-${tl(n.gv)}'),
            ('Damga vergisi', '-${tl(n.damga)}'),
            ('>Net izin ücreti (yaklaşık)', tl(n.net)),
          ]);
          ad = 'yillik_izin_ucreti';
          baslik = 'Yıllık izin ücreti hesabı';
        }
      }
      if (satirlar.isNotEmpty) sonuc = _sonuc(satirlar, ad, baslik);
      else sonuc = const Text('Hesap için gerekli sayıları gir.');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ppChips(),
      const SizedBox(height: 10),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Maaş net')), ButtonSegment(value: false, label: Text('Maaş brüt'))],
        selected: {_ppNet},
        onSelectionChanged: (v) => setState(() => _ppNet = v.first),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 260, child: MaasAlani(controller: _ppMaas, etiket: _ppNet ? 'Aylık net maaş (TL)' : 'Aylık brüt maaş (TL)', ipucu: '0,00')),
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<int>(
            initialValue: _ppYil,
            decoration: const InputDecoration(labelText: 'Yıl', isDense: true),
            items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (v) => setState(() => _ppYil = v ?? _ppYil),
          ),
        ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<int>(
            initialValue: _ppAy,
            decoration: const InputDecoration(labelText: 'Ay', isDense: true),
            items: [for (var a = 1; a <= 12; a++) DropdownMenuItem(value: a, child: Text(bordroAylar[a - 1]))],
            onChanged: (v) => setState(() => _ppAy = v ?? _ppAy),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (_ppMod == 0)
        Wrap(spacing: 10, runSpacing: 8, children: [
          _oranAlani(_fmSaat, 'Fazla mesai saati (ay)', genislik: 190),
          _oranAlani(_fmZam, 'Fazla mesai zammı (%)', genislik: 190),
          _oranAlani(_fmBolen, 'Saatlik ücret böleni', genislik: 190),
          _oranAlani(_fmHt, 'Hafta tatilinde çalışılan gün', genislik: 190),
          _oranAlani(_fmHtK, 'Hafta tatili katsayısı (günlük x)', genislik: 190),
          _oranAlani(_fmGt, 'Genel tatilde çalışılan gün', genislik: 190),
          _oranAlani(_fmGtK, 'Genel tatil katsayısı (günlük x)', genislik: 190),
        ])
      else if (_ppMod == 1) ...[
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in _rpTurleri.entries)
            ChoiceChip(
              label: Text(e.key),
              selected: _rpTur == e.key,
              onSelected: (_) => setState(() {
                _rpTur = e.key;
                _rpOran.text = e.value.$1;
                _rpBekleme.text = e.value.$2;
              }),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          _oranAlani(_rpGun, 'Bu ay raporlu / izinli gün (en çok 30)', genislik: 260),
          _oranAlani(_rpOran, 'Ödenek oranı (günlük kazancın %)', genislik: 230),
          _oranAlani(_rpBekleme, 'Ödenmeyen bekleme günü', genislik: 190),
        ]),
      ] else
        _oranAlani(_izGun, 'Kullanılmayan yıllık izin günü', genislik: 260),
      const SizedBox(height: 14),
      sonuc,
      _not(_ppMod == 0
          ? 'Saatlik ücret = aylık brüt / böleni (haftada 45 saat için 225). Fazla mesai varsayılan %50 zamlıdır. Hafta tatilinde ve genel tatilde çalışma karşılığı için katsayıları iş sözleşmenize ve güncel mevzuata göre kontrol et. '
              'Net etki yaklaşık hesaplanır: SGK tavanı ve asgari ücret istisnası dikkate alınmaz, kesin tutar için bordroya gir.'
          : _ppMod == 1
              ? 'Ödenek oranları ve bekleme günü seçilen türe göre önceden dolu gelir, güncel SGK uygulamasına göre kontrol et. Ödenek brüt kabul edilip kesintisiz eklenir. Doğum izni gibi 30 günü aşan süreleri aylara bölerek hesapla; ödenek günlük kazanç olarak maaş / 30 alınır, SGK\'nın gerçek günlük kazancı farklı olabilir.'
              : 'İzin ücreti günlük brüt ücret (maaş / 30) x kullanılmayan gün olarak alınır. Net etki yaklaşık hesaplanır: SGK tavanı ve asgari ücret istisnası dikkate alınmaz.'),
    ]);
  }

  // ---------------------------------------------------------------- Zam simülasyonu
  Widget _zamSim() {
    final p = bordroParam(_zmYil)!;
    final u = _sayi(_zmMaas.text), d = _sayi(_zmDeger.text);
    Widget sonuc = const Text('Mevcut maaşı ve zamı gir.');
    if (u != null && u > 0 && d != null && d > 0) {
      final yeniU = _zmYuzde ? kurus(u * (1 + d / 100)) : d;
      List<AyBordro> yap(double x) => yillikBordro(p, BordroGirdi(ucret: x, net: _zmNet, asgari: false, giris: DateTime(_zmYil, 1, 1)), 12);
      final e = yap(u), y = yap(yeniU);
      double top(List<AyBordro> l, double Function(AyBordro) f) => kurus(l.fold(0.0, (a, b) => a + f(b)));
      final netE = top(e, (b) => b.net), netY = top(y, (b) => b.net);
      final malE = top(e, (b) => b.maliyet), malY = top(y, (b) => b.maliyet);
      final dNet = kurus(netY - netE), dMal = kurus(malY - malE);
      final oran = dNet > 0 ? kurus(dMal / dNet * 100) / 100 : 0.0;
      String ok(double a, double b) => '${tl(a)} → ${tl(b)}';
      sonuc = _sonuc([
        ('$_zmYil zam simülasyonu (yıl başından uygulanmış gibi)', ''),
        ('${_zmNet ? 'Net' : 'Brüt'} maaş', ok(u, yeniU)),
        ('Ocak brüt', ok(e.first.brut, y.first.brut)),
        ('Ocak net', ok(e.first.net, y.first.net)),
        ('Aralık net (dilim etkisi dahil)', ok(e.last.net, y.last.net)),
        ('Yıllık toplam net', ok(netE, netY)),
        ('Yıllık işveren maliyeti', ok(malE, malY)),
        ('>Yıllık ek işveren maliyeti', tl(dMal)),
        ('>Çalışanın yıllık net kazancı', tl(dNet)),
        ('1 TL net artış işverene', '${oran.toStringAsFixed(2).replaceAll('.', ',')} TL'),
      ], 'zam_simulasyonu_$_zmYil', 'Zam simülasyonu $_zmYil');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Maaş net')), ButtonSegment(value: false, label: Text('Maaş brüt'))],
        selected: {_zmNet},
        onSelectionChanged: (v) => setState(() => _zmNet = v.first),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<int>(
          initialValue: _zmYil,
          decoration: const InputDecoration(labelText: 'Yıl', isDense: true),
          items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _zmYil = v ?? _zmYil),
        ),
      ),
      const SizedBox(height: 10),
      MaasAlani(controller: _zmMaas, etiket: _zmNet ? 'Mevcut net maaş (TL)' : 'Mevcut brüt maaş (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Zam yüzdesi')), ButtonSegment(value: false, label: Text('Yeni maaş tutarı'))],
        selected: {_zmYuzde},
        onSelectionChanged: (v) => setState(() {
          _zmYuzde = v.first;
          _zmDeger.clear();
        }),
      ),
      const SizedBox(height: 10),
      _zmYuzde ? _oranAlani(_zmDeger, 'Zam oranı (%)') : MaasAlani(controller: _zmDeger, etiket: 'Yeni maaş (TL)', ipucu: '0,00'),
      const SizedBox(height: 14),
      sonuc,
      _not('Her iki maaş da yıl başından çalışıyormuş gibi bordro motoruyla hesaplanır (kümülatif matrah, asgari ücret istisnası, varsayılan işveren SGK indirimi). '
          'Yıl ortasında verilen zamda toplamlar daha düşük çıkar; dilim etkisini ve 1 TL net artışın işverene maliyetini görmek için kullan.'),
    ]);
  }

  // ---------------------------------------------------------------- Stopaj
  Widget _stopaj() {
    final t = _sayi(_stTutar.text), o = _sayi(_stOran.text);
    Widget sonuc = const Text('Tutarı ve oranı gir.');
    if (t != null && t > 0 && o != null && o >= 0 && o < 100) {
      final r = o / 100;
      final brut = _stNetten ? kurus(t / (1 - r)) : t;
      final st = kurus(brut * r);
      final net = _stNetten ? t : kurus(brut - st);
      sonuc = _sonuc([
        (_stNetten ? 'Netten brüte (stopaj dahil edilir)' : 'Brütten nete', ''),
        ('Brüt tutar', tl(brut)),
        ('Stopaj (%${_yz(o)})', tl(st)),
        ('>Net ödenecek', tl(net)),
      ], 'stopaj', 'Stopaj hesabı');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: false, label: Text('Brütten nete')), ButtonSegment(value: true, label: Text('Netten brüte'))],
        selected: {_stNetten},
        onSelectionChanged: (v) => setState(() => _stNetten = v.first),
      ),
      const SizedBox(height: 12),
      MaasAlani(controller: _stTutar, etiket: _stNetten ? 'Net tutar (TL)' : 'Brüt tutar (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      _oranAlani(_stOran, 'Stopaj oranı (%)'),
      const SizedBox(height: 14),
      sonuc,
      _not('Oranı kendin gir: serbest meslek ve işyeri kirası gibi ödemelerde oran farklıdır, güncel oranı kontrol et. KDV bu hesaba dahil değildir.'),
    ]);
  }

  // ---------------------------------------------------------------- Serbest meslek makbuzu
  Widget _smm() {
    final t = _sayi(_smTutar.text), k = _sayi(_smKdv.text), s = _sayi(_smStopaj.text);
    Widget sonuc = const Text('Tutarı gir.');
    if (t != null && t > 0 && k != null && k >= 0 && s != null && s >= 0 && 1 + k / 100 - s / 100 > 0) {
      final kr = k / 100, sr = s / 100;
      final brut = _smNet ? kurus(t / (1 + kr - sr)) : t;
      final kdv = kurus(brut * kr);
      final st = kurus(brut * sr);
      final tahsil = kurus(brut + kdv - st);
      sonuc = _sonuc([
        (_smNet ? 'Tahsil edilecek nete göre makbuz' : 'Brüt ücrete göre makbuz', ''),
        ('Brüt ücret (KDV hariç)', tl(brut)),
        ('KDV (%${_yz(k)})', tl(kdv)),
        ('Toplam (KDV dahil)', tl(kurus(brut + kdv))),
        ('Stopaj (%${_yz(s)})', tl(st)),
        ('>Tahsil edilecek net', tl(tahsil)),
        ('Beyan', ''),
        ('Hasılat (gelir)', tl(brut)),
        ('Hesaplanan KDV', tl(kdv)),
        ('Mahsup edilecek stopaj', tl(st)),
      ], 'serbest_meslek_makbuzu', 'Serbest meslek makbuzu hesabı');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: false, label: Text('Brüt ücret belli')), ButtonSegment(value: true, label: Text('Eline geçecek net belli'))],
        selected: {_smNet},
        onSelectionChanged: (v) => setState(() => _smNet = v.first),
      ),
      const SizedBox(height: 12),
      MaasAlani(controller: _smTutar, etiket: _smNet ? 'Tahsil edilecek net (TL)' : 'Brüt ücret, KDV hariç (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 8, children: [_oranAlani(_smKdv, 'KDV oranı (%)'), _oranAlani(_smStopaj, 'Stopaj oranı (%)')]),
      const SizedBox(height: 14),
      sonuc,
      _not('Stopaj brüt ücret üzerinden, KDV brüt ücret üzerinden hesaplanır. Stopaj kesilmeyecekse oranı 0 yaz. KDV tevkifatı varsa KDV sekmesindeki tevkifat hesabını kullan.'),
    ]);
  }

  // ---------------------------------------------------------------- Kira vergisi
  Widget _kira() {
    final p = bordroParam(_kiYil)!;
    final gelir = _sayi(_kiGelir.text);
    Widget sonuc = const Text('Yıllık brüt kira gelirini gir.');
    if (gelir != null && gelir > 0) {
      final istisna = _kiKonut ? (_sayi(_kiIstisna.text) ?? 0) : 0.0;
      final gerceklesen = _sayi(_kiGider.text) ?? 0;
      final asan = gelir > istisna ? gelir - istisna : 0.0;
      final gider = _kiGotur ? kurus(asan * 0.15) : kurus(gerceklesen * asan / gelir);
      final matrah = asan - gider;
      final vergi = kurus(gelirVergisiTarife(p, matrah));
      final mahsup = _sayi(_kiMahsup.text) ?? 0;
      final fark = kurus(vergi - mahsup);
      sonuc = _sonuc([
        ('$_kiYil kira geliri vergisi', ''),
        ('Yıllık brüt kira', tl(gelir)),
        if (istisna > 0) ('Konut kira istisnası', '-${tl(istisna > gelir ? gelir : istisna)}'),
        ('İstisnayı aşan kira', tl(asan)),
        (_kiGotur ? 'Götürü gider (%15)' : 'Gider (istisnaya isabet eden kısım hariç)', '-${tl(gider)}'),
        ('Vergi matrahı', tl(matrah)),
        ('Hesaplanan gelir vergisi', tl(vergi)),
        if (mahsup > 0) ('Mahsup edilen stopaj', '-${tl(mahsup)}'),
        (fark >= 0 ? '>Ödenecek gelir vergisi' : '>Mahsuptan kalan (iade/sonraki mahsup)', tl(fark.abs())),
      ], 'kira_vergisi_$_kiYil', 'Kira geliri vergisi $_kiYil');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<int>(
          initialValue: _kiYil,
          decoration: const InputDecoration(labelText: 'Yıl (tarife)', isDense: true),
          items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _kiYil = v ?? _kiYil),
        ),
      ),
      const SizedBox(height: 10),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: true, label: Text('Götürü gider (%15)')), ButtonSegment(value: false, label: Text('Gerçek gider'))],
        selected: {_kiGotur},
        onSelectionChanged: (v) => setState(() => _kiGotur = v.first),
      ),
      const SizedBox(height: 10),
      MaasAlani(controller: _kiGelir, etiket: 'Yıllık brüt kira geliri (TL)', ipucu: '0,00'),
      if (!_kiGotur) ...[
        const SizedBox(height: 10),
        MaasAlani(controller: _kiGider, etiket: 'Belgeli gerçek giderler toplamı (TL)', ipucu: '0,00'),
      ],
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _kiKonut,
        onChanged: (v) => setState(() => _kiKonut = v ?? true),
        title: const Text('Konut kirası: istisna uygula'),
      ),
      if (_kiKonut) MaasAlani(controller: _kiIstisna, etiket: 'Yıl için konut kira istisnası tutarı (TL, güncel tutarı gir)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _kiMahsup, etiket: 'Kesilmiş stopaj (TL, varsa)', ipucu: '0,00'),
      const SizedBox(height: 14),
      sonuc,
      _not('Tek kaynaktan kira geliri varsayılır; başka gelirler matraha eklenmez. İstisna tutarını her yıl güncel duyurudan gir. '
          'Götürü gider, istisnayı aşan tutar üzerinden; gerçek giderde istisnaya isabet eden gider düşülmez. Beyan sınırı ve diğer gelirlerle birleşme için ayrıca kontrol et.'),
    ]);
  }





  // ---------------------------------------------------------------- Şirket türü karşılaştırma
  Widget _sirketKarsilastir() {
    final p = bordroParam(_scYil);
    final kar = _sayi(_scKar.text), kv = _sayi(_scKv.text), stopaj = _sayi(_scStopaj.text);
    final dagit = ((_sayi(_scDagit.text) ?? 100).clamp(0, 100)) / 100;
    double v(TextEditingController c) => _sayi(c.text) ?? 0;
    Widget sonuc = const Text('Yıllık vergi öncesi kârı, kurumlar vergisi ve kâr payı stopaj oranını gir.');
    if (p == null) {
      sonuc = Text('$_scYil için gelir vergisi tarifesi tanımlı değil (Parametreler bölümünden girilir).');
    } else if (kar != null && kar > 0 && kv != null && stopaj != null) {
      // Şahıs işletmesi
      final primS = v(_scPrimSahis), ekS = v(_scEkSahis);
      final matrahS = (kar - ekS - (_scPrimIndir ? primS : 0)).clamp(0, double.infinity).toDouble();
      final gvS = kurus(gelirVergisiTarife(p, matrahS));
      final yukS = kurus(gvS + primS + ekS);
      final netS = kurus(kar - yukS);

      // Sermaye şirketi (limited veya anonim)
      ({double kv, double stopaj, double prim, double ek, double yuk, double ortakNet, double sirketteKalan}) sirket(double prim, double ek) {
        final sk = (kar - ek).clamp(0, double.infinity).toDouble();
        final kvT = kurus(sk * kv / 100);
        final net = kurus(sk - kvT);
        final dag = kurus(net * dagit);
        final st = kurus(dag * stopaj / 100);
        return (kv: kvT, stopaj: st, prim: prim, ek: ek, yuk: kurus(kvT + st + prim + ek), ortakNet: kurus(dag - st - prim), sirketteKalan: kurus(net - dag));
      }

      final l = sirket(v(_scPrimLtd), v(_scEkLtd));
      final a = sirket(v(_scPrimAs), v(_scEkAs));
      String yuzde(double yuk) => '%${_yz(kurus(yuk / kar * 100))}';
      sonuc = _sonuc([
        ('Şirket türü karşılaştırması ($_scYil)', ''),
        ('Yıllık vergi öncesi kâr', tl(kar)),
        ('Şahıs işletmesi', ''),
        ('Gelir vergisi matrahı', tl(matrahS)),
        ('Gelir vergisi', tl(gvS)),
        ('SGK / Bağ-Kur primi', tl(primS)),
        if (ekS > 0) ('Ek yıllık maliyet', tl(ekS)),
        ('>Toplam yük (şahıs)', '${tl(yukS)}  (${yuzde(yukS)})'),
        ('Net kalan (şahıs)', tl(netS)),
        ('Limited şirket', ''),
        ('Kurumlar vergisi', tl(l.kv)),
        ('Kâr payı stopajı', tl(l.stopaj)),
        ('Ortağın SGK / Bağ-Kur primi', tl(l.prim)),
        if (l.ek > 0) ('Ek yıllık maliyet (muhasebe, kuruluş vb.)', tl(l.ek)),
        ('>Toplam yük (limited)', '${tl(l.yuk)}  (${yuzde(l.yuk)})'),
        ('Ortağın eline geçen net', tl(l.ortakNet)),
        if (l.sirketteKalan > 0) ('Şirkette kalan kâr', tl(l.sirketteKalan)),
        ('Anonim şirket', ''),
        ('Kurumlar vergisi', tl(a.kv)),
        ('Kâr payı stopajı', tl(a.stopaj)),
        ('Ortağın SGK / Bağ-Kur primi', tl(a.prim)),
        if (a.ek > 0) ('Ek yıllık maliyet (muhasebe, kuruluş vb.)', tl(a.ek)),
        ('>Toplam yük (anonim)', '${tl(a.yuk)}  (${yuzde(a.yuk)})'),
        ('Ortağın eline geçen net', tl(a.ortakNet)),
        if (a.sirketteKalan > 0) ('Şirkette kalan kâr', tl(a.sirketteKalan)),
      ], 'sirket_turu_karsilastirma_$_scYil', 'Şirket türü karşılaştırması $_scYil');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<int>(
          initialValue: _scYil,
          decoration: const InputDecoration(labelText: 'Yıl (gelir vergisi tarifesi)', isDense: true),
          items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _scYil = v ?? _scYil),
        ),
      ),
      const SizedBox(height: 10),
      MaasAlani(controller: _scKar, etiket: 'Yıllık vergi öncesi kâr (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_scKv, 'Kurumlar vergisi oranı (%, güncel oranı gir)', genislik: 340),
        _oranAlani(_scStopaj, 'Kâr payı stopaj oranı (%, güncel oranı gir)', genislik: 340),
        _oranAlani(_scDagit, 'Net kârın dağıtılan kısmı (%)', genislik: 260),
      ]),
      const SizedBox(height: 10),
      const Text('Yıllık SGK / Bağ-Kur primi (kişinin kendi cebinden, TL)', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_scPrimSahis, 'Şahıs işletmesi', genislik: 200),
        _oranAlani(_scPrimLtd, 'Limited ortak', genislik: 200),
        _oranAlani(_scPrimAs, 'Anonim ortak', genislik: 200),
      ]),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _scPrimIndir,
        onChanged: (v) => setState(() => _scPrimIndir = v ?? true),
        title: const Text('Şahıs işletmesinde primi gelir vergisi matrahından indir'),
      ),
      const Text('Ek yıllık maliyet (muhasebe, kuruluş, harç, vb., TL)', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_scEkSahis, 'Şahıs işletmesi', genislik: 200),
        _oranAlani(_scEkLtd, 'Limited şirket', genislik: 200),
        _oranAlani(_scEkAs, 'Anonim şirket', genislik: 200),
      ]),
      const SizedBox(height: 14),
      sonuc,
      _not('Aynı kâr tutarında üç şirket türünün vergi, prim ve ek maliyet yükünü kıyaslayan ön hesap. Kurumlar vergisi ve stopaj oranlarını, prim tutarlarını ve ek maliyetleri '
          'güncel mevzuattan ve teklifinizden kendin gir; sabit yazılmadı. Limited ve anonim şirketin vergi hesabı aynıdır, farkı yalnızca girdiğin prim ve ek maliyet yaratır. '
          'Ortağa ödenen maaş, istisnalar, indirimler, KDV, sermaye ve yönetim kurulu yükümlülükleri ile kuruluş sonrası işlemler hesaba katılmaz. Karar için ayrıca danışmanlık yapılmalıdır.'),
    ]);
  }

  // ---------------------------------------------------------------- Vergi ceza hesaplayıcı
  int _vcAy(DateTime vade, DateTime odeme) {
    final v = DateTime(vade.year, vade.month, vade.day), o = DateTime(odeme.year, odeme.month, odeme.day);
    if (!o.isAfter(v)) return 0;
    var m = (o.year - v.year) * 12 + o.month - v.month;
    if (o.day > v.day) m++;
    return m < 1 ? 1 : m;
  }

  Widget _vergiCeza() {
    final vergi = _sayi(_vcVergi.text), oran = _sayi(_vcOran.text), kat = _sayi(_vcKat.text) ?? 0;
    final usul = _sayi(_vcUsul.text) ?? 0, ozel = _sayi(_vcOzel.text) ?? 0, indirim = _sayi(_vcIndirim.text);
    Widget sonuc = const Text('Vergi aslını ve aylık oranı gir.');
    if (vergi != null && vergi > 0 && oran != null && oran >= 0) {
      final ay = _vcAy(_vcVade, _vcOdeme);
      final zam = kurus(vergi * oran / 100 * ay);
      final ziyaCeza = kurus(vergi * kat);
      final sabitCeza = kurus(usul + ozel);
      final satirlar = <_Satir>[
        ('Vergi cezası senaryoları', ''),
        ('Vergi aslı', tl(vergi)),
        ('Vade - ödeme', '${_tr(_vcVade)} - ${_tr(_vcOdeme)} ($ay ay)'),
        ('Aylık oran', '%${_yz(oran)}'),
        ('1) Resen veya inceleme sonucu tarhiyat (cezalı)', ''),
        ('Vergi ziyaı cezası (${_yz(kat)} kat)', tl(ziyaCeza)),
        if (sabitCeza > 0) ('Usulsüzlük ve özel usulsüzlük cezaları', tl(sabitCeza)),
        ('Gecikme faizi/zammı', tl(zam)),
        ('>Toplam yük (1)', tl(kurus(vergi + ziyaCeza + sabitCeza + zam))),
        ('2) Pişmanlıkla beyan (şartlar sağlanırsa vergi ziyaı cezası uygulanmaz)', ''),
        if (sabitCeza > 0) ('Usulsüzlük ve özel usulsüzlük cezaları (şartlara göre)', tl(sabitCeza)),
        ('Pişmanlık zammı', tl(zam)),
        ('>Toplam yük (2)', tl(kurus(vergi + sabitCeza + zam))),
        if (indirim != null && indirim > 0 && indirim <= 100) ...[
          ('3) İndirimli ödeme / uzlaşma (cezada %${_yz(indirim)} indirim)', ''),
          ('İndirimli vergi ziyaı cezası', tl(kurus(ziyaCeza * (1 - indirim / 100)))),
          if (sabitCeza > 0) ('Usulsüzlük cezaları (indirimli)', tl(kurus(sabitCeza * (1 - indirim / 100)))),
          ('Gecikme faizi/zammı', tl(zam)),
          ('>Toplam yük (3)', tl(kurus(vergi + (ziyaCeza + sabitCeza) * (1 - indirim / 100) + zam))),
        ],
      ];
      sonuc = _sonuc(satirlar, 'vergi_ceza_senaryolari', 'Vergi ceza senaryoları');
    }
    Widget tarih(String e, DateTime d, void Function(DateTime) ata) => OutlinedButton.icon(
          onPressed: () async {
            final x = await showDatePicker(context: context, initialDate: d, firstDate: DateTime(2015), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
            if (x != null) setState(() => ata(x));
          },
          icon: const Icon(Icons.event, size: 18),
          label: Text('$e: ${_tr(d)}'),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MaasAlani(controller: _vcVergi, etiket: 'Eksik veya geç ödenen vergi aslı (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        tarih('Vade', _vcVade, (x) => _vcVade = x),
        tarih('Ödeme', _vcOdeme, (x) => _vcOdeme = x),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_vcOran, 'Aylık zam/faiz oranı (%, güncel oranı gir)', genislik: 320),
        _oranAlani(_vcKat, 'Vergi ziyaı cezası katı (mevzuattan doğrula)', genislik: 320),
      ]),
      const SizedBox(height: 10),
      MaasAlani(controller: _vcUsul, etiket: 'Usulsüzlük cezası tutarı (TL, varsa)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _vcOzel, etiket: 'Özel usulsüzlük cezası tutarı (TL, varsa)', ipucu: '0,00'),
      const SizedBox(height: 10),
      _oranAlani(_vcIndirim, 'İndirim oranı (%, uzlaşma/indirimli ödeme, isteğe bağlı)', genislik: 420),
      const SizedBox(height: 14),
      sonuc,
      _not('Üç senaryoyu karşılaştırmak için ön hesaptır. Ceza kat sayısı, pişmanlık ve indirimli ödeme şartları, usulsüzlük ceza tutarları ve indirim oranları '
          'olaya, döneme ve verginin türüne göre değişir; bu değerleri güncel mevzuattan kontrol edip kendin gir. Kaçakçılık cezaları ve ceza alt sınırları '
          'hesaplanmaz. Tarhiyat sonrası faiz ile pişmanlık zammında aynı aylık oranın uygulandığı varsayılmıştır; gerçek oranları ayrıca kontrol et.'),
    ]);
  }

  // ---------------------------------------------------------------- Tapu harcı ve alım-satım maliyeti
  Widget _tapuMaliyet() {
    final bedel = _sayi(_tpBedel.text);
    Widget sonuc = const Text('Satış bedelini gir.');
    if (bedel != null && bedel > 0) {
      final deger = _sayi(_tpDeger.text) ?? bedel;
      double oran(TextEditingController c) => (_sayi(c.text) ?? 0) / 100;
      final harcA = kurus(deger * oran(_tpHarcA)), harcS = kurus(deger * oran(_tpHarcS));
      final damga = kurus(deger * oran(_tpDamga));
      final damgaA = _tpDamgaTaraf == 0 ? damga : (_tpDamgaTaraf == 1 ? 0.0 : kurus(damga / 2));
      final damgaS = kurus(damga - damgaA);
      final kdv = oran(_tpKdv);
      final komA = kurus(bedel * oran(_tpKomA)), komS = kurus(bedel * oran(_tpKomS));
      final komKdvA = kurus(komA * kdv), komKdvS = kurus(komS * kdv);
      final digA = _sayi(_tpDigA.text) ?? 0, digS = _sayi(_tpDigS.text) ?? 0;
      final masrafA = kurus(harcA + damgaA + komA + komKdvA + digA);
      final masrafS = kurus(harcS + damgaS + komS + komKdvS + digS);
      sonuc = _sonuc([
        ('Alım-satım maliyeti', ''),
        ('Satış bedeli', tl(bedel)),
        if (deger != bedel) ('Harç ve damga matrahı (tapuda beyan edilen)', tl(deger)),
        ('Alıcı masrafları', ''),
        if (harcA > 0) ('Tapu harcı (alıcı)', tl(harcA)),
        if (damgaA > 0) ('Damga vergisi (alıcı payı)', tl(damgaA)),
        if (komA > 0) ('Komisyon (alıcı)', tl(komA)),
        if (komKdvA > 0) ('Komisyon KDV (alıcı)', tl(komKdvA)),
        if (digA > 0) ('Diğer masraflar (alıcı)', tl(digA)),
        ('Alıcı toplam masrafı', tl(masrafA)),
        ('>Alıcının toplam maliyeti', tl(kurus(bedel + masrafA))),
        ('Satıcı masrafları', ''),
        if (harcS > 0) ('Tapu harcı (satıcı)', tl(harcS)),
        if (damgaS > 0) ('Damga vergisi (satıcı payı)', tl(damgaS)),
        if (komS > 0) ('Komisyon (satıcı)', tl(komS)),
        if (komKdvS > 0) ('Komisyon KDV (satıcı)', tl(komKdvS)),
        if (digS > 0) ('Diğer masraflar (satıcı)', tl(digS)),
        ('Satıcı toplam masrafı', tl(masrafS)),
        ('>Satıcının eline geçen (vergi öncesi)', tl(kurus(bedel - masrafS))),
      ], 'tapu_maliyet', 'Tapu harcı ve alım-satım maliyeti');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MaasAlani(controller: _tpBedel, etiket: 'Satış bedeli (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _tpDeger, etiket: 'Tapuda beyan edilen değer (TL, boşsa satış bedeli)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_tpHarcA, 'Tapu harcı oranı alıcı (%, güncel oranı gir)', genislik: 330),
        _oranAlani(_tpHarcS, 'Tapu harcı oranı satıcı (%, güncel oranı gir)', genislik: 330),
        _oranAlani(_tpDamga, 'Damga vergisi oranı (%, güncel oranı gir)', genislik: 330),
      ]),
      const SizedBox(height: 10),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: 0, label: Text('Damga: alıcı')), ButtonSegment(value: 1, label: Text('Damga: satıcı')), ButtonSegment(value: 2, label: Text('Damga: yarı yarıya'))],
        selected: {_tpDamgaTaraf},
        onSelectionChanged: (v) => setState(() => _tpDamgaTaraf = v.first),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_tpKomA, 'Alıcı komisyonu (% , satış bedeli üzerinden)', genislik: 330),
        _oranAlani(_tpKomS, 'Satıcı komisyonu (%, satış bedeli üzerinden)', genislik: 330),
        _oranAlani(_tpKdv, 'Komisyon KDV oranı (%)', genislik: 200),
      ]),
      const SizedBox(height: 10),
      MaasAlani(controller: _tpDigA, etiket: 'Alıcı diğer masrafları (TL: DASK, ekspertiz, döner sermaye vb.)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _tpDigS, etiket: 'Satıcı diğer masrafları (TL)', ipucu: '0,00'),
      const SizedBox(height: 14),
      sonuc,
      _not('Harç, damga vergisi ve komisyon oranları işlem türüne ve döneme göre değişir; tutarlar bu araçta sabit yazılmadı, güncel tarife ve sözleşmeden kendin gir. '
          'Satıcının değer artış kazancı vergisi bu hesaba dahil değildir, "Değer artış kazancı" aracında ayrıca hesaplanır. Kredi masrafları ve ipotek bedeli eklenmez.'),
    ]);
  }

  // ---------------------------------------------------------------- Değer artış kazancı
  Widget _degerArtis() {
    final p = bordroParam(_daYil);
    final alis = _sayi(_daAlis.text), satis = _sayi(_daSatis.text);
    final masraf = _sayi(_daMasraf.text) ?? 0;
    final eA = _sayi(_daEndA.text), eS = _sayi(_daEndS.text);
    final esik = _sayi(_daEsik.text), sure = _sayi(_daSure.text);
    final istisna = _sayi(_daIstisna.text) ?? 0, diger = _sayi(_daDiger.text) ?? 0;
    Widget sonuc = const Text('Alış ve satış bedelini gir.');
    if (p == null) {
      sonuc = Text('$_daYil için gelir vergisi tarifesi tanımlı değil (Parametreler bölümünden girilir).');
    } else if (alis != null && alis > 0 && satis != null && satis > 0) {
      final ay = (_daSatisT.year - _daAlisT.year) * 12 + _daSatisT.month - _daAlisT.month - (_daSatisT.day < _daAlisT.day ? 1 : 0);
      final sureYil = ay ~/ 12, sureKalanAy = ay % 12;
      final muaf = sure != null && sure > 0 && ay >= sure * 12;
      var endAlis = alis;
      var endNot = 'Endeks girilmedi, alış bedeli endekslenmedi';
      if (eA != null && eA > 0 && eS != null && eS > 0) {
        final artis = (eS / eA - 1) * 100;
        if (esik != null && artis >= esik) {
          endAlis = kurus(alis * eS / eA);
          endNot = 'Endeks artışı %${_yz(kurus(artis))}, eşik (%${_yz(esik)}) aşıldı: alış bedeli endekslendi';
        } else {
          endNot = 'Endeks artışı %${_yz(kurus(artis))}, eşik ${esik == null ? 'girilmedi' : '(%${_yz(esik)})'} aşılmadığı için alış bedeli endekslenmedi';
        }
      }
      final kazanc = kurus(satis - endAlis - masraf);
      final matrah = kazanc > istisna ? kurus(kazanc - istisna) : 0.0;
      final vergi = muaf || kazanc <= 0 ? 0.0 : kurus(gelirVergisiTarife(p, diger + matrah) - gelirVergisiTarife(p, diger));
      sonuc = _sonuc([
        ('Değer artış kazancı ($_daYil tarifesi)', ''),
        ('Elde tutma süresi', '$sureYil yıl $sureKalanAy ay'),
        ('Satış bedeli', tl(satis)),
        ('İktisap bedeli', tl(alis)),
        (endNot, endAlis == alis ? '' : tl(endAlis)),
        if (masraf > 0) ('İktisap ve satış masrafları', '-${tl(masraf)}'),
        (kazanc >= 0 ? 'Hesaplanan kazanç' : 'Hesaplanan zarar', tl(kazanc.abs())),
        if (istisna > 0) ('Yıllık istisna tutarı', '-${tl(istisna > kazanc ? (kazanc > 0 ? kazanc : 0) : istisna)}'),
        ('Vergiye tabi matrah', tl(muaf || kazanc <= 0 ? 0 : matrah)),
        if (diger > 0) ('Diğer gelirlerin matrahı (tarife başlangıcı)', tl(diger)),
        if (muaf) ('Elde tutma süresi girilen süreyi (${_yz(sure)} yıl) doldurduğu için vergi dışı görünüyor', ''),
        ('>Hesaplanan gelir vergisi', tl(vergi)),
      ], 'deger_artis_kazanci_$_daYil', 'Değer artış kazancı $_daYil');
    }
    Widget tarih(String e, DateTime d, void Function(DateTime) ata) => OutlinedButton.icon(
          onPressed: () async {
            final x = await showDatePicker(context: context, initialDate: d, firstDate: DateTime(1980), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
            if (x != null) setState(() => ata(x));
          },
          icon: const Icon(Icons.event, size: 18),
          label: Text('$e: ${_tr(d)}'),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<int>(
          initialValue: _daYil,
          decoration: const InputDecoration(labelText: 'Satış yılı (tarife)', isDense: true),
          items: [for (final y in bordroYillari()) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _daYil = v ?? _daYil),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        tarih('İktisap tarihi', _daAlisT, (x) => _daAlisT = x),
        tarih('Satış tarihi', _daSatisT, (x) => _daSatisT = x),
      ]),
      const SizedBox(height: 10),
      MaasAlani(controller: _daAlis, etiket: 'İktisap (alış) bedeli (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _daSatis, etiket: 'Satış bedeli (TL)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _daMasraf, etiket: 'Belgeli iktisap ve satış masrafları (TL, varsa)', ipucu: '0,00'),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_daEndA, 'İktisap tarihinden önceki ayın endeksi (Yİ-ÜFE)', genislik: 320),
        _oranAlani(_daEndS, 'Satış tarihinden önceki ayın endeksi (Yİ-ÜFE)', genislik: 320),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _oranAlani(_daEsik, 'Endeksleme için artış eşiği (%, mevzuattan doğrula)', genislik: 320),
        _oranAlani(_daSure, 'Vergiden müstesna elde tutma süresi (yıl, mevzuattan doğrula)', genislik: 360),
      ]),
      const SizedBox(height: 10),
      MaasAlani(controller: _daIstisna, etiket: 'Yıllık istisna tutarı (TL, güncel tutarı gir)', ipucu: '0,00'),
      const SizedBox(height: 10),
      MaasAlani(controller: _daDiger, etiket: 'Aynı yıl beyan edilecek diğer gelirlerin matrahı (TL, varsa)', ipucu: '0,00'),
      const SizedBox(height: 14),
      sonuc,
      _not('Taşınmaz ve benzeri iktisap edilen değerlerin satışı için ön hesap yapar. Elde tutma süresi, endeksleme eşiği, istisna tutarı ve varlık türüne göre '
          '(taşınmaz, hisse, diğer haklar) uygulama değişir; bu değerleri güncel mevzuattan kontrol edip kendin gir. Endeks değerlerini TÜİK duyurusundan kendin gir. '
          'Bina ve arsa ayrımı, miras veya bağış yoluyla iktisap, kamulaştırma gibi özel durumlar hesaplanmaz.'),
    ]);
  }

  // ---------------------------------------------------------------- Emlak vergisi / yeniden değerleme
  Widget _emlak() {
    Widget sonuc = const Text('Değeri gir.');
    if (_emMod == 0) {
      final d = _sayi(_emDeger.text), o = _sayi(_emOran.text);
      if (d != null && d > 0 && o != null && o >= 0) {
        final yil = kurus(d * o / 1000 * (_emBuyuk ? 2 : 1));
        sonuc = _sonuc([
          ('Emlak vergisi ($_emTur)', ''),
          ('Vergi değeri', tl(d)),
          ('Oran', 'binde ${_yz(o)}${_emBuyuk ? ' x 2 (büyükşehir)' : ''}'),
          ('>Yıllık emlak vergisi', tl(yil)),
          ('İki eşit taksit', tl(kurus(yil / 2))),
        ], 'emlak_vergisi', 'Emlak vergisi hesabı',
            vadeler: [('Emlak vergisi 1. taksit son günü', DateTime(DateTime.now().year, 5, 31)), ('Emlak vergisi 2. taksit son günü', DateTime(DateTime.now().year, 11, 30))]);
      }
    } else {
      final e = _sayi(_emEski.text), a = _sayi(_emArtis.text);
      if (e != null && e > 0 && a != null && a >= 0) {
        final yeni = kurus(e * (1 + a / 100));
        sonuc = _sonuc([
          ('Yeniden değerleme oranıyla artış', ''),
          ('Önceki yıl tutarı', tl(e)),
          ('Artış oranı', '%${_yz(a)}'),
          ('Artış tutarı', tl(kurus(yeni - e))),
          ('>Yeni tutar', tl(yeni)),
          ('İki eşit taksit', tl(kurus(yeni / 2))),
        ], 'yeniden_degerleme', 'Yeniden değerleme artışı');
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: 0, label: Text('Emlak vergisi')), ButtonSegment(value: 1, label: Text('Yeniden değerleme artışı'))],
        selected: {_emMod},
        onSelectionChanged: (v) => setState(() => _emMod = v.first),
      ),
      const SizedBox(height: 12),
      if (_emMod == 0) ...[
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in _emTurleri.entries)
            ChoiceChip(
              label: Text('${e.key} (binde ${e.value})'),
              selected: _emTur == e.key,
              onSelected: (_) => setState(() {
                _emTur = e.key;
                _emOran.text = e.value;
              }),
            ),
        ]),
        const SizedBox(height: 10),
        MaasAlani(controller: _emDeger, etiket: 'Bina / arsa / arazi vergi değeri (TL)', ipucu: '0,00'),
        const SizedBox(height: 10),
        _oranAlani(_emOran, 'Oran (binde)'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _emBuyuk,
          onChanged: (v) => setState(() => _emBuyuk = v ?? false),
          title: const Text('Büyükşehir belediyesi sınırları içinde (oran 2 katı)'),
        ),
      ] else ...[
        MaasAlani(controller: _emEski, etiket: 'Önceki yıl tutarı (MTV, emlak, harç vb., TL)', ipucu: '0,00'),
        const SizedBox(height: 10),
        _oranAlani(_emArtis, 'Yeniden değerleme oranı (%, güncel oranı gir)', genislik: 340),
      ],
      const SizedBox(height: 14),
      sonuc,
      _not(_emMod == 0
          ? 'Oranlar düzenlenebilir; vergi değeri belediyenin takdir ettiği değerdir. Muafiyet, indirim ve 1 yıl içinde yeniden değerleme sınırı gibi durumlar uygulanmaz.'
          : 'MTV gibi tarifeye bağlı vergilerde yeni yıl tutarı tarifeden okunur; bu araç yalnızca oranla artışı hesaplar. Oranı her yıl resmî ilandan gir.'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vergi hesaplayıcı', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final (i, ad) in const ['KDV', 'İki bilinmeyenli KDV', 'Gelir vergisi', 'Damga vergisi', 'Net - brüt maaş', 'Stopaj', 'SMM makbuzu', 'Kira vergisi', 'Emlak / yeniden değerleme', 'Ücretli yıllık beyan', 'Kâr dağıtımı', 'Ortak cari faizi', 'Finansman gider kısıtlaması', 'Kuruluş maliyeti', 'Personel ödemeleri', 'Gecikme / pişmanlık zammı', 'Değer artış kazancı', 'Tapu harcı / alım-satım maliyeti', 'Vergi ceza hesaplayıcı', 'Şirket türü karşılaştırma'].indexed)
                ChoiceChip(label: Text(ad), selected: _sekme == i, onSelected: (_) => setState(() => _sekme = i)),
            ]),
            const SizedBox(height: 14),
            if (_sekme == 15)
              const ZamHesapSayfasi(gomulu: true)
            else
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: switch (_sekme) {
                    0 => _kdv(),
                    1 => _ikiBilinmeyenli(),
                    2 => _gelirVergisi(),
                    3 => _damga(),
                    4 => _maasHesap(),
                    5 => _stopaj(),
                    6 => _smm(),
                    7 => _kira(),
                    8 => _emlak(),
                    9 => _ybBeyan(),
                    10 => _karDagitimi(),
                    11 => _ortakFaiz(),
                    12 => _finansmanKisit(),
                    13 => _kurulus(),
                    16 => _degerArtis(),
                    17 => _tapuMaliyet(),
                    18 => _vergiCeza(),
                    19 => _sirketKarsilastir(),
                    _ => _personelOdeme(),
                  },
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Bu araçlar ön hesap içindir, kesin tutar için güncel mevzuat ve resmî hesaplamaları esas al.', style: TextStyle(fontSize: 12, color: Colors.black87)),
            ),
          ]),
        ),
      ),
    ]);
  }
}
