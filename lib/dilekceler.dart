import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'bordro_cikti.dart' show bordroKaydet;
import 'firmalar.dart';

String _buyuk(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

String _ascii(String s) {
  const a = 'çğıöşüÇĞİÖŞÜ', b = 'cgiosuCGIOSU';
  var r = s;
  for (var i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
}

const _nokta = '...........................';
const _tarihNokta = '....../....../........';

String _d(String s, [String yedek = _nokta]) => s.trim().isEmpty ? yedek : s.trim();

class _Alan {
  final String anahtar, etiket, varsayilan;
  final int satir;
  const _Alan(this.anahtar, this.etiket, {this.varsayilan = '', this.satir = 1});
}

typedef _V = String Function(String);

class _Belge {
  final String ad, aciklama, dosya, grup;
  final List<_Alan> alanlar;
  final Map<String, String Function(Firma)> firmadan;
  final List<pw.Widget> Function(_V v) icerik;
  final List<String> Function(_V v) imzalar;
  final String taraf; // dosya adına eklenecek alanın anahtarı
  const _Belge({
    required this.grup,
    required this.ad,
    required this.aciklama,
    required this.dosya,
    required this.alanlar,
    required this.icerik,
    required this.imzalar,
    this.firmadan = const {},
    this.taraf = 'sahip',
  });
}

pw.Widget _p(String m, {bool kalin = false, double boyut = 11, double alt = 9, pw.TextAlign hiza = pw.TextAlign.justify}) => pw.Padding(
      padding: pw.EdgeInsets.only(bottom: alt),
      child: pw.Text(m, textAlign: hiza, style: pw.TextStyle(fontSize: boyut, lineSpacing: 3, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

pw.Widget _baslik(String m) => _p(m, kalin: true, boyut: 13, hiza: pw.TextAlign.center, alt: 16);

// ---- Ortak alan kümeleri ve firma eşlemeleri
const _sahipAlanlari = [
  _Alan('sahip', 'Dilekçe sahibi (ad soyad / unvan)'),
  _Alan('no', 'Vergi no / T.C. kimlik no'),
  _Alan('adres', 'Adres'),
];

final Map<String, String Function(Firma)> _firmaEsle = {
  'sahip': (f) => f.unvan,
  'no': (f) => f.vergiNo.isNotEmpty ? f.vergiNo : f.tcNo,
  'adres': (f) => f.adres,
  'kurum': (f) => f.vergiDairesi,
};

/// Kuruma verilen dilekçe: kurum başlığı, konu, gövde paragrafları, tarih ve imza bloğu.
_Belge _dilekce({
  required String grup,
  required String ad,
  required String aciklama,
  required String dosya,
  required String kurumEtiket,
  required String kurumSon,
  required String konu,
  List<_Alan> ekler = const [],
  required List<String> Function(_V v) govde,
  String kapanis = 'Gereğini saygılarımla arz ederim.',
  Map<String, String Function(Firma)>? firmadan,
}) =>
    _Belge(
      grup: grup,
      ad: ad,
      aciklama: aciklama,
      dosya: dosya,
      alanlar: [_Alan('kurum', kurumEtiket), ..._sahipAlanlari, ...ekler],
      firmadan: firmadan ?? (kurumEtiket.toLowerCase().contains('vergi') ? _firmaEsle : {for (final e in _firmaEsle.entries) if (e.key != 'kurum') e.key: e.value}),
      icerik: (v) => [
        _p('${_buyuk(_d(v('kurum'), '.....................'))} ${_buyuk(kurumSon)}', kalin: true, hiza: pw.TextAlign.center, alt: 18),
        _p('Tarih: ${_tarihNokta}', hiza: pw.TextAlign.right, alt: 14),
        _p('KONU: $konu', kalin: true, alt: 12),
        for (final g in govde(v)) _p(g),
        _p(kapanis, alt: 22),
        _p('Adı soyadı / unvanı: ${_d(v('sahip'))}\nVergi / T.C. kimlik no: ${_d(v('no'))}\nAdres: ${_d(v('adres'))}', alt: 14),
      ],
      imzalar: (v) => ['${_d(v('sahip'), '')}\n(imza / kaşe)'],
    );


String _cizgi(int n) => List.filled(n, '_' * 72).join('\n');

String _t(DateTime? d) => d == null ? '' : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

pw.Widget _hucreYaz(String m, {bool kalin = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(m, style: pw.TextStyle(fontSize: 10, fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

/// Etiket - değer tablosu (resmî form görünümü).
pw.Widget _formTablo(List<(String, String)> satirlar) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Table(
        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
        columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
        children: [
          for (final (e, d) in satirlar) pw.TableRow(children: [_hucreYaz(e, kalin: true), _hucreYaz(d)]),
        ],
      ),
    );

pw.Widget _altBaslik(String m) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
      child: pw.Text(m, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    );

final Map<String, String Function(Firma)> _firmaForm = {
  'kurum': (f) => f.vergiDairesi,
  'vkn': (f) => f.vergiNo,
  'tc': (f) => f.tcNo,
  'ad': (f) => f.unvan,
  'ticaretSicil': (f) => f.ticaretSicilNo,
  'adres': (f) => f.adres,
  'eposta': (f) => f.eposta,
  'tel': (f) => f.telefon,
  'kurulusTarihi': (f) => _t(f.kurulus),
};

final Map<String, String Function(Firma)> _firmaIsveren = {
  'isveren': (f) => f.unvan,
  'adres': (f) => f.adres,
  'sicil': (f) => f.sgkSicilNo,
};

final _belgeler = <_Belge>[
  // ------------------------------------------------------------------ Vergi dairesi
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'Fazla veya mükerrer ödenen verginin iadesi / mahsubu',
    aciklama: 'Yanlış, fazla veya iki kez ödenen verginin iade ya da mahsup talebi.',
    dosya: 'vergi_iade_mahsup_talebi',
    kurumEtiket: 'Vergi dairesi adı (örn. Kadıköy)',
    kurumSon: 'Vergi Dairesi Müdürlüğüne',
    konu: 'Fazla / mükerrer ödenen verginin iadesi veya mahsubu talebi',
    ekler: const [
      _Alan('donem', 'Vergi türü ve dönemi (örn. KDV, 2026 Eylül)'),
      _Alan('tutar', 'Fazla ödenen tutar (TL)'),
      _Alan('odemeTarihi', 'Ödeme tarihi'),
      _Alan('neden', 'Ödemenin nedeni', satir: 3, varsayilan: 'Aynı borç hatalı olarak iki kez ödenmiştir.'),
      _Alan('yontem', 'İstenen yöntem (iade / mahsup)', varsayilan: 'mahsup'),
      _Alan('iban', 'İade için IBAN (mahsup ise boş)'),
    ],
    govde: (v) => [
      '${_d(v('donem'))} dönemine ilişkin olarak ${_d(v('odemeTarihi'))} tarihinde ${_d(v('tutar'))} TL ödeme yaptım. ${_d(v('neden'), '')}',
      'Bu nedenle fazla / yersiz ödenen tutarın ilgili mevzuat hükümleri çerçevesinde ${_d(v('yontem'))} edilmesini talep ederim.${v('iban').trim().isEmpty ? '' : ' İade, ${v('iban').trim()} numaralı IBAN\'a yapılabilir.'}',
      'Ödeme belgesinin (dekont / tahakkuk fişi) örneği ekte sunulmuştur.',
    ],
  ),
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'Vergi borcu yoktur yazısı talebi',
    aciklama: 'İhale, kredi, ruhsat veya başka işlemler için borç durumunu gösterir belge talebi.',
    dosya: 'vergi_borcu_yoktur_talebi',
    kurumEtiket: 'Vergi dairesi adı',
    kurumSon: 'Vergi Dairesi Müdürlüğüne',
    konu: 'Vergi borcu yoktur yazısı talebi',
    ekler: const [_Alan('amac', 'Belgenin kullanılacağı yer', varsayilan: 'ihale / kredi işlemi')],
    govde: (v) => [
      'Vergi dairenize kayıtlı mükellef olarak, ${_d(v('amac'))} için kurumunuza ait vergi borcu bulunup bulunmadığını gösterir yazının tarafıma verilmesini talep ederim.',
    ],
  ),
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'Vergi borcu taksitlendirme (tecil) talebi',
    aciklama: 'Vadesinde ödenemeyen vergi borçları için ödeme planı talebi (6183 sayılı Kanun).',
    dosya: 'vergi_taksitlendirme_talebi',
    kurumEtiket: 'Vergi dairesi adı',
    kurumSon: 'Vergi Dairesi Müdürlüğüne',
    konu: 'Vergi borcunun taksitlendirilmesi (tecil) talebi',
    ekler: const [
      _Alan('borc', 'Borç türü ve dönemi'),
      _Alan('tutar', 'Borç tutarı (TL)'),
      _Alan('taksit', 'İstenen taksit sayısı'),
      _Alan('neden', 'Ödeme güçlüğünün nedeni', satir: 3),
    ],
    govde: (v) => [
      'Vergi dairenize ${_d(v('borc'))} için ${_d(v('tutar'))} TL borcum bulunmaktadır. ${_d(v('neden'), '')}',
      'Borcun tamamını vadesinde ödeyemeyecek durumda olduğumdan, 6183 sayılı Amme Alacaklarının Tahsil Usulü Hakkında Kanun\'un 48. maddesi uyarınca ${_d(v('taksit'))} eşit taksitte ödenmesine izin verilmesini talep ederim.',
      'Gerekli teminatı mevzuata uygun şekilde vereceğimi bildiririm.',
    ],
  ),
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'Uzlaşma talebi',
    aciklama: 'Tarh edilen vergi veya kesilen ceza için uzlaşma görüşmesi talebi.',
    dosya: 'uzlasma_talebi',
    kurumEtiket: 'Vergi dairesi / uzlaşma komisyonu',
    kurumSon: 'Başkanlığına',
    konu: 'Uzlaşma talebi',
    ekler: const [
      _Alan('ihbarname', 'İhbarname / ceza tarihi ve sayısı'),
      _Alan('tebligTarihi', 'Tebliğ tarihi'),
      _Alan('vergi', 'Vergi türü ve dönemi'),
      _Alan('gerekce', 'Gerekçe', satir: 4),
    ],
    govde: (v) => [
      '${_d(v('tebligTarihi'))} tarihinde tebliğ edilen ${_d(v('ihbarname'))} tarihli ve sayılı ihbarname ile ${_d(v('vergi'))} için yapılan tarhiyata / kesilen cezaya ilişkin olarak uzlaşma talebinde bulunuyorum.',
      _d(v('gerekce'), ''),
      'Uzlaşma görüşmesi için gün ve saat bildirilmesini talep ederim. Talebimin yasal süre içinde yapıldığını belirtirim.',
    ],
  ),
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'İşi bırakma (faaliyet terk) bildirimi',
    aciklama: 'Faaliyetin sona erdiğini vergi dairesine bildirme dilekçesi.',
    dosya: 'isi_birakma_bildirimi',
    kurumEtiket: 'Vergi dairesi adı',
    kurumSon: 'Vergi Dairesi Müdürlüğüne',
    konu: 'İşi bırakma bildirimi',
    ekler: const [
      _Alan('bitis', 'İşi bırakma tarihi (gg.aa.yyyy)'),
      _Alan('neden', 'Neden', varsayilan: 'Faaliyetime son verilmiştir.'),
    ],
    govde: (v) => [
      'Kurumunuza kayıtlı mükellef olarak ${_d(v('bitis'))} tarihi itibarıyla işi bıraktığımı bildiririm. ${_d(v('neden'), '')}',
      'Mükellefiyet kaydımın bu tarih itibarıyla terkin edilmesini ve gerekli işlemlerin yapılmasını talep ederim. Defter, belge ve kayıtlarım yasal süre boyunca saklanacaktır.',
    ],
  ),
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'Adres / unvan değişikliği bildirimi',
    aciklama: 'İş yeri adresi veya unvan değişikliğinin vergi dairesine bildirilmesi.',
    dosya: 'adres_unvan_degisikligi',
    kurumEtiket: 'Vergi dairesi adı',
    kurumSon: 'Vergi Dairesi Müdürlüğüne',
    konu: 'Adres / unvan değişikliği bildirimi',
    ekler: const [
      _Alan('eski', 'Eski adres / unvan', satir: 2),
      _Alan('yeni', 'Yeni adres / unvan', satir: 2),
      _Alan('tarih', 'Değişiklik tarihi (gg.aa.yyyy)'),
    ],
    govde: (v) => [
      'Kayıtlarınızda yer alan eski bilgilerim: ${_d(v('eski'))}',
      '${_d(v('tarih'))} tarihi itibarıyla yeni bilgilerim: ${_d(v('yeni'))}',
      'Değişikliğin mükellefiyet kaydıma işlenmesini ve gerekli düzeltmenin yapılmasını talep ederim.',
    ],
  ),
  // ------------------------------------------------------------------ SGK
  _dilekce(
    grup: 'SGK',
    ad: 'SGK borcu yoktur belgesi talebi',
    aciklama: 'İhale, teşvik veya başka işlemler için prim borcu durumunu gösterir belge talebi.',
    dosya: 'sgk_borcu_yoktur_talebi',
    kurumEtiket: 'SGK il müdürlüğü / sosyal güvenlik merkezi',
    kurumSon: 'Müdürlüğüne',
    konu: 'Prim borcu yoktur yazısı talebi',
    ekler: const [_Alan('sicil', 'İşyeri SGK sicil no'), _Alan('amac', 'Belgenin kullanılacağı yer')],
    govde: (v) => [
      '${_d(v('sicil'))} sicil numaralı işyeri için kurumunuza prim ve idari para cezası borcu bulunup bulunmadığını gösterir belgenin ${_d(v('amac'), 'ilgili işlem')} için tarafıma verilmesini talep ederim.',
    ],
  ),
  _dilekce(
    grup: 'SGK',
    ad: 'SGK prim borcu taksit / yapılandırma talebi',
    aciklama: 'Prim borcunun yapılandırılması veya taksitlendirilmesi için başvuru dilekçesi.',
    dosya: 'sgk_taksit_talebi',
    kurumEtiket: 'SGK il müdürlüğü / sosyal güvenlik merkezi',
    kurumSon: 'Müdürlüğüne',
    konu: 'Prim borcunun taksitlendirilmesi / yapılandırılması talebi',
    ekler: const [
      _Alan('sicil', 'İşyeri SGK sicil no'),
      _Alan('borc', 'Borç dönemleri ve tutarı', satir: 2),
      _Alan('taksit', 'İstenen taksit sayısı'),
      _Alan('neden', 'Gerekçe', satir: 3),
    ],
    govde: (v) => [
      '${_d(v('sicil'))} sicil numaralı işyerimin ${_d(v('borc'))} prim borcu bulunmaktadır. ${_d(v('neden'), '')}',
      'Güncel mevzuattaki yapılandırma ve taksitlendirme imkânlarından yararlanmak istiyorum. Borcun ${_d(v('taksit'))} taksitte ödenmesine izin verilmesini ve gerekli başvuru şartlarının bildirilmesini talep ederim.',
    ],
  ),
  // ------------------------------------------------------------------ İşveren ve personel
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'Avans talep formu',
    aciklama: 'Personelin maaş avansı talebi ve geri ödeme onayı.',
    dosya: 'avans_talep_formu',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('personel', 'Personel adı soyadı'),
      _Alan('tc', 'T.C. kimlik no'),
      _Alan('gorev', 'Görevi'),
      _Alan('tutar', 'Talep edilen avans (TL)'),
      _Alan('neden', 'Talep nedeni'),
      _Alan('geriOdeme', 'Geri ödeme şekli', varsayilan: 'Bir sonraki maaşımdan kesilmesini'),
      _Alan('tarih', 'Tarih (gg.aa.yyyy)'),
    ],
    firmadan: {'isveren': (f) => f.unvan},
    icerik: (v) => [
      _baslik('AVANS TALEP FORMU'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('İşveren / işyeri: ${_d(v('isveren'))}'),
      _p('Personel: ${_d(v('personel'))}   T.C. kimlik no: ${_d(v('tc'))}   Görevi: ${_d(v('gorev'))}'),
      _p('Yukarıda bilgileri yazılı personel olarak ${_d(v('neden'), 'kişisel ihtiyaçlarım')} nedeniyle ${_d(v('tutar'))} TL avans talep ediyorum. ${_d(v('geriOdeme'))} kabul ve taahhüt ederim.'),
      _p('İşveren onayı:   Onaylanan tutar: ................ TL        Ödeme tarihi: ....../....../........', alt: 6),
    ],
    imzalar: (v) => ['PERSONEL\n${_d(v('personel'), '')}', 'İŞVEREN ONAYI\n${_d(v('isveren'), '')}'],
  ),
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'Fazla çalışma onay formu',
    aciklama: 'Personelin fazla çalışmaya yazılı onayı (İş Kanunu fazla çalışma için işçinin onayını arar).',
    dosya: 'fazla_calisma_onay_formu',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('personel', 'Personel adı soyadı'),
      _Alan('tc', 'T.C. kimlik no'),
      _Alan('gorev', 'Görevi'),
      _Alan('kapsam', 'Kapsam', satir: 3, varsayilan: 'Haftalık normal çalışma süresini aşan fazla çalışmaları, işin gerektirdiği hallerde, yılda azami yasal süreyi aşmamak üzere kabul ediyorum.'),
      _Alan('tarih', 'Tarih (gg.aa.yyyy)'),
    ],
    firmadan: {'isveren': (f) => f.unvan},
    icerik: (v) => [
      _baslik('FAZLA ÇALIŞMA ONAY FORMU'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('İşveren / işyeri: ${_d(v('isveren'))}'),
      _p('Personel: ${_d(v('personel'))}   T.C. kimlik no: ${_d(v('tc'))}   Görevi: ${_d(v('gorev'))}'),
      _p('${_d(v('kapsam'))}'),
      _p('Fazla çalışmanın her saati için ücretimin yasal zamlı tutarda ödeneceğini veya talebim halinde serbest zaman olarak kullandırılabileceğini biliyorum. Bu onayı özgür irademle veriyorum.'),
    ],
    imzalar: (v) => ['PERSONEL\n${_d(v('personel'), '')}', 'İŞVEREN\n${_d(v('isveren'), '')}'],
  ),
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'Devamsızlık ihtar yazısı',
    aciklama: 'İşe gelmeyen personele işe dönmesi için yapılan yazılı uyarı. Noter veya iadeli taahhütlü gönderilir.',
    dosya: 'devamsizlik_ihtar_yazisi',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('personel', 'Personel adı soyadı'),
      _Alan('tc', 'T.C. kimlik no'),
      _Alan('adres', 'Personelin adresi'),
      _Alan('tarihler', 'Mazeretsiz devamsızlık tarihleri', satir: 2),
      _Alan('sure', 'İşe dönmesi için süre / son tarih', varsayilan: 'bu yazının tebliğinden itibaren 2 iş günü içinde'),
      _Alan('tarih', 'Yazı tarihi (gg.aa.yyyy)'),
    ],
    firmadan: {'isveren': (f) => f.unvan},
    icerik: (v) => [
      _baslik('DEVAMSIZLIK İHTAR YAZISI'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('Sayın ${_d(v('personel'))} (T.C. kimlik no: ${_d(v('tc'))})\nAdres: ${_d(v('adres'))}', alt: 12),
      _p('İşyerimizde çalışmakta iken ${_d(v('tarihler'))} tarihlerinde, işverenden izin almaksızın ve haklı bir mazeret bildirmeksizin işinize devam etmediğiniz tespit edilmiştir.'),
      _p('Bu nedenle, ${_d(v('sure'))} işinizin başına dönmeniz, aksi halde 4857 sayılı İş Kanunu\'nun ilgili hükümleri uyarınca iş sözleşmenizin haklı nedenle feshedilebileceği ve yasal haklarınız yönünden gerekli işlemlerin yapılacağı ihtar olunur.'),
      _p('Mazeretiniz varsa belgesiyle birlikte aynı süre içinde yazılı olarak bildirmeniz gerekmektedir.', alt: 6),
    ],
    imzalar: (v) => ['İŞVEREN\n${_d(v('isveren'), '')}\n(imza / kaşe)'],
  ),
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'Savunma isteme yazısı',
    aciklama: 'Olay veya disiplin konusunda personelden yazılı savunma isteme yazısı.',
    dosya: 'savunma_isteme_yazisi',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('personel', 'Personel adı soyadı'),
      _Alan('gorev', 'Görevi'),
      _Alan('olay', 'Olayın açıklaması (tarih, yer, içerik)', satir: 4),
      _Alan('sure', 'Savunma için süre / son tarih', varsayilan: 'bu yazının tebliğinden itibaren 3 iş günü içinde'),
      _Alan('tarih', 'Yazı tarihi (gg.aa.yyyy)'),
    ],
    firmadan: {'isveren': (f) => f.unvan},
    icerik: (v) => [
      _baslik('SAVUNMA İSTEME YAZISI'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('Sayın ${_d(v('personel'))} (${_d(v('gorev'))})', alt: 12),
      _p('Aşağıda açıklanan olay hakkında yazılı savunmanız istenmektedir:'),
      _p(_d(v('olay'))),
      _p('Savunmanızı ${_d(v('sure'))} işyerimize yazılı olarak vermeniz gerekmektedir. Belirtilen süre içinde savunma verilmemesi halinde değerlendirmenin mevcut bilgi ve belgelere göre yapılacağı hatırlatılır.', alt: 6),
    ],
    imzalar: (v) => ['İŞVEREN\n${_d(v('isveren'), '')}', 'TEBELLÜĞ EDEN\n${_d(v('personel'), '')}\n(tarih / imza)'],
  ),
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'Zimmet teslim formu',
    aciklama: 'Personele teslim edilen telefon, bilgisayar, araç gibi eşyaların imzalı zimmet formu.',
    dosya: 'zimmet_teslim_formu',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('personel', 'Teslim alan personel'),
      _Alan('tc', 'T.C. kimlik no'),
      _Alan('gorev', 'Görevi'),
      _Alan('liste', 'Zimmetlenen eşyalar (her satıra bir eşya, seri no)', satir: 5),
      _Alan('tarih', 'Teslim tarihi (gg.aa.yyyy)'),
    ],
    firmadan: {'isveren': (f) => f.unvan},
    icerik: (v) => [
      _baslik('ZİMMET TESLİM FORMU'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('İşveren / işyeri: ${_d(v('isveren'))}'),
      _p('Teslim alan: ${_d(v('personel'))}   T.C. kimlik no: ${_d(v('tc'))}   Görevi: ${_d(v('gorev'))}'),
      _p('Aşağıda belirtilen eşyaları sağlam ve çalışır durumda teslim aldım:'),
      _p(_d(v('liste'))),
      _p('Bu eşyaları özenle kullanacağımı, iş dışı amaçla kullanmayacağımı, kaybı veya hasarı halinde işvereni derhal bilgilendireceğimi ve iş sözleşmem sona erdiğinde eksiksiz geri teslim edeceğimi kabul ve taahhüt ederim.', alt: 6),
    ],
    imzalar: (v) => ['TESLİM EDEN\n${_d(v('isveren'), '')}', 'TESLİM ALAN\n${_d(v('personel'), '')}'],
  ),
  // ------------------------------------------------------------------ Genel
  _Belge(
    grup: 'Genel',
    ad: 'Vekâletname',
    aciklama: 'Mali müşavire vergi dairesi, SGK ve diğer kurum işlemleri için vekâlet taslağı. Kurumlar noter onayı isteyebilir.',
    dosya: 'vekaletname',
    taraf: 'muvekkil',
    alanlar: const [
      _Alan('muvekkil', 'Müvekkil (ad soyad / unvan)'),
      _Alan('muvekkilNo', 'Müvekkil T.C. / vergi no'),
      _Alan('muvekkilAdres', 'Müvekkil adresi'),
      _Alan('vekil', 'Vekil (ad soyad)', varsayilan: 'SMMM Erkan Uçar'),
      _Alan('vekilNo', 'Vekil T.C. / SMMM sicil no'),
      _Alan('vekilAdres', 'Vekil adresi'),
      _Alan('yetki', 'Yetkiler', satir: 7, varsayilan: 'Vergi daireleri, Sosyal Güvenlik Kurumu, Gelir İdaresi Başkanlığı, belediyeler ve diğer resmî kurumlar nezdinde müvekkilin vergi, SGK ve işyeri işlemlerini yürütmeye; beyanname, bildirge ve dilekçeleri düzenleyip imzalamaya ve vermeye; tahakkuk ve tebligatları teslim almaya; ödeme yapmaya ve makbuz almaya; itiraz, uzlaşma ve pişmanlıkla beyan işlemlerini yapmaya; gerekli gördüğü kişilere vekâlet devrine yetkilidir.'),
      _Alan('sure', 'Geçerlilik süresi', varsayilan: 'Geri alınıncaya kadar'),
      _Alan('tarih', 'Düzenleme tarihi (gg.aa.yyyy)'),
    ],
    firmadan: {
      'muvekkil': (f) => f.unvan,
      'muvekkilNo': (f) => f.vergiNo.isNotEmpty ? f.vergiNo : f.tcNo,
      'muvekkilAdres': (f) => f.adres,
    },
    icerik: (v) => [
      _baslik('VEKÂLETNAME'),
      _p('MÜVEKKİL: ${_d(v('muvekkil'))}, T.C./Vergi no: ${_d(v('muvekkilNo'))}, adres: ${_d(v('muvekkilAdres'))}.'),
      _p('VEKİL: ${_d(v('vekil'))}, T.C./SMMM sicil no: ${_d(v('vekilNo'))}, adres: ${_d(v('vekilAdres'))}.'),
      _p('YETKİLER: Müvekkil olarak yukarıda adı geçen vekilimi aşağıdaki konularda temsile yetkili kıldım: ${_d(v('yetki'))}'),
      _p('SÜRE: Bu vekâletname ${_d(v('sure'))} geçerlidir. Düzenleme tarihi: ${_d(v('tarih'), _tarihNokta)}.', alt: 8),
      pw.Text('Bu belge taslaktır. Kurumlar noter onaylı vekâletname isteyebilir; kullanımdan önce noter tasdiki ve ilgili kurumun şartları kontrol edilmelidir.',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
    ],
    imzalar: (v) => ['MÜVEKKİL\n${_d(v('muvekkil'), '')}'],
  ),
  _Belge(
    grup: 'Genel',
    ad: 'Cari hesap mutabakat mektubu',
    aciklama: 'Karşı firmaya bakiye mutabakatı isteyen yazı; karşı tarafın cevap bölümü de yer alır.',
    dosya: 'cari_mutabakat_mektubu',
    taraf: 'gonderen',
    alanlar: const [
      _Alan('gonderen', 'Mutabakat isteyen firma'),
      _Alan('alici', 'Karşı firma'),
      _Alan('aliciAdres', 'Karşı firma adresi / yetkilisi'),
      _Alan('bakiyeTarihi', 'Bakiye tarihi (gg.aa.yyyy)'),
      _Alan('tutar', 'Bakiye tutarı (TL)'),
      _Alan('durum', 'Bakiye durumu', varsayilan: 'borç'),
      _Alan('sure', 'Cevap için süre', varsayilan: '7 gün'),
      _Alan('tarih', 'Mektup tarihi (gg.aa.yyyy)'),
    ],
    firmadan: {'gonderen': (f) => f.unvan},
    icerik: (v) => [
      _baslik('CARİ HESAP MUTABAKAT MEKTUBU'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('Sayın ${_d(v('alici'))}\n${_d(v('aliciAdres'), '')}', alt: 12),
      _p('Kayıtlarımıza göre ${_d(v('bakiyeTarihi'))} tarihi itibarıyla firmanızın ${_d(v('tutar'))} TL ${_d(v('durum'))} bakiyesi görünmektedir. Kendi kayıtlarınızla karşılaştırarak mutabık olup olmadığınızı ${_d(v('sure'))} içinde yazılı bildirmenizi rica ederiz.'),
      _p('Belirtilen süre içinde cevap alınamazsa bakiyenin doğru olduğu kabul edilmiş sayılır.', alt: 14),
      _p('CEVAP BÖLÜMÜ (karşı firma tarafından doldurulacaktır)', kalin: true, alt: 6),
      _p('[   ] Bakiye ile MUTABIKIZ.\n[   ] Bakiye ile MUTABIK DEĞİLİZ. Kayıtlarımıza göre bakiyemiz: ................ TL    Farkın nedeni: ..................................................', alt: 6),
    ],
    imzalar: (v) => ['${_d(v('gonderen'), 'GÖNDEREN FİRMA')}\n(imza / kaşe)', '${_d(v('alici'), 'KARŞI FİRMA')}\n(imza / kaşe)'],
  ),

  // ------------------------------------------------------------------ Vergi dairesi: elektronik hizmet formları
  _Belge(
    grup: 'Vergi dairesi',
    ad: 'Elektronik beyanname gönderme talep formu ve taahhütnamesi (Ek-1)',
    aciklama: 'Beyannameleri elektronik ortamda göndermek için kullanıcı kodu, parola ve şifre talebi.',
    dosya: 'elektronik_beyanname_talep_ek1',
    taraf: 'ad',
    alanlar: const [
      _Alan('kurum', 'Vergi dairesi adı'),
      _Alan('tarih', 'Tarih (gg.aa.yyyy)'),
      _Alan('vkn', 'Vergi kimlik numarası'),
      _Alan('tc', 'T.C. kimlik numarası'),
      _Alan('ad', 'Adı soyadı / unvanı'),
      _Alan('ticaretSicil', 'Ticaret sicil no'),
      _Alan('dogumYeri', 'Doğum yeri / tüzel kişilerde kanuni merkezi'),
      _Alan('dogumTarihi', 'Doğum tarihi / tüzel kişilerde kuruluş tarihi'),
      _Alan('adres', 'Adresi', satir: 2),
      _Alan('oda', 'Bağlı olduğu oda ve sicil no'),
      _Alan('tel', 'Telefon numarası'),
      _Alan('faks', 'Faks numarası'),
      _Alan('eposta', 'Elektronik posta adresi'),
      _Alan('temsilci', 'Mükellef / kanuni temsilci adı soyadı'),
    ],
    firmadan: _firmaForm,
    icerik: (v) => [
      _p('EK: 1', hiza: pw.TextAlign.right, alt: 4),
      _baslik('ELEKTRONİK BEYANNAME GÖNDERME TALEP FORMU VE TAAHHÜTNAMESİ'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('${_buyuk(_d(v('kurum'), '.....................'))} VERGİ DAİRESİ MÜDÜRLÜĞÜNE', kalin: true, hiza: pw.TextAlign.center, alt: 12),
      _p('Beyannamelerimi elektronik ortamda göndermek istiyorum. Talebimin değerlendirilmesini ve tarafıma parola, kullanıcı kodu ve kullanıcı şifresi verilmesini arz ederim.'),
      _altBaslik('MÜKELLEF KİMLİK / ADRES BİLGİLERİ'),
      _formTablo([
        ('Vergi kimlik numarası', _d(v('vkn'), '')),
        ('T.C. kimlik numarası', _d(v('tc'), '')),
        ('Adı, soyadı / unvanı', _d(v('ad'), '')),
        ('Ticaret sicil no', _d(v('ticaretSicil'), '')),
        ('Doğum yeri / tüzel kişilerde kanuni merkezi', _d(v('dogumYeri'), '')),
        ('Doğum tarihi / tüzel kişilerde kuruluş tarihi', _d(v('dogumTarihi'), '')),
        ('Adresi', _d(v('adres'), '')),
        ('Bağlı bulunduğu oda ve sicil no', _d(v('oda'), '')),
        ('Telefon numarası', _d(v('tel'), '')),
        ('Faks numarası', _d(v('faks'), '')),
        ('Elektronik posta adresi', _d(v('eposta'), '')),
      ]),
      _p('Tarafıma elektronik beyanname gönderme yetkisinin verilmesi halinde;', alt: 6),
      _p('1. Bakanlık tarafından beyannamelerin elektronik ortamda gönderilmesi ile ilgili yayımlanan genel tebliğ ve diğer ilgili düzenlemelerle getirilecek usul ve esasların tümüne uyacağımı,', alt: 5),
      _p('2. Tarafıma verilmiş kullanıcı kodu, parola ve şifreden sorumlu olduğumu ve herhangi bir üçüncü kişiye açıklamayacağımı ve kullanımına izin vermeyeceğimi, kullanıcı kodu, parola ve şifreyi başka amaçlarla kullanmayacağımı, işyerimin satışı, transferi ve işi bırakmada kullanıcı kodu, parola ve şifremi kimseye devretmeyeceğimi, kiralayamayacağımı ve satmayacağımı, almış olduğum kullanıcı kodu, parola ve şifrem ile başkaları tarafından işlem yapıldığını öğrendiğim anda Gelir İdaresi Başkanlığı Çağrı Merkezine (444 0 435) veya bağlı olduğum vergi dairesine bildireceğimi,', alt: 5),
      _p('3. Kullanıcı kodu, parola ve şifrenin kullanımı suretiyle yapılan işlemlerin, kendim veya yetkili kişilerce yapılmadığı yönünde bir iddia ileri sürmeyeceğimi ve tüm kullanımlardan sorumlu olduğumu, kullanıcı kodu, parola ve şifrenin yetkisiz kişilerce kullanıldığını öğrendiğim anda (şifrenin, parolanın ve kodun kaybedilmesi, çalınması vb. durumlar dahil) Çağrı Merkezine veya bağlı olduğum vergi dairesine bildireceğimi, bu bildirim anına kadar yapılan işlemlerden ve kullanımdan bizzat sorumlu olacağımı,', alt: 5),
      _p('4. Elektronik ortamda yapılan işlemlerin tespit ve tevsikinde ilgili vergi dairesi ve Gelir İdaresi Başkanlığı bilgi işlem kayıtlarının esas alınacağını,', alt: 5),
      _p('5. Kullanıcı kodu, parola ve şifre kullanılarak düzenlenen ve tarafımca onaylanarak manyetik ortamda gönderilen bildirim ve beyannamelerin tarafımdan imzalanmış sayılacağını,', alt: 5),
      _p('kabul ve taahhüt ediyorum.', alt: 10),
      _p('Mükellef / kanuni temsilci: ${_d(v('temsilci'))}', alt: 4),
    ],
    imzalar: (v) => ['MÜKELLEF / KANUNİ TEMSİLCİ\n${_d(v('temsilci'), '')}'],
  ),
  _Belge(
    grup: 'Vergi dairesi',
    ad: 'Elektronik tebligat talep bildirimi (Ek-2)',
    aciklama: 'Tebligatların elektronik ortamda yapılması için vergi dairesine başvuru formu.',
    dosya: 'elektronik_tebligat_talep_ek2',
    taraf: 'ad',
    alanlar: const [
      _Alan('kurum', 'Vergi dairesi adı'),
      _Alan('tc', 'T.C. kimlik numarası'),
      _Alan('vkn', 'Vergi kimlik numarası'),
      _Alan('ad', 'Adı soyadı / unvanı'),
      _Alan('dogumYeri', 'Doğum yeri'),
      _Alan('dogumTarihi', 'Doğum tarihi'),
      _Alan('tel', 'Telefon numarası'),
      _Alan('faks', 'Faks numarası'),
      _Alan('cep1', 'Cep telefonu 1'),
      _Alan('cep2', 'Cep telefonu 2'),
      _Alan('eposta', 'E-posta adresi 1'),
      _Alan('eposta2', 'E-posta adresi 2'),
      _Alan('adres', 'Adres', satir: 2),
      _Alan('diger', 'Diğer iletişim bilgileri'),
      _Alan('tercih', 'Bilgilendirme tercihi (Kısa mesaj, E-posta)', varsayilan: 'Kısa mesaj, E-posta'),
      _Alan('sifre', 'Daha önce İnternet Vergi Dairesi şifresi var mı (Evet / Hayır)', varsayilan: 'Evet'),
      _Alan('tarih', 'Tarih (gg.aa.yyyy)'),
    ],
    firmadan: _firmaForm,
    icerik: (v) => [
      _p('${_buyuk(_d(v('kurum'), '.....................'))} VERGİ DAİRESİ BAŞKANLIĞI / MÜDÜRLÜĞÜ\'NE', kalin: true, hiza: pw.TextAlign.center, alt: 12),
      _baslik('ELEKTRONİK TEBLİGAT TALEP BİLDİRİMİ'),
      _altBaslik('MÜKELLEF BİLGİLERİ'),
      _formTablo([
        ('T.C. kimlik numarası', _d(v('tc'), '')),
        ('Vergi kimlik numarası', _d(v('vkn'), '')),
        ('Adı / soyadı (unvanı)', _d(v('ad'), '')),
        ('Doğum yeri', _d(v('dogumYeri'), '')),
        ('Doğum tarihi', _d(v('dogumTarihi'), '')),
        ('Telefon numarası', _d(v('tel'), '')),
        ('Faks numarası', _d(v('faks'), '')),
        ('Cep telefonu', '1. ${_d(v('cep1'), '')}\n2. ${_d(v('cep2'), '')}'),
        ('E-posta adresi', '1. ${_d(v('eposta'), '')}\n2. ${_d(v('eposta2'), '')}'),
        ('Adres', _d(v('adres'), '')),
        ('Diğer iletişim bilgileri', _d(v('diger'), '')),
      ]),
      _altBaslik('BİLGİLENDİRME TERCİHLERİ'),
      _p(_d(v('tercih'), 'Kısa mesaj servisi / E-posta'), alt: 10),
      _p('Elektronik tebligat sisteminin kullanımına ilişkin olarak;', alt: 5),
      _p('- İnternet ortamında elektronik tebligat alma ve bilgileri sorgulama işlemleri için Gelir İdaresi Başkanlığı tarafından verilen, istenildiğinde değiştirilebilecek olan kullanıcı kodu ve kişisel şifrenin gizlilik ve güvenliğinin sağlanması, korunması ve yetkisiz kişiler tarafından kullanılması gibi sorumlulukların tarafıma ait olduğunu,', alt: 4),
      _p('- Başkanlığın elektronik tebligata ilişkin olarak sunduğu altyapı ve yazılım sistemlerini zarara uğratacak, güvenliğini zedeleyecek veya sağlıklı çalışmasını engelleyecek hususların oluşmaması için Başkanlık tarafından belirlenecek her türlü teknik ve idari önlemin alınacağını,', alt: 4),
      _p('- Herhangi bir aksaklık olmaması için bütün tedbirleri alacağımı, buna rağmen oluşan ihtilaflarda Gelir İdaresi Başkanlığı tarafından oluşturulan kayıtların esas alınacağını,', alt: 4),
      _p('- Unutulmuş, çalınmış veya kaybedilmiş olan kullanıcı kodu ve kişisel şifremden, bunların üçüncü kişiler tarafından kullanılmasından ve sonuçlarından hiçbir şekilde Gelir İdaresi Başkanlığı\'nın sorumlu olmadığını kabul ediyorum.', alt: 4),
      _p('- Yukarıda beyan edilen kişisel bilgilerin ve diğer bilgilerin doğruluğunu kabul ve beyan ederim.', alt: 8),
      if (v('sifre').trim().toLowerCase().startsWith('e'))
        _p('[X] Daha önceden İnternet Vergi Dairesi kullanıcı kodu ve şifrem bulunması nedeniyle; şifremi elektronik tebligat alma işlemlerinde de kullanmak istiyorum.', alt: 8),
      _p('Adı soyadı: ${_d(v('ad'))}\nTarih: ${_d(v('tarih'), _tarihNokta)}', alt: 4),
    ],
    imzalar: (v) => ['${_d(v('ad'), '')}\n(imza)'],
  ),
  _Belge(
    grup: 'Vergi dairesi',
    ad: 'İnternet hizmetleri kullanım başvuru formu (tüzel kişiler)',
    aciklama: 'Tüzel kişilerin internet vergi dairesi, bildirim ve beyanname gönderme başvurusu.',
    dosya: 'internet_hizmetleri_basvuru_tuzel',
    taraf: 'unvan',
    alanlar: const [
      _Alan('kurum', 'Vergi dairesi adı'),
      _Alan('tarih', 'Tarih (gg.aa.yyyy)'),
      _Alan('yetkili', 'Kurum yetkilisinin adı soyadı'),
      _Alan('yetkiliVkn', 'Kurum yetkilisinin vergi kimlik no / T.C.'),
      _Alan('vkn', 'Kurum vergi kimlik numarası'),
      _Alan('unvan', 'Unvanı'),
      _Alan('kurulusYeri', 'Kuruluş yeri'),
      _Alan('kurulusTarihi', 'Kuruluş tarihi'),
      _Alan('ticaretSicil', 'Ticaret sicil numarası'),
      _Alan('tescilTarihi', 'Tescil tarihi'),
      _Alan('tel', 'Telefon numarası'),
      _Alan('faks', 'Faks numarası'),
      _Alan('eposta', 'E-posta adresi'),
      _Alan('adres', 'Adres', satir: 2),
    ],
    firmadan: {..._firmaForm, 'unvan': (f) => f.unvan},
    icerik: (v) => [
      _baslik('İNTERNET HİZMETLERİ KULLANIM BAŞVURU FORMU\n(TÜZEL KİŞİLER)'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('${_buyuk(_d(v('kurum'), '.....................'))} VERGİ DAİRESİ MÜDÜRLÜĞÜ\'NE / BAŞKANLIĞI\'NA', kalin: true, hiza: pw.TextAlign.center, alt: 12),
      _p('Aşağıda kimlik bilgileri bulunan firmamızın / kurumumuzun internet üzerinden vergi bilgileri sorgulama işlemlerini yapabilmesi, bildirim ve beyanname gönderebilmesi için gereğini arz ederiz.'),
      _formTablo([
        ('Kurum yetkilisinin adı, soyadı', _d(v('yetkili'), '')),
        ('Vergi kimlik numarası', _d(v('yetkiliVkn'), '')),
      ]),
      _altBaslik('KURUM BİLGİLERİ'),
      _formTablo([
        ('Vergi kimlik numarası', _d(v('vkn'), '')),
        ('Unvanı', _d(v('unvan'), '')),
        ('Kuruluş yeri', _d(v('kurulusYeri'), '')),
        ('Kuruluş tarihi', _d(v('kurulusTarihi'), '')),
        ('Ticaret sicil numarası', _d(v('ticaretSicil'), '')),
        ('Tescil tarihi', _d(v('tescilTarihi'), '')),
        ('Telefon numarası', _d(v('tel'), '')),
        ('Faks numarası', _d(v('faks'), '')),
        ('E-posta adresi', _d(v('eposta'), '')),
        ('Adres', _d(v('adres'), '')),
      ]),
      _p('İnternet ortamında verilen bilgileri sorgulama işlemleri için Gelir İdaresi Başkanlığı tarafından verilen ve tarafımızca değiştirilebilecek olan kullanıcı kodu ve kişisel şifrenin korunması ve her türlü riskinin tarafımıza ait olduğunu, Gelir İdaresi Başkanlığı\'nın herhangi bir sorumluluğunun bulunmadığını, unutulmuş, çalınmış veya kaybedilmiş olan kullanıcı kodu ve kişisel şifremden, bunların üçüncü kişiler tarafından kullanılmasından ve sonuçlarından hiçbir şekilde sorumlu olmadığını kabul ediyoruz.'),
      _p('Bu kullanıcı kodu ve kişisel şifre kullanılarak düzenlenen ve tarafımızca onaylanarak manyetik ortamda gönderilen bildirim ve beyannamelerin doğruluğunu, bunları Gelir İdaresi Başkanlığı bilgisayar sistemleri tarih ve saatini esas alarak göndermeyi kabul ve taahhüt ediyoruz.', alt: 10),
    ],
    imzalar: (v) => ['KURUM YETKİLİSİ\n${_d(v('yetkili'), '')}'],
  ),
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'Pişmanlıkla beyan dilekçesi',
    aciklama: 'Süresinde verilmeyen veya eksik verilen beyanname için pişmanlık talebi (213 sayılı VUK m.371).',
    dosya: 'pismanlik_dilekcesi',
    kurumEtiket: 'Vergi dairesi adı',
    kurumSon: 'Vergi Dairesi Müdürlüğüne',
    konu: 'Pişmanlıkla beyan talebi',
    ekler: const [
      _Alan('donem', 'Vergi türü ve dönemi'),
      _Alan('neden', 'Beyan edilmeme nedeni', satir: 3),
    ],
    govde: (v) => [
      '${_d(v('donem'))} dönemine ilişkin beyannamemi yasal süresi içinde veremedim / eksik verdim. ${_d(v('neden'), '')}',
      '213 sayılı Vergi Usul Kanunu\'nun 371. maddesi uyarınca, haber verilmeden önce kendiliğinden beyanda bulunduğumdan pişmanlıkla beyan hükümlerinden yararlanmak istiyorum. Beyannameyi ekte sunuyorum; hesaplanacak vergiyi ve gecikme faizini yasal sürede ödeyeceğimi bildiririm.',
    ],
  ),
  _dilekce(
    grup: 'Vergi dairesi',
    ad: 'Mükellefiyet / vergi levhası yazısı talebi',
    aciklama: 'Banka, kurum veya ihale için mükellefiyet durumunu gösterir yazı talebi.',
    dosya: 'mukellefiyet_yazisi_talebi',
    kurumEtiket: 'Vergi dairesi adı',
    kurumSon: 'Vergi Dairesi Müdürlüğüne',
    konu: 'Mükellefiyet yazısı / vergi levhası talebi',
    ekler: const [_Alan('amac', 'Yazının verileceği yer / amaç')],
    govde: (v) => [
      'Vergi dairenize kayıtlı mükellef olarak ${_d(v('amac'), 'ilgili işlemler')} için mükellefiyet durumumu, faaliyet konumu ve adresimi gösterir yazının / vergi levhası örneğinin tarafıma verilmesini talep ederim.',
    ],
  ),
  // ------------------------------------------------------------------ SGK
  _dilekce(
    grup: 'SGK',
    ad: 'SGK sistem şifresi / e-Bildirge yetki talebi',
    aciklama: 'İşyeri sistem şifresi veya yetkilendirme için başvuru dilekçesi.',
    dosya: 'sgk_sistem_sifre_talebi',
    kurumEtiket: 'SGK il müdürlüğü / sosyal güvenlik merkezi',
    kurumSon: 'Müdürlüğüne',
    konu: 'İşyeri sistem şifresi ve bildirim yetkisi talebi',
    ekler: const [
      _Alan('sicil', 'İşyeri SGK sicil no'),
      _Alan('yetkili', 'Yetkilendirilecek kişi (ad soyad, T.C. no)'),
    ],
    govde: (v) => [
      '${_d(v('sicil'))} sicil numaralı işyerimin sigortalı bildirimlerini elektronik ortamda yapabilmek üzere işyeri sistem şifresinin / yetkilendirmenin ${_d(v('yetkili'))} adına verilmesini talep ederim.',
      'İşyeri sicil numarası ve kimlik bilgilerimi içeren belgeler ekte sunulmuştur.',
    ],
  ),
  _Belge(
    grup: 'SGK',
    ad: 'İş kazası tutanağı',
    aciklama: 'İş kazası olduğunda olay yerinde düzenlenen tutanak. Kaza bildirimi ayrıca yasal süresinde SGK\'ya yapılmalıdır.',
    dosya: 'is_kazasi_tutanagi',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('sicil', 'İşyeri SGK sicil no'),
      _Alan('adres', 'İşyeri adresi'),
      _Alan('personel', 'Kazazede adı soyadı'),
      _Alan('tc', 'T.C. kimlik no'),
      _Alan('gorev', 'Görevi'),
      _Alan('tarih', 'Kaza tarihi (gg.aa.yyyy)'),
      _Alan('saat', 'Kaza saati'),
      _Alan('yer', 'Kaza yeri'),
      _Alan('olay', 'Kazanın oluş şekli', satir: 4),
      _Alan('yaralanma', 'Yaralanma / sonuç', satir: 2),
      _Alan('tedavi', 'Sevk edilen sağlık kuruluşu ve saati'),
      _Alan('sahit1', 'Tanık 1 (ad soyad, görevi)'),
      _Alan('sahit2', 'Tanık 2 (ad soyad, görevi)'),
    ],
    firmadan: _firmaIsveren,
    icerik: (v) => [
      _baslik('İŞ KAZASI TUTANAĞI'),
      _formTablo([
        ('İşveren / işyeri unvanı', _d(v('isveren'), '')),
        ('İşyeri SGK sicil no', _d(v('sicil'), '')),
        ('İşyeri adresi', _d(v('adres'), '')),
        ('Kazazede adı soyadı', _d(v('personel'), '')),
        ('T.C. kimlik no', _d(v('tc'), '')),
        ('Görevi', _d(v('gorev'), '')),
        ('Kaza tarihi ve saati', '${_d(v('tarih'), _tarihNokta)}  ${_d(v('saat'), '..:..')}'),
        ('Kaza yeri', _d(v('yer'), '')),
      ]),
      _altBaslik('KAZANIN OLUŞ ŞEKLİ'),
      _p(_d(v('olay'))),
      _altBaslik('YARALANMA / SONUÇ'),
      _p(_d(v('yaralanma'))),
      _p('Sağlık kuruluşuna sevk: ${_d(v('tedavi'))}'),
      _p('İşbu tutanak, kazanın yukarıda belirtilen şekilde meydana geldiğini göstermek üzere, aşağıda adı yazılı kişilerce birlikte düzenlenmiş ve imza altına alınmıştır.', alt: 8),
      _p('Tanıklar: 1) ${_d(v('sahit1'))}\n2) ${_d(v('sahit2'))}', alt: 4),
    ],
    imzalar: (v) => ['İŞVEREN / VEKİLİ\n${_d(v('isveren'), '')}', 'KAZAZEDE\n${_d(v('personel'), '')}', 'TANIKLAR\n.................'],
  ),
  // ------------------------------------------------------------------ İşveren ve personel: tutanaklar
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'Devamsızlık tutanağı',
    aciklama: 'Personelin izinsiz ve mazeretsiz işe gelmediğini gösteren, tanıklarla imzalanan tutanak.',
    dosya: 'devamsizlik_tutanagi',
    taraf: 'personel',
    alanlar: const [
      _Alan('tarih', 'Tutanak tarihi (gg.aa.yyyy)'),
      _Alan('isveren', 'İşyeri / şirket unvanı'),
      _Alan('personel', 'Personel adı soyadı'),
      _Alan('tc', 'T.C. kimlik no'),
      _Alan('gorev', 'Görevi'),
      _Alan('devamsizTarih', 'İşe gelmediği tarih (gg.aa.yyyy)'),
      _Alan('mesai', 'Mesai başlangıç saati', varsayilan: '09:00'),
      _Alan('ulasim', 'Ulaşım durumu', satir: 2, varsayilan: 'Kendisine ulaşılamamıştır.'),
      _Alan('d1', 'Düzenleyen 1: ad soyad'),
      _Alan('d1g', 'Düzenleyen 1: görevi'),
      _Alan('d2', 'Düzenleyen 2: ad soyad'),
      _Alan('d2g', 'Düzenleyen 2: görevi'),
    ],
    firmadan: _firmaIsveren,
    icerik: (v) => [
      _baslik('DEVAMSIZLIK TUTANAĞI'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('İşbu tutanak, aşağıda bilgileri yer alan personelin işe izinsiz ve mazeretsiz olarak gelmemesi nedeniyle düzenlenmiştir.'),
      _altBaslik('Personelin'),
      _formTablo([
        ('Adı soyadı', _d(v('personel'), '')),
        ('T.C. kimlik no', _d(v('tc'), '')),
        ('Görevi', _d(v('gorev'), '')),
      ]),
      _p('Yukarıda bilgileri yer alan ${_d(v('isveren'), 'şirketimiz')} personeli, ${_d(v('devamsizTarih'), _tarihNokta)} tarihinde, mesai başlangıç saati olan ${_d(v('mesai'), '..:..')} itibarıyla iş başında bulunması gerekirken, herhangi bir bilgi vermeksizin ve izin almaksızın işine gelmemiştir. ${_d(v('ulasim'), '')}'),
      _p('Personelin devamsızlığı ile ilgili gerekli savunmasının alınması ve işveren tarafından değerlendirilmesi gerekmektedir.'),
      _p('İşbu tutanak, personelin görev yerinde bulunmadığının tespiti üzerine, aşağıda isimleri belirtilen şahitler huzurunda imza altına alınmıştır.', alt: 12),
      _p('Düzenleyenler:', kalin: true, alt: 6),
      _formTablo([
        ('Adı soyadı / görevi (1)', '${_d(v('d1'), '')}  -  ${_d(v('d1g'), '')}'),
        ('Adı soyadı / görevi (2)', '${_d(v('d2'), '')}  -  ${_d(v('d2g'), '')}'),
      ]),
    ],
    imzalar: (v) => ['${_d(v('d1'), 'DÜZENLEYEN 1')}\n${_d(v('d1g'), '')}', '${_d(v('d2'), 'DÜZENLEYEN 2')}\n${_d(v('d2g'), '')}'],
  ),
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'İşyerinin geç açılması: disiplin tutanağı ve yazılı savunma isteme',
    aciklama: 'Geç açılan işyeri için tespit, yazılı savunma isteme, savunma, tebliğ ve tanık imza bölümlerinden oluşan tek form.',
    dosya: 'gec_acilma_disiplin_tutanagi',
    taraf: 'calisan',
    alanlar: const [
      _Alan('isveren', 'İşveren / işveren vekili'),
      _Alan('isyeri', 'İşyeri unvanı'),
      _Alan('adres', 'İşyeri adresi'),
      _Alan('calisan', 'Çalışanın adı soyadı'),
      _Alan('gorev', 'Görevi / unvanı'),
      _Alan('tarih', 'Tutanak tarihi (gg.aa.yyyy)'),
      _Alan('acilis', 'Normal açılış saati', varsayilan: '09:00'),
      _Alan('olayTarih', 'Olay tarihi (gg.aa.yyyy)'),
      _Alan('tespitSaat', 'Tespit saati (işyeri hâlâ kapalı)'),
      _Alan('sorumlu', 'Açılıştan sorumlu çalışan'),
      _Alan('etki', 'Çalışma düzenine etkisi', satir: 3),
      _Alan('sure', 'Savunma için süre (iş günü)', varsayilan: '3'),
      _Alan('t1', 'Tutanak düzenleyen / tanık 1 (ad soyad, görevi)'),
      _Alan('t2', 'Tutanak düzenleyen / tanık 2 (ad soyad, görevi)'),
    ],
    firmadan: {'isyeri': (f) => f.unvan, 'adres': (f) => f.adres},
    icerik: (v) => [
      _baslik('İŞYERİNİN GEÇ AÇILMASI NEDENİYLE DİSİPLİN TUTANAĞI\nVE YAZILI SAVUNMA İSTEMİ'),
      _formTablo([
        ('İşveren / işveren vekili', _d(v('isveren'), '')),
        ('İşyeri unvanı', _d(v('isyeri'), '')),
        ('İşyeri adresi', _d(v('adres'), '')),
        ('Çalışanın adı soyadı', _d(v('calisan'), '')),
        ('Görevi / unvanı', _d(v('gorev'), '')),
        ('Tutanak tarihi', _d(v('tarih'), _tarihNokta)),
      ]),
      _altBaslik('1. OLAYIN TESPİTİ'),
      _p('İşyerinin çalışma düzenine göre normal açılış saatinin ${_d(v('acilis'), '09:00')} olduğu, ${_d(v('olayTarih'), _tarihNokta)} tarihinde işyerinin bu saatte açılmadığı ve yapılan kontrolde saat ${_d(v('tespitSaat'), '........')} itibarıyla işyerinin halen kapalı olduğu tespit edilmiştir.'),
      _p('Yapılan tespitte, işyerinin açılmasından ve çalışma faaliyetinin zamanında başlatılmasından sorumlu olan çalışanın ${_d(v('sorumlu'))} olduğu belirlenmiştir.'),
      _p('Söz konusu durumun işyerinin çalışma düzeninin aksamasına ve/veya hizmetin zamanında başlatılamamasına neden olup olmadığı aşağıdaki şekilde tespit edilmiştir:\n${v('etki').trim().isEmpty ? _cizgi(3) : v('etki').trim()}'),
      _altBaslik('2. ÇALIŞANDAN YAZILI SAVUNMA İSTEMİ'),
      _p('Yukarıda belirtilen tespit kapsamında; işyerinin belirlenen çalışma saatinde açılmaması ve görev kapsamında bulunan işin zamanında yerine getirilmemesi hususunda, olayın nedenleri ile varsa geçerli mazeret ve açıklamalarınızın yazılı olarak bildirilmesi istenmektedir.'),
      _p('İşbu savunma isteminin tarafınıza tebliğinden itibaren ${_d(v('sure'), '......')} iş günü içerisinde yazılı savunmanızı işverene / işveren vekiline sunmanız gerekmektedir. Varsa olayla ilgili belge ve diğer delillerinizi savunmanıza ekleyebilirsiniz.'),
      _p('Belirtilen süre içerisinde savunma verilmemesi halinde, savunma verme hakkından vazgeçmiş sayılacağınız hususu ayrıca değerlendirilerek işverenin mevcut bilgi ve belgeler üzerinden işlem yapabileceği tarafınıza bildirilmiştir.'),
      _altBaslik('3. ÇALIŞANIN YAZILI SAVUNMASI'),
      _p('Olayla ilgili savunmam aşağıdaki gibidir:\n${_cizgi(6)}'),
      _p('Çalışanın beyanı: Yukarıdaki savunmam tarafımdan okunmuş / tarafıma okunmuş olup doğrudur.\nÇalışan: ${_d(v('calisan'))}        İmza: ______________  Tarih: ____/____/______\nİşveren / işveren vekili: ${_d(v('isveren'))}        İmza: ______________  Tarih: ____/____/______'),
      _altBaslik('4. TUTANAK DÜZENLEYEN / TANIKLAR'),
      _formTablo([
        ('1) Ad soyad / görevi / imza', _d(v('t1'), '')),
        ('2) Ad soyad / görevi / imza', _d(v('t2'), '')),
      ]),
      _altBaslik('5. ÇALIŞANIN TEBELLÜĞÜ'),
      _p('İşbu tutanak ve yazılı savunma istemi tarafıma tebliğ edilmiş olup, savunmamı belirtilen süre içerisinde sunacağım.\nÇalışanın adı soyadı: ${_d(v('calisan'))}\nTebliğ tarihi: ____ / ____ / ______    İmza: ________________'),
      _altBaslik('İŞVERENİN DEĞERLENDİRMESİ / DİSİPLİN İŞLEMİ'),
      _p('Savunmanın alınmasından sonra, olayın niteliği, çalışanın görev ve sorumlulukları, varsa mazereti, önceki benzer olaylar ve işyeri uygulamaları birlikte değerlendirilerek gerekli işveren işlemi ayrıca belirlenir.'),
      pw.Text('Önemli not: Bu tutanak olayın tespiti ve savunma alınması amacıyla hazırlanmıştır. Disiplin cezası veya fesih işlemi uygulanacaksa somut olayın özellikleri, iş sözleşmesi, işyeri düzenlemeleri ve 4857 sayılı İş Kanunu hükümleri ayrıca değerlendirilmelidir.',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
    ],
    imzalar: (v) => [],
  ),
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'İzin talep ve onay formu',
    aciklama: 'Yıllık, mazeret veya ücretsiz izin için personel talebi ve işveren onayı.',
    dosya: 'izin_talep_formu',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('personel', 'Personel adı soyadı'),
      _Alan('tc', 'T.C. kimlik no'),
      _Alan('gorev', 'Görevi'),
      _Alan('tur', 'İzin türü (yıllık / mazeret / ücretsiz / diğer)', varsayilan: 'Yıllık izin'),
      _Alan('bas', 'İzin başlangıç tarihi (gg.aa.yyyy)'),
      _Alan('bit', 'İzin bitiş tarihi (gg.aa.yyyy)'),
      _Alan('gun', 'Toplam gün'),
      _Alan('donus', 'İşbaşı tarihi (gg.aa.yyyy)'),
      _Alan('neden', 'Açıklama', satir: 2),
      _Alan('tarih', 'Form tarihi (gg.aa.yyyy)'),
    ],
    firmadan: {'isveren': (f) => f.unvan},
    icerik: (v) => [
      _baslik('İZİN TALEP VE ONAY FORMU'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _formTablo([
        ('İşveren / işyeri', _d(v('isveren'), '')),
        ('Personel adı soyadı', _d(v('personel'), '')),
        ('T.C. kimlik no', _d(v('tc'), '')),
        ('Görevi', _d(v('gorev'), '')),
        ('İzin türü', _d(v('tur'), '')),
        ('İzin süresi', '${_d(v('bas'), _tarihNokta)} - ${_d(v('bit'), _tarihNokta)}  (${_d(v('gun'), '....')} gün)'),
        ('İşbaşı tarihi', _d(v('donus'), _tarihNokta)),
        ('Açıklama', _d(v('neden'), '')),
      ]),
      _p('Yukarıda belirtilen tarihlerde izin kullanmak istiyorum.', alt: 10),
      _p('İşveren onayı:   [   ] Uygundur     [   ] Uygun değildir     Açıklama: ________________________________', alt: 6),
    ],
    imzalar: (v) => ['PERSONEL\n${_d(v('personel'), '')}', 'İŞVEREN ONAYI\n${_d(v('isveren'), '')}'],
  ),
  _Belge(
    grup: 'İşveren ve personel',
    ad: 'Yazılı uyarı tutanağı',
    aciklama: 'Kurallara uymayan personele yazılı uyarı ve tebellüğ belgesi.',
    dosya: 'yazili_uyari_tutanagi',
    taraf: 'personel',
    alanlar: const [
      _Alan('isveren', 'İşveren / işyeri unvanı'),
      _Alan('personel', 'Personel adı soyadı'),
      _Alan('gorev', 'Görevi'),
      _Alan('olayTarih', 'Olay tarihi (gg.aa.yyyy)'),
      _Alan('olay', 'Olayın açıklaması', satir: 4),
      _Alan('uyari', 'Uyarı metni', satir: 3, varsayilan: 'İşyeri düzenine ve iş sözleşmesine uygun davranmanız, benzer bir durumun tekrarı halinde yasal işlemlerin uygulanacağı yazılı olarak ihtar olunur.'),
      _Alan('tarih', 'Yazı tarihi (gg.aa.yyyy)'),
    ],
    firmadan: {'isveren': (f) => f.unvan},
    icerik: (v) => [
      _baslik('YAZILI UYARI TUTANAĞI'),
      _p('Tarih: ${_d(v('tarih'), _tarihNokta)}', hiza: pw.TextAlign.right),
      _p('Sayın ${_d(v('personel'))} (${_d(v('gorev'))})', alt: 12),
      _p('${_d(v('olayTarih'), _tarihNokta)} tarihinde meydana gelen aşağıdaki durum işyerimizce tespit edilmiştir:'),
      _p(_d(v('olay'))),
      _p(_d(v('uyari'))),
      _p('İşbu uyarı yazısını tebellüğ ettim.   Tarih: ____/____/______', alt: 6),
    ],
    imzalar: (v) => ['İŞVEREN\n${_d(v('isveren'), '')}', 'TEBELLÜĞ EDEN\n${_d(v('personel'), '')}'],
  ),
  // ---- Ticaret odası
  _dilekce(
    grup: 'Ticaret odası',
    ad: 'Faaliyet belgesi talebi',
    aciklama: 'Odaya kayıtlı olduğunu ve faaliyette bulunduğunu gösteren belge talebi.',
    dosya: 'oda_faaliyet_belgesi',
    kurumEtiket: 'Ticaret odası / ticaret sicil müdürlüğü adı',
    kurumSon: 'Başkanlığına / Ticaret Sicil Müdürlüğüne',
    konu: 'Faaliyet belgesi talebi',
    ekler: const [_Alan('sicil', 'Ticaret sicil no'), _Alan('oda', 'Oda sicil no'), _Alan('amac', 'Belgenin verileceği yer / amaç')],
    govde: (v) => [
      'Odanıza ${_d(v('oda'))} oda sicil, ${_d(v('sicil'))} ticaret sicil numarası ile kayıtlı olup faaliyetime devam etmekteyim. ${_d(v('amac'), 'İlgili kurum')} nezdinde kullanılmak üzere faaliyet belgesinin tarafıma verilmesini talep ederim.',
    ],
  ),
  _dilekce(
    grup: 'Ticaret odası',
    ad: 'Ticaret sicil tasdiknamesi talebi',
    aciklama: 'Sicil kaydını gösteren tasdiknamenin istenmesi.',
    dosya: 'oda_sicil_tasdiknamesi',
    kurumEtiket: 'Ticaret odası / ticaret sicil müdürlüğü adı',
    kurumSon: 'Başkanlığına / Ticaret Sicil Müdürlüğüne',
    konu: 'Ticaret sicil tasdiknamesi talebi',
    ekler: const [_Alan('sicil', 'Ticaret sicil no'), _Alan('oda', 'Oda sicil no'), _Alan('amac', 'Kullanılacağı yer / amaç')],
    govde: (v) => [
      '${_d(v('sicil'))} ticaret sicil numaralı işletmemizin güncel sicil bilgilerini gösteren ticaret sicil tasdiknamesinin ${_d(v('amac'), 'ilgili kurumlara ibraz edilmek üzere')} tarafımıza verilmesini talep ederim.',
    ],
  ),
  _dilekce(
    grup: 'Ticaret odası',
    ad: 'İmza sirküleri düzenleme talebi',
    aciklama: 'Yetkili imza sirküleri düzenlenmesi için başvuru.',
    dosya: 'oda_imza_sirkuleri',
    kurumEtiket: 'Ticaret odası / ticaret sicil müdürlüğü adı',
    kurumSon: 'Başkanlığına / Ticaret Sicil Müdürlüğüne',
    konu: 'İmza sirküleri talebi',
    ekler: const [_Alan('sicil', 'Ticaret sicil no'), _Alan('oda', 'Oda sicil no'), _Alan('yetkili', 'Yetkili adı soyadı ve T.C. no')],
    govde: (v) => [
      'Şirketimizi temsile yetkili ${_d(v('yetkili'))} adına, yetkisini ve imzasını gösteren imza sirkülerinin düzenlenmesini talep ederim.',
      'Gerekli belgeler (yetki / karar belgeleri) ekte sunulmuştur.',
    ],
  ),
  _dilekce(
    grup: 'Ticaret odası',
    ad: 'Adres / unvan / nevi değişikliği tescil başvurusu',
    aciklama: 'Sicile kayıtlı bilgilerin değişikliğinin tescili talebi.',
    dosya: 'oda_degisiklik_tescil',
    kurumEtiket: 'Ticaret odası / ticaret sicil müdürlüğü adı',
    kurumSon: 'Başkanlığına / Ticaret Sicil Müdürlüğüne',
    konu: 'Sicil bilgilerinde değişiklik tescili',
    ekler: const [_Alan('sicil', 'Ticaret sicil no'), _Alan('oda', 'Oda sicil no'), _Alan('degisiklik', 'Değişikliğin konusu (eski ve yeni bilgi)', satir: 3)],
    govde: (v) => [
      '${_d(v('sicil'))} ticaret sicil numaralı işletmemize ait sicil kaydında aşağıdaki değişiklik meydana gelmiştir:',
      _d(v('degisiklik')),
      'Değişikliğin ticaret siciline tescil edilmesini ve ilanını talep ederim. Gerekli belgeler ekte sunulmuştur.',
    ],
  ),
  _dilekce(
    grup: 'Ticaret odası',
    ad: 'Oda kaydının silinmesi (terk) talebi',
    aciklama: 'İşi bırakma nedeniyle oda kaydının silinmesi talebi.',
    dosya: 'oda_kayit_silme',
    kurumEtiket: 'Ticaret odası / ticaret sicil müdürlüğü adı',
    kurumSon: 'Başkanlığına / Ticaret Sicil Müdürlüğüne',
    konu: 'Oda kaydının silinmesi talebi',
    ekler: const [_Alan('sicil', 'Ticaret sicil no'), _Alan('oda', 'Oda sicil no'), _Alan('tarih', 'İşi bırakma tarihi (gg.aa.yyyy)')],
    govde: (v) => [
      '${_d(v('tarih'), _tarihNokta)} tarihi itibarıyla işi bıraktığımdan, ${_d(v('oda'))} oda sicil numaralı kaydımın silinmesini talep ederim.',
    ],
  ),
  _dilekce(
    grup: 'Ticaret odası',
    ad: 'Aidat borcu yoktur yazısı talebi',
    aciklama: 'Oda aidatı / borcu bulunmadığını gösteren yazı talebi.',
    dosya: 'oda_borc_yoktur',
    kurumEtiket: 'Ticaret odası / ticaret sicil müdürlüğü adı',
    kurumSon: 'Başkanlığına / Ticaret Sicil Müdürlüğüne',
    konu: 'Oda borcu yoktur yazısı talebi',
    ekler: const [_Alan('sicil', 'Ticaret sicil no'), _Alan('oda', 'Oda sicil no')],
    govde: (v) => [
      'Odanıza ${_d(v('oda'))} oda sicil numarası ile kayıtlı olup aidat ve diğer borçlarımın bulunmadığını gösteren yazının tarafıma verilmesini talep ederim.',
    ],
  ),
];

Future<void> _pdfIndir(_Belge s, _V v) async {
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: await PdfGoogleFonts.notoSansRegular(), bold: await PdfGoogleFonts.notoSansBold()));
  final imzalar = s.imzalar(v);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(52, 52, 52, 44),
    build: (c) => [
      ...s.icerik(v),
      pw.SizedBox(height: 18),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (final i in imzalar)
          pw.Column(children: [
            pw.Text(i, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 30),
            pw.Text('İmza', style: const pw.TextStyle(fontSize: 9)),
          ]),
      ]),
    ],
  ));
  final ad = v(s.taraf).trim();
  await bordroKaydet(ad.isEmpty ? s.dosya : '${s.dosya}_${_ascii(ad)}', Uint8List.fromList(await doc.save()), 'pdf');
}

/// Önemli dilekçe ve formlar: vergi dairesi, SGK, işveren-personel. Sadece yönetici.
class DilekcelerSayfasi extends StatefulWidget {
  const DilekcelerSayfasi({super.key});
  @override
  State<DilekcelerSayfasi> createState() => _DilekcelerSayfasiState();
}

class _DilekcelerSayfasiState extends State<DilekcelerSayfasi> {
  Future<void> _ac(_Belge s) async {
    final ctl = {for (final a in s.alanlar) a.anahtar: TextEditingController(text: a.varsayilan)};
    String v(String k) => ctl[k]?.text ?? '';
    String? hata;
    var mesgul = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(s.ad),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.aciklama, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                if (s.firmadan.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Firmadan doldur', isDense: true),
                    items: [for (final f in FirmaDeposu.ornek.liste) DropdownMenuItem(value: f.id, child: Text(f.unvan, overflow: TextOverflow.ellipsis))],
                    onChanged: (id) {
                      final f = FirmaDeposu.ornek.bul(id ?? -1);
                      if (f == null) return;
                      setD(() => s.firmadan.forEach((k, fn) => ctl[k]?.text = fn(f)));
                    },
                  ),
                ],
                for (final a in s.alanlar)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: ctl[a.anahtar],
                      minLines: a.satir,
                      maxLines: a.satir,
                      decoration: InputDecoration(labelText: a.etiket, isDense: true, border: a.satir > 1 ? const OutlineInputBorder() : null),
                    ),
                  ),
                if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Boş bırakılan alanlar PDF\'te noktalı çizgi olarak çıkar. Belgeler hazır taslaktır, hukuki danışmanlık yerine geçmez. Kullanmadan önce güncel mevzuata ve kurumun şartlarına göre kontrol et.',
                      style: TextStyle(fontSize: 12, color: Colors.black87)),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Kapat')),
            FilledButton(
              onPressed: mesgul
                  ? null
                  : () async {
                      setD(() {
                        mesgul = true;
                        hata = null;
                      });
                      try {
                        await _pdfIndir(s, v);
                        if (c.mounted) Navigator.pop(c);
                      } catch (e) {
                        setD(() {
                          mesgul = false;
                          hata = 'PDF oluşturulamadı: $e';
                        });
                      }
                    },
              child: Text(mesgul ? 'Hazırlanıyor...' : 'PDF indir'),
            ),
          ],
        ),
      ),
    );
    // Pencere kapanış animasyonu bitmeden denetleyiciler atılmasın
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        for (final c in ctl.values) {
          c.dispose();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final gruplar = <String>[];
    for (final b in _belgeler) {
      if (!gruplar.contains(b.grup)) gruplar.add(b.grup);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Dilekçeler ve formlar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Bilgileri doldur, PDF olarak indir. "Firmadan doldur" ile mükellef bilgileri otomatik gelir.', style: TextStyle(color: Colors.black54)),
      for (final g in gruplar) ...[
        Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(g, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        for (final b in _belgeler.where((e) => e.grup == g))
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(b.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(b.aciklama),
              trailing: FilledButton(onPressed: () => _ac(b), child: const Text('Hazırla')),
            ),
          ),
      ],
    ]);
  }
}
