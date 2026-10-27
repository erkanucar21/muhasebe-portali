import 'marka.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bordro_cikti.dart' show bordroKaydet;
import 'firmalar.dart';
import 'bordro_hesap.dart';
import 'secili_firma.dart';
import 'tatiller.dart';

// Kıdem tazminatı tavanı (her dönem için ilk gün, tavan). Yeni dönem açıklanınca buraya ekle.
// 2026 değerleri resmi duyurudan alındı; 2024 ve 2025 değerlerini kullanmadan önce kontrol et.
final tavanlar = <(DateTime, double)>[
  (DateTime(2024, 1, 1), 35058.58),
  (DateTime(2024, 7, 1), 41828.42),
  (DateTime(2025, 1, 1), 46655.43),
  (DateTime(2025, 7, 1), 53919.68),
  (DateTime(2026, 1, 1), 64948.77),
  (DateTime(2026, 7, 1), 73729.87),
];

double _tavanBul(DateTime t) {
  var r = tavanlar.first.$2;
  for (final (d, v) in tavanlar) {
    if (!t.isBefore(d)) r = v;
  }
  return r;
}

double kidemTavani(DateTime t) => _tavanBul(t);

Future<Uint8List> tazminatCetveliPdf({
  required String kapsam,
  required String firma,
  required String kisi,
  required DateTime giris,
  required DateTime cikis,
  required String sure,
  required double giydirilmis,
  required double tavan,
  required double esas,
  required bool kidemVar,
  required bool kidemHak,
  required double kidemBrut,
  required double kidemDamga,
  required bool ihbarHak,
  required int hafta,
  required double ihbarBrut,
  required double ihbarGv,
  required double ihbarDamga,
}) =>
    _pdfYap(
      kapsam: kapsam,
      firma: firma,
      kisi: kisi,
      giris: giris,
      cikis: cikis,
      sure: sure,
      tur: 'Ayrılış paketi (seçilen haklar)',
      giydirilmis: giydirilmis,
      tavan: tavan,
      esas: esas,
      kidemVar: kidemVar,
      kidemHak: kidemHak,
      kidemBrut: kidemBrut,
      kidemDamga: kidemDamga,
      kidemNet: kidemBrut - kidemDamga,
      ihbarHak: ihbarHak,
      hafta: hafta,
      ihbarBrut: ihbarBrut,
      ihbarGv: ihbarGv,
      ihbarDamga: ihbarDamga,
      ihbarNet: ihbarBrut - ihbarGv - ihbarDamga,
    );

class _CikisTuru {
  final String ad;
  final bool kidem, ihbar;
  const _CikisTuru(this.ad, this.kidem, this.ihbar);
}

const _turler = [
  _CikisTuru('İşveren haksız feshetti, ihbar süresi kullandırmadı', true, true),
  _CikisTuru('İşveren feshetti, ihbar süresi kullandırıldı', true, false),
  _CikisTuru('İşçi haklı nedenle feshetti (ücret ödenmemesi, SGK eksik bildirim vb.)', true, false),
  _CikisTuru('Emeklilik, askerlik, kadın işçi evlilik (1 yıl içinde) veya ölüm', true, false),
  _CikisTuru('İşçi kendi isteğiyle istifa etti', false, false),
  _CikisTuru('İşveren haklı nedenle feshetti (devamsızlık, güveni kötüye kullanma vb.)', false, false),
];

String _para(double v) {
  final s = v.abs().toStringAsFixed(2).split('.');
  final tam = s[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '${v < 0 ? '-' : ''}$tam,${s[1]} TL';
}

double _oku(String s) {
  final t = s.trim().replaceAll(' ', '');
  if (t.isEmpty) return 0;
  final n = t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t) ? t.replaceAll('.', '') : t);
  return double.tryParse(n) ?? 0;
}

String _tarih(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class TazminatSayfasi extends StatefulWidget {
  const TazminatSayfasi({super.key});
  @override
  State<TazminatSayfasi> createState() => _TazminatSayfasiState();
}

class _TazminatSayfasiState extends State<TazminatSayfasi> {
  final _brut = TextEditingController(), _yanHak = TextEditingController(), _tavan = TextEditingController(), _kum = TextEditingController(), _izin = TextEditingController();
  String? _izinNot;
  List<Map<String, dynamic>> _personel = [];
  int? _personelId;
  DateTime? _giris, _cikis;
  int _tur = 0;
  String? _not;

  @override
  void initState() {
    super.initState();
    seciliFirmaId.addListener(_firmaDegisti);
    _firmaDegisti();
  }

  @override
  void dispose() {
    seciliFirmaId.removeListener(_firmaDegisti);
    for (final c in [_brut, _yanHak, _tavan, _kum, _izin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _firmaDegisti() async {
    final id = seciliFirmaId.value;
    _personelId = null;
    if (id == null) {
      setState(() => _personel = []);
      return;
    }
    try {
      final r = await Supabase.instance.client.from('personel').select().eq('firma_id', id).order('ad');
      if (!mounted) return;
      setState(() => _personel = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  void _personelSec(int? id) {
    final p = _personel.where((e) => e['id'] == id).firstOrNull;
    setState(() {
      _personelId = id;
      if (p == null) return;
      _giris = DateTime.parse(p['giris'] as String);
      _cikis = p['cikis'] == null ? null : DateTime.parse(p['cikis'] as String);
      _tavan.text = '';
      _otomatik();
    });
    _izinOtomatik();
  }

  /// İş Kanunu m.53: 1-5 yıl 14, 5 yıldan fazla 15 yıldan az 20, 15 yıl ve fazlası 26 gün.
  int _izinHakki(int yil) => yil < 1 ? 0 : (yil <= 5 ? 14 : (yil < 15 ? 20 : 26));

  /// Tamamlanan her hizmet yılının hakkını toplar, işlenmiş izin günlerini düşer.
  Future<void> _izinOtomatik() async {
    final giris = _giris, cikis = _cikis, id = _personelId;
    if (giris == null || cikis == null || id == null || cikis.isBefore(giris)) return;
    final son = DateTime(cikis.year, cikis.month, cikis.day + 1);
    var tam = son.year - giris.year;
    if (DateTime(giris.year + tam, giris.month, giris.day).isAfter(son)) tam--;
    var hak = 0;
    for (var k = 1; k <= tam; k++) {
      hak += _izinHakki(k);
    }
    try {
      final r = await Supabase.instance.client.from('izin_kayitlari').select('tarih').eq('personel_id', id).eq('durum', 'izin');
      final kullanilan = (r as List).where((m) => !izneSayilmaz(DateTime.parse((m as Map)['tarih'] as String))).length;
      final kalan = hak - kullanilan;
      if (!mounted) return;
      setState(() {
        _izin.text = (kalan > 0 ? kalan : 0).toString();
        _izinNot = 'Hak: $hak gün, takipte işlenen izin: $kullanilan gün. Kağıt üzerinde başka izin kullanıldıysa günü elle düzelt.';
      });
    } catch (_) {}
  }

  /// Seçili personelin brüt ücretini ve çıkış ayına kadarki kümülatif gelir vergisi matrahını bordro hesabından bulur.
  void _otomatik() {
    final p = _personel.where((e) => e['id'] == _personelId).firstOrNull;
    final giris = _giris;
    if (p == null || giris == null) return;
    final ucret = ((p['ucret'] ?? 0) as num).toDouble();
    final net = (p['maas_turu'] ?? 'net') != 'brut';
    final asgari = (p['asgari_ucretli'] ?? false) == true;
    final cikis = _cikis;
    final yil = (cikis ?? DateTime.now()).year;
    final param = bordroParam(yil);
    _brut.text = '';
    _kum.text = '';
    _not = null;
    if (param == null) {
      if (!net) {
        _brut.text = ucret.toStringAsFixed(2).replaceAll('.', ',');
      } else {
        _not = '$yil yılı bordro parametresi tanımlı değil. Brüt ücreti ve matrahı elle yaz.';
      }
      return;
    }
    final sonAy = cikis?.month ?? DateTime.now().month;
    final liste = yillikBordro(param, BordroGirdi(ucret: ucret, net: net, asgari: asgari, giris: giris, cikis: cikis), sonAy);
    AyBordro? son;
    for (final b in liste) {
      if (b.gun > 0) son = b;
    }
    if (son == null) {
      _not = 'Bu personelin $yil yılında bordrosu yok (giriş veya çıkış başka yılda). Brütü ve matrahı elle yaz.';
      return;
    }
    // Eksik gün çalışılan aya göre tam aylık brüt
    final tamBrut = son.gun >= 30 ? son.brut : kurus(son.brut * 30 / son.gun);
    _brut.text = tamBrut.toStringAsFixed(2).replaceAll('.', ',');
    _kum.text = liste.last.kumMatrah.toStringAsFixed(2).replaceAll('.', ',');
    if (net) {
      _not = 'Kayıtlı maaş NET (${_para(ucret)}). Brüt ücret ve matrah bordro hesabından bulundu, kontrol et.';
    }
  }

  Future<void> _tarihSec(bool giris) async {
    final su = giris ? _giris : _cikis;
    final d = await showDatePicker(
      context: context,
      initialDate: su ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (d != null) {
      setState(() {
        giris ? _giris = d : _cikis = d;
        if (_personelId != null) _otomatik();
      });
      _izinOtomatik();
    }
  }

  @override
  Widget build(BuildContext context) {
    final giris = _giris, cikis = _cikis;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Bilgiler', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 10),
            if (_personel.isNotEmpty)
              DropdownButtonFormField<int>(
                key: ValueKey('p-${seciliFirmaId.value}-$_personelId'),
                initialValue: _personelId,
                decoration: const InputDecoration(labelText: 'Personel (seçersen bilgiler dolar, istersen elle gir)'),
                items: [for (final p in _personel) DropdownMenuItem(value: p['id'] as int, child: Text(p['ad'] as String))],
                onChanged: _personelSec,
              )
            else
              const Text('Üstten firma seçersen personeli listelenir. Elle de hesaplayabilirsin.', style: TextStyle(color: Colors.black87)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(onPressed: () => _tarihSec(true), icon: const Icon(Icons.login, size: 18), label: Text(giris == null ? 'İşe giriş tarihi' : 'Giriş: ${_tarih(giris)}')),
              OutlinedButton.icon(onPressed: () => _tarihSec(false), icon: const Icon(Icons.logout, size: 18), label: Text(cikis == null ? 'İşten çıkış tarihi' : 'Çıkış: ${_tarih(cikis)}')),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _tur,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Çıkış şekli'),
              items: [for (var i = 0; i < _turler.length; i++) DropdownMenuItem(value: i, child: Text(_turler[i].ad, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _tur = v ?? 0),
            ),
            const SizedBox(height: 10),
            if (_not != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_not!, style: const TextStyle(color: Color(0xFFB26A00), fontSize: 13))),
            if (_izinNot != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_izinNot!, style: const TextStyle(color: Colors.black87, fontSize: 12))),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _alan(_brut, 'Aylık brüt ücret (TL)'),
              _alan(_yanHak, 'Aylık yan haklar toplamı (yemek, yol vb.)'),
              _alan(_tavan, 'Kıdem tavanı (boşsa otomatik)'),
              _alan(_kum, 'Yıl başından beri GV matrahı (ihbar vergisi için)'),
              _alan(_izin, 'Kullanılmamış yıllık izin (gün)'),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      _sonuc(),
    ]);
  }

  Widget _alan(TextEditingController c, String etiket) => SizedBox(
        width: 260,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: etiket),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _sonuc() {
    final giris = _giris, cikis = _cikis;
    final brut = _oku(_brut.text);
    if (giris == null || cikis == null || brut <= 0) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Giriş, çıkış tarihi ve brüt ücreti girince sonuç burada görünür.')));
    }
    if (cikis.isBefore(giris)) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Çıkış tarihi girişten önce olamaz.', style: TextStyle(color: Colors.red))));
    }
    // Çıkış günü dahil: bitişi ertesi gün (hariç) alıp yıl, ay, gün farkını çıkarır.
    final son = DateTime(cikis.year, cikis.month, cikis.day + 1);
    var y = son.year - giris.year, m = son.month - giris.month, g = son.day - giris.day;
    if (g < 0) {
      m -= 1;
      g += DateTime(son.year, son.month, 0).day;
    }
    if (m < 0) {
      y -= 1;
      m += 12;
    }
    final toplamAy = y * 12 + m;
    final tur = _turler[_tur];
    final giydirilmis = brut + _oku(_yanHak.text);
    final tavanOto = _tavanBul(cikis);
    final tavan = _oku(_tavan.text) > 0 ? _oku(_tavan.text) : tavanOto;
    final esas = giydirilmis < tavan ? giydirilmis : tavan;
    final sureYil = y + m / 12 + g / 365;

    final kidemVar = tur.kidem && toplamAy >= 12;
    final kidemBrut = kidemVar ? kurus(esas * sureYil) : 0.0;
    final kidemDamga = kurus(kidemBrut * damgaOrani);
    final kidemNet = kidemBrut - kidemDamga;

    final hafta = toplamAy < 6 ? 2 : (toplamAy < 18 ? 4 : (toplamAy < 36 ? 6 : 8));
    final ihbarBrut = tur.ihbar ? kurus(giydirilmis / 30 * 7 * hafta) : 0.0;
    final param = bordroParam(cikis.year) ?? bordroParam(bordroYillari().last);
    var ihbarGv = 0.0;
    if (ihbarBrut > 0 && param != null) {
      final kum = _oku(_kum.text);
      ihbarGv = kurus(gelirVergisiTarife(param, kum + ihbarBrut) - gelirVergisiTarife(param, kum));
    }
    final ihbarDamga = kurus(ihbarBrut * damgaOrani);
    final ihbarNet = ihbarBrut - ihbarGv - ihbarDamga;
    final toplamNet = kidemNet + ihbarNet;
    final izinGun = _oku(_izin.text).round();
    final izinBrut = izinGun > 0 ? kurus(giydirilmis / 30 * izinGun) : 0.0;

    Widget satir(String a, String b, {bool kalin = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: kalin ? FontWeight.w700 : FontWeight.normal))),
            Text(b, style: TextStyle(fontWeight: kalin ? FontWeight.w700 : FontWeight.normal)),
          ]),
        );

    final ozet = StringBuffer()
      ..writeln('Çalışma süresi: $y yıl $m ay $g gün (${_tarih(giris)} - ${_tarih(cikis)})')
      ..writeln('Kıdem tazminatı: brüt ${_para(kidemBrut)}, net ${_para(kidemNet)}')
      ..writeln('İhbar tazminatı ($hafta hafta): brüt ${_para(ihbarBrut)}, net ${_para(ihbarNet)}')
      ..writeln('Toplam net: ${_para(toplamNet)}')
      ..writeln(izinGun > 0 ? 'Kullanılmayan yıllık izin ($izinGun gün): brüt ${_para(izinBrut)} (SGK ve vergi kesintileri bordroda)' : '');

    Future<void> indir(String kapsam) async {
      final kisi = _personel.where((e) => e['id'] == _personelId).firstOrNull;
      final firma = FirmaDeposu.ornek.bul(seciliFirmaId.value ?? -1)?.unvan ?? '';
      try {
        final b = await _pdfYap(
          kapsam: kapsam,
          firma: firma,
          kisi: kisi == null ? '' : kisi['ad'] as String,
          giris: giris,
          cikis: cikis,
          sure: '$y yıl $m ay $g gün',
          tur: tur.ad,
          giydirilmis: giydirilmis,
          tavan: tavan,
          esas: esas,
          kidemVar: kidemVar,
          kidemHak: tur.kidem,
          kidemBrut: kidemBrut,
          kidemDamga: kidemDamga,
          kidemNet: kidemNet,
          ihbarHak: tur.ihbar,
          hafta: hafta,
          ihbarBrut: ihbarBrut,
          ihbarGv: ihbarGv,
          ihbarDamga: ihbarDamga,
          ihbarNet: ihbarNet,
          izinGun: izinGun,
          izinBrut: izinBrut,
        );
        final ad = kisi == null ? 'personel' : (kisi['ad'] as String).replaceAll(' ', '_');
        final etiket = kapsam == 'kidem' ? 'kidem' : (kapsam == 'ihbar' ? 'ihbar' : 'kidem_ihbar');
        await bordroKaydet('${etiket}_tazminat_$ad', b, 'pdf');
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF oluşturulamadı: $e')));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sonuç', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          satir('Çalışma süresi', '$y yıl $m ay $g gün'),
          satir('Giydirilmiş brüt ücret', _para(giydirilmis)),
          const Divider(),
          const Text('Kıdem tazminatı', style: TextStyle(fontWeight: FontWeight.w600)),
          if (!tur.kidem)
            const Text('Bu çıkış şeklinde kıdem tazminatı hakkı yok.', style: TextStyle(color: Colors.black87))
          else if (toplamAy < 12)
            const Text('1 yıldan az çalışma: kıdem tazminatı hakkı doğmaz.', style: TextStyle(color: Colors.black87))
          else ...[
            satir('Hesaba esas ücret (tavan: ${_para(tavan)})', _para(esas)),
            satir('Brüt kıdem tazminatı', _para(kidemBrut)),
            satir('Damga vergisi (binde 7,59)', '-${_para(kidemDamga)}'),
            satir('Net kıdem tazminatı', _para(kidemNet), kalin: true),
          ],
          const Divider(),
          const Text('İhbar tazminatı', style: TextStyle(fontWeight: FontWeight.w600)),
          if (!tur.ihbar)
            const Text('Bu çıkış şeklinde ihbar tazminatı hakkı yok.', style: TextStyle(color: Colors.black87))
          else ...[
            satir('İhbar süresi', '$hafta hafta'),
            satir('Brüt ihbar tazminatı', _para(ihbarBrut)),
            satir('Gelir vergisi', '-${_para(ihbarGv)}'),
            satir('Damga vergisi (binde 7,59)', '-${_para(ihbarDamga)}'),
            satir('Net ihbar tazminatı', _para(ihbarNet), kalin: true),
          ],
          const Divider(),
          satir('TOPLAM NET ÖDENECEK', _para(toplamNet), kalin: true),
          if (izinGun > 0) ...[
            const Divider(),
            const Text('Kullanılmayan yıllık izin ücreti', style: TextStyle(fontWeight: FontWeight.w600)),
            satir('Kullanılmayan izin', '$izinGun gün'),
            satir('Brüt izin ücreti (giydirilmiş ücret / 30 x gün)', _para(izinBrut), kalin: true),
            const Text('Ücret niteliğinde olduğundan SGK primi ve gelir vergisi kesilir; son ay bordrosuna eklenerek hesaplanır.', style: TextStyle(fontSize: 12, color: Colors.black87)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (tur.kidem && kidemVar)
              FilledButton.icon(
                onPressed: () => indir('kidem'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Kıdem PDF'),
              ),
            if (tur.ihbar)
              FilledButton.icon(
                onPressed: () => indir('ihbar'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('İhbar PDF'),
              ),
            if ((tur.kidem && kidemVar) && tur.ihbar)
              FilledButton.tonalIcon(
                onPressed: () => indir('hepsi'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('İkisi birlikte PDF'),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: ozet.toString()));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Özet kopyalandı.')));
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Özeti kopyala'),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Notlar: Çıkış günü süreye dahildir. Kıdem tazminatı 30 günlük giydirilmiş brüt ücret üzerinden, tavanı aşmayacak şekilde hesaplanır; '
            'yalnızca damga vergisi kesilir. İhbar tazminatında tavan yoktur, gelir vergisi yıl başından beri matraha göre hesaplanır '
            '(matrahı bilmiyorsan boş bırak, vergi sıfırdan başlayarak hesaplanır). Yıllık izin ücreti brüt gösterilir ve toplama katılmaz; fazla mesai ve '
            'diğer alacaklar dahil değildir. Önemli işlemlerde sonucu ayrıca kontrol et.',
            style: TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ]),
      ),
    );
  }
}

Future<Uint8List> _pdfYap({
  required String kapsam,
  required String firma,
  required String kisi,
  required DateTime giris,
  required DateTime cikis,
  required String sure,
  required String tur,
  required double giydirilmis,
  required double tavan,
  required double esas,
  required bool kidemVar,
  required bool kidemHak,
  required double kidemBrut,
  required double kidemDamga,
  required double kidemNet,
  required bool ihbarHak,
  required int hafta,
  required double ihbarBrut,
  required double ihbarGv,
  required double ihbarDamga,
  required double ihbarNet,
  int izinGun = 0,
  double izinBrut = 0,
}) async {
  final kidemGoster = kapsam != 'ihbar', ihbarGoster = kapsam != 'kidem';
  final toplam = (kidemGoster ? kidemNet : 0.0) + (ihbarGoster ? ihbarNet : 0.0);
  final baslikAd = kapsam == 'kidem' ? 'KIDEM TAZMİNATI HESAP CETVELİ' : (kapsam == 'ihbar' ? 'İHBAR TAZMİNATI HESAP CETVELİ' : 'KIDEM VE İHBAR TAZMİNATI HESAP CETVELİ');
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
    ),
  );
  const gri = PdfColor.fromInt(0xFFF2F2F2);
  pw.Widget hucre(String t, {bool kalin = false, bool sag = false, PdfColor? zemin}) => pw.Container(
        color: zemin,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        alignment: sag ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(t, style: pw.TextStyle(fontSize: 10, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
  pw.Widget tablo(List<(String, String, bool)> satirlar) => pw.Table(
        border: pw.TableBorder.all(width: 0.6),
        columnWidths: const {0: pw.FlexColumnWidth(2.2), 1: pw.FlexColumnWidth(1)},
        children: [
          for (final (a, b, k) in satirlar)
            pw.TableRow(children: [hucre(a, kalin: k, zemin: k ? gri : null), hucre(b, kalin: k, sag: true, zemin: k ? gri : null)]),
        ],
      );
  pw.Widget baslik(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      );
  pw.Widget imzaKutusu(String ad) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(ad, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Tarih: ....... / ....... / ...........', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 38),
        pw.Container(height: 0.8, color: PdfColors.black),
        pw.SizedBox(height: 3),
        pw.Text('Ad Soyad / İmza', style: const pw.TextStyle(fontSize: 8)),
      ]);
  pw.Widget not(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text(t, style: const pw.TextStyle(fontSize: 8.5)));

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
      header: (c) => markaUst(),
      footer: (c) => markaAlt(c),
    build: (c) => [
      pw.Text(baslikAd, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      tablo([
        if (firma.isNotEmpty) ('İşyeri', firma, false),
        if (kisi.isNotEmpty) ('İşçi', kisi, false),
        ('İşe giriş tarihi', _tarih(giris), false),
        ('İşten çıkış tarihi', _tarih(cikis), false),
        ('Çalışma süresi (çıkış günü dahil)', sure, false),
        ('Çıkış şekli', tur, false),
        ('Giydirilmiş brüt aylık ücret', _para(giydirilmis), false),
      ]),
      if (kidemGoster) baslik('Kıdem tazminatı'),
      if (kidemGoster && !kidemHak)
        pw.Text('Çıkış şekli nedeniyle kıdem tazminatı hakkı doğmamıştır.', style: const pw.TextStyle(fontSize: 10))
      else if (kidemGoster && !kidemVar)
        pw.Text('Bir yıldan az çalışma nedeniyle kıdem tazminatı hakkı doğmamıştır.', style: const pw.TextStyle(fontSize: 10))
      else if (kidemGoster)
        tablo([
          ('Kıdem tazminatı tavanı', _para(tavan), false),
          ('Hesaba esas aylık ücret', _para(esas), false),
          ('Brüt kıdem tazminatı (esas ücret x çalışma yılı)', _para(kidemBrut), false),
          ('Damga vergisi (binde 7,59)', '-${_para(kidemDamga)}', false),
          ('Net kıdem tazminatı', _para(kidemNet), true),
        ]),
      if (ihbarGoster) baslik('İhbar tazminatı'),
      if (ihbarGoster && !ihbarHak)
        pw.Text('Çıkış şekli nedeniyle ihbar tazminatı hakkı doğmamıştır.', style: const pw.TextStyle(fontSize: 10))
      else if (ihbarGoster)
        tablo([
          ('İhbar süresi', '$hafta hafta', false),
          ('Brüt ihbar tazminatı (haftalık ücret x hafta)', _para(ihbarBrut), false),
          ('Gelir vergisi', '-${_para(ihbarGv)}', false),
          ('Damga vergisi (binde 7,59)', '-${_para(ihbarDamga)}', false),
          ('Net ihbar tazminatı', _para(ihbarNet), true),
        ]),
      if (izinGun > 0) ...[
        baslik('Kullanılmayan yıllık izin ücreti'),
        tablo([
          ('Kullanılmayan yıllık izin', '$izinGun gün', false),
          ('Brüt izin ücreti (giydirilmiş ücret / 30 x gün)', _para(izinBrut), true),
        ]),
        not('İzin ücreti ücret niteliğindedir; SGK primi ve gelir vergisi kesintileri son ay bordrosunda hesaplanır, yukarıdaki toplama dahil değildir. (4857 sayılı Kanun m.59)'),
      ],
      pw.SizedBox(height: 10),
      tablo([(kapsam == 'hepsi' ? 'TOPLAM NET ÖDENECEK TUTAR' : 'NET ÖDENECEK TUTAR', _para(toplam), true)]),
      baslik('Yasal dayanak'),
      if (kidemGoster) not('• Kıdem tazminatı: 1475 sayılı İş Kanunu m.14. Her tam çalışma yılı için 30 günlük ücret tutarında, artan süre kıstelyevm hesabıyla ödenir. '
          'Bir yıldan az çalışmada hak doğmaz. Hesaba esas ücret, ilgili dönemdeki kıdem tazminatı tavanını aşamaz.'),
      if (ihbarGoster) not('• İhbar süreleri ve tazminatı: 4857 sayılı İş Kanunu m.17. Süreler: 6 aydan az 2 hafta, 6 ay - 1,5 yıl 4 hafta, 1,5 - 3 yıl 6 hafta, 3 yıldan fazla 8 hafta. '
          'Bildirim süresine uymayan taraf, bu sürelere ait ücret tutarında tazminat öder.'),
      not('• Haklı nedenle fesih: 4857 sayılı İş Kanunu m.24 (işçi) ve m.25 (işveren).'),
      not('• Vergiler: kıdem tazminatı gelir vergisinden istisnadır (193 sayılı GVK m.25/7), yalnızca damga vergisi (488 sayılı Kanun) kesilir. '
          'İhbar tazminatı ücret niteliğinde olup gelir vergisi ve damga vergisine tabidir, SGK primi kesilmez.'),
      pw.SizedBox(height: 26),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: imzaKutusu('İŞVEREN / MÜŞAVİR')),
        pw.SizedBox(width: 30),
        pw.Expanded(child: imzaKutusu('İŞÇİ${kisi.isNotEmpty ? ' ($kisi)' : ''}')),
      ]),
      not('Bu cetvel bilgilendirme amaçlıdır; fazla mesai ve diğer alacaklar dahil değildir. Hesaplama tarihi: ${_tarih(DateTime.now())}.'),
    ],
  ));
  return doc.save();
}
