import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bordro_cikti.dart' show bordroKaydet;
import 'firmalar.dart';
import 'personel_takip.dart';

enum SozlesmeTuru { belirli, belirsiz, belirsizDetayli }

String _tarih(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

class SozlesmeVeri {
  final String isverenAd, isverenAdres, sgkSicil;
  final String isciAd, tc, babaAdi, dogum, isciAdres, yapilacakIs, il, deneme, ucretMetni;
  final DateTime baslangic;
  final DateTime? bitis;
  SozlesmeVeri({
    required this.isverenAd,
    required this.isverenAdres,
    required this.sgkSicil,
    required this.isciAd,
    required this.tc,
    required this.babaAdi,
    required this.dogum,
    required this.isciAdres,
    required this.yapilacakIs,
    required this.il,
    required this.deneme,
    required this.ucretMetni,
    required this.baslangic,
    this.bitis,
  });

  String get calismaYeri => il.trim().isEmpty
      ? 'İşverenin işyerinde veya işveren ya da vekilinin göstereceği yerlerde.'
      : 'İşverenin ${il.trim()} sınırları içindeki değişik işyerlerinde, işveren veya vekilinin göstereceği yerler.';

  String get sure {
    final b = bitis;
    if (b == null) return _nokta;
    var ay = (b.year - baslangic.year) * 12 + b.month - baslangic.month;
    if (b.day < baslangic.day - 1) ay -= 1;
    if (ay <= 0) {
      final gun = b.difference(baslangic).inDays + 1;
      return '$gun günlük';
    }
    if (ay % 12 == 0) return '${ay ~/ 12} yıllık';
    return '$ay aylık';
  }

  String get denemeMetin => deneme.trim().isEmpty ? _nokta : deneme.trim();
}

pw.Widget _madde(String baslik, String metin, {double boyut = 9.6}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.RichText(
        textAlign: pw.TextAlign.justify,
        text: pw.TextSpan(style: pw.TextStyle(fontSize: boyut, lineSpacing: 1.5), children: [
          if (baslik.isNotEmpty) pw.TextSpan(text: '$baslik ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.TextSpan(text: metin),
        ]),
      ),
    );

pw.Widget _par(String metin, {double boyut = 9.6, double bosluk = 6}) => pw.Padding(
      padding: pw.EdgeInsets.only(bottom: bosluk),
      child: pw.Text(metin, textAlign: pw.TextAlign.justify, style: pw.TextStyle(fontSize: boyut, lineSpacing: 1.5)),
    );

pw.Widget _baslikSatiri(String t, {double boyut = 10}) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
      child: pw.Text(t, style: pw.TextStyle(fontSize: boyut, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _alan(String etiket, String deger, {double boyut = 9.6}) => pw.Padding(
      padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
      child: pw.Text('$etiket: $deger', style: pw.TextStyle(fontSize: boyut)),
    );

pw.Widget _imza({required String isciBaslik, String? ek}) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(children: [
            pw.Text('İŞVEREN VEYA VEKİL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text('(Kaşe-İmza)', style: const pw.TextStyle(fontSize: 9)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(isciBaslik, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text('Adı Soyadı   :', style: const pw.TextStyle(fontSize: 9.6)),
            pw.SizedBox(height: 6),
            pw.Text('İmzası         :', style: const pw.TextStyle(fontSize: 9.6)),
          ]),
        ]),
        if (ek != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 18), child: pw.Text(ek, style: const pw.TextStyle(fontSize: 9))),
      ]),
    );

List<pw.Widget> _taraflar(SozlesmeVeri v, {bool detayli = false}) => [
      _madde('1.TARAFLAR:', ''),
      _baslikSatiri('İŞVERENİN${detayli ? '' : ':'}'),
      _alan('Adı Soyadı (Unvanı)', v.isverenAd),
      if (detayli) ...[
        _alan('İşyeri SGK Sicil Numarası', v.sgkSicil),
        _alan('Adresi', v.isverenAdres),
      ] else ...[
        _alan('Adresi', v.isverenAdres),
        _alan('İşyeri SGK Sicil Numarası', v.sgkSicil),
      ],
      pw.SizedBox(height: 4),
      _baslikSatiri(detayli ? 'ÇALIŞAN' : 'İŞÇİNİN:'),
      _alan('Adı Soyadı (Unvanı)', v.isciAd),
      if (detayli) _alan('İşe Başlama Tarihi', _tarih(v.baslangic)),
      _alan('Baba Adı', v.babaAdi),
      _alan('Doğum Yeri ve Yılı', v.dogum),
      _alan('TC Kimlik Numarası', v.tc),
      _alan('Adresi', v.isciAdres),
      pw.SizedBox(height: 6),
    ];

List<pw.Widget> _kisaGovde(SozlesmeVeri v, bool belirli) {
  final tur = belirli ? 'BELİRLİ SÜRELİ İŞ SÖZLEŞMESİ' : 'BELİRSİZ SÜRELİ İŞ SÖZLEŞMESİ';
  return [
    _par('Aşağıda isim (unvan) ve adresleri yazılı bulunan işveren ile işçi arasında, tamamen kendi istek ve serbest iradeleri ile ve belirtilen şartlarla "$tur" yapılmıştır. Taraflar bundan sonra "işveren" ve "işçi" olarak anılacaktır.', bosluk: 10),
    ..._taraflar(v),
    _madde('2.İŞÇİNİN ÇALIŞMA YERİ:', v.calismaYeri),
    _madde('3.YAPILACAK İŞ:', v.yapilacakIs.isEmpty ? _nokta : v.yapilacakIs),
    if (belirli)
      _madde('4.SÖZLEŞMENİN SÜRESİ:',
          '${v.sure} süreli olan bu iş sözleşmesi, ${_tarih(v.baslangic)} tarihinde başlamış olup, ${v.bitis == null ? '..../..../........' : _tarih(v.bitis!)} tarihinde her hangi bir bildirim yapılmaksızın kendiliğinden sona erer. İşveren gerektiğinde süresi dolmadan da sözleşmeyi feshedebilir.')
    else
      _madde('4.SÖZLEŞMENİN SÜRESİ:', 'Bu iş sözleşmesi, ${_tarih(v.baslangic)} tarihinde başlamış olup, belirsiz sürelidir.'),
    _madde('5. İŞE BAŞLAMA TARİHİ:', _tarih(v.baslangic)),
    _madde('6. DENEME SÜRELERİ:', 'Deneme süresi ${v.denemeMetin} dır. Taraflar, bu süre içinde iş sözleşmesini ihbarsız ve tazminatsız feshedebilirler.'),
    _madde('7. ÇALIŞMA SÜRELERİ:', 'Haftalık çalışma süresi en çok 45 saattir. Bu süre, haftanın çalışılan günlerine eşit şekilde bölünerek uygulanır.'),
    _par('Ancak, 45 saatlik haftalık normal çalışma süresi, işveren tarafından gerekli görüldüğünde:'),
    _par('a) Haftanın çalışılan günlerine, günde 11 saati aşmamak koşulu ile, farklı şekillerde dağıtılabilir. Ayrıca, işin niteliği ve şartlarına göre, işe başlama ve bitiş saatleri de, işçiler için farklı şekillerde düzenlenebilir ve gerektiğinde değiştirilebilir.', bosluk: 2),
    _par('b) 45 saatlik haftalık normal çalışma süresinin, haftanın çalışılan günlerine farklı şekillerde dağıtılarak çalışılması durumunda, iki aylık çalışma süresi içinde, işçinin haftalık ortalama normal çalışma süresi 45 saati aşamaz.', bosluk: 2),
    _par('c) Ara dinlenme zamanları işveren tarafından belirlenir.', bosluk: 2),
    _par('d) İşçi bu maddede çalışma şekil ve şartlarını peşinen kabul eder.'),
    _madde('8.FAZLA ÇALIŞMA:', 'İşveren, ülkenin genel yararları, işin niteliği veya üretimin artırılması gibi nedenlerle işçiye, günlük toplam çalışma süresi 11 saati aşmamak koşulu ile, yılda 270 saate kadar fazla çalışma yaptırabilir.'),
    _par('Haftalık 45 saati aşan çalışmalar fazla çalışma sayılır. Ancak, denkleştirme esası uygulandığı durumlarda, işçinin iki aylık süre içindeki haftalık ortalama çalışma süresi 45 saati aşmamak koşulu ile, bazı haftalarda 45 saatten fazla çalıştırma olsa dahi, bu haftalardaki 45 saati aşan çalışma süreleri fazla çalışma sayılmaz ve fazla çalışma ücreti ödenmez.'),
    _madde('9.TELAFİ ÇALIŞMASI:', 'Zorunlu nedenlerle işin durması, ulusal bayram ve genel tatillerden önce veya sonra işyerinin tatil edilmesi veya benzer nedenlerle normal çalışma sürelerinin önemli ölçüde altında çalışılması ya da işin tümüyle durdurulması veya işçinin talebi ile kendisine izin verilmesi hallerinde, işveren, iki ay içerisinde işçiye, çalışılmayan bu süreler karşılığı olarak telafi çalışması yaptırabilir.'),
    if (belirli) ...[
      _par('Telafi çalışması, günlük en çok çalışma süresi olan 11 saati ve günde en fazla 3 saati aşamaz. Tatil günlerinde telafi çalışması yaptırılamaz.'),
      _par('Telafi çalışması fazla çalışma sayılmaz ve karşılığında fazla çalışma ücreti ödenmez.'),
    ],
    _madde('10. ÜCRET:', '${v.ucretMetni} İşçinin ücreti kural olarak imza karşılığında kendisine ödenir. Ancak işçinin yazılı talebi ile belirlediği ve bu talebin altında tatbiki imzası bulunan mutemedine de yine imzası karşılığında ödenebilir.'),
    _madde('11. FAZLA ÇALIŞMA ÜCRETİ:', 'İşçinin her bir saat fazla çalışması için işverence ödenecek fazla çalışma ücreti, işçinin normal çalışma ücretinin saat başına düşen miktarının yüzde elli artırılmış tutarıdır.'),
    _madde('12. ÜCRET ÖDEME ZAMANI:', 'İşçi ücreti ayda bir ödenir. Mücbir bir neden olmadıkça, her ayın ücreti, ödeme gününden itibaren en geç 20 gün içinde ödenir.'),
    _madde('13. ÖZEL ŞARTLAR:', ''),
    for (final s in [
      'a) İşverenin, işçilerin bir bölümüne veya tümüne sözleşme gereği olmaksızın, teşvik amaçlı olarak yapacağı süreklilik arz etmeyen nakdi ayni ödemeler, işçiler bakımından kazanılmış hak niteliğinde olmayıp, tekrarlanacağı anlamına gelmez.',
      'b) İşçi, işyerinde, çalışma mevzuatı ve işveren tarafından belirlenmiş bulunan çalışma şartlarına, iş disiplinine, iş sağlığı ve iş güvenliği kurallarına, işveren tarafından çıkartılmış ve çıkartılacak olan yönetmelik, genelge, sirküler, talimat gibi düzenlemelere uymayı kabul ve taahhüt eder.',
      'c) İşçi, işverenin istemesi halinde, hafta tatili ile ulusal bayram ve genel tatil günlerinde de çalışmayı peşinen kabul eder.',
      'd) İşçi, işverenin istemesi halinde fazla çalışma yapmayı peşinen kabul eder.',
      'e) İşçi iş sözleşmesi devam ettiği sürece, özel de olsa başka bir işte çalışmamayı taahhüt eder.',
      'f) İşçi, işverene ve işyerine ait her türlü iş sırlarını saklamayı, işverene zarar verecek davranışlarda bulunmamayı taahhüt eder.',
      'g) İşçi, işyerindeki makine, alet ve teçhizatı usulüne uygun olarak ve özenle kullanmayı, görevi ile ilgili olmayan işlerle uğraşmamayı, kendisine teslim edilmemiş makine, alet ve edevatı kullanmamayı taahhüt eder.',
      'h) İşçi, kendisine işinde kullanılmak üzere teslim edilen malzeme, araç ve gereçleri işyeri dışına çıkarmamayı, amacı dışında kullanmamayı taahhüt eder.',
      'i) İşçi, işyerine, alkollü içki veya uyuşturucu madde almış olarak gelmemeyi ve bu maddeleri işyerinde kullanmamayı, çalışması ile ilgili olmayan eşya ve maddeler ile taşınması ya da kullanılması yasaklanmış maddeleri işyerine sokmamayı taahhüt eder.',
      'j) İşçi, İş Kanununa göre hak kazanacağı yıllık ücretli iznini, işverenin iş şartlarına göre belirleyeceği zamanda kullanmayı kabul eder.',
      'k) İşçi, iş sözleşmesinin feshinde, kendisine teslim edilmiş bulunan her türlü demirbaş eşyayı eksiksiz olarak teslim etmeyi, kendi kasıt veya kusurundan meydana gelmiş zararlar varsa, tazmin etmeyi taahhüt eder.',
      'l) İşveren, işçinin ücretini ve bu sözleşme ile İş Kanunundan doğan diğer haklarını süresinde ödemeyi kabul ve taahhüt eder.',
      "m) Sözleşmenin işveren tarafından feshinde; fesih bildiriminde sebep gösterildiği veya gösterilen sebebin geçerli olmadığı hususunda ortaya çıkacak uyuşmazlıklar, bir ay içinde Özel Hakem'e götürülür.",
      'n) Bu iş sözleşmesinde yer almayan hususlarda İş Kanunu ve diğer ilgili mevzuat uygulanır.',
      'o) Sözleşmenin uygulanmasında çıkacak uyuşmazlıklarda, işyerinin bulunduğu yer mahkemeleri ve icra daireleri yetkilidir.',
    ])
      _par(s, bosluk: 2),
    pw.SizedBox(height: 6),
    _par('14. İş bu ${belirli ? 'belirli' : 'belirsiz'} süreli iş sözleşmesi, ${_tarih(v.baslangic)} tarihinde taraflarca iki nüsha olarak tanzim edilip, okunarak imzalanmakla, işveren işçiyi iş ve ücret vermeyi, işçi de belirtilen şartlarla iş görmeyi karşılıklı olarak kabul, beyan ve taahhüt etmişlerdir.'),
    _imza(isciBaslik: 'İŞÇİ'),
  ];
}

List<pw.Widget> _detayliGovde(SozlesmeVeri v) {
  final a = v.isverenAd;
  final yer = v.isverenAdres;
  final is_ = v.yapilacakIs.isEmpty ? _nokta : v.yapilacakIs;
  return [
    pw.Center(child: pw.Text('BELİRSİZ SÜRELİ İŞ SÖZLEŞMESİ', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
    pw.SizedBox(height: 8),
    _par('Aşağıda isim (unvan) ve adresleri yazılı bulunan işveren ile işçi arasında, tamamen kendi istek ve serbest iradeleri ile ve belirtilen şartlarla "BELİRSİZ SÜRELİ İŞ SÖZLEŞMESİ" yapılmıştır. Taraflar bundan sonra "işveren" ve "işçi" olarak anılacaktır.', bosluk: 10),
    ..._taraflar(v, detayli: true),
    _madde('2.SÖZLEŞMENİN KONUSU', 'İş bu sözleşme, taraflar arasında kurulan iş ilişkisinde karşılıklı hak ve yükümlülükleri düzenlemektedir.'),
    _madde('3.İŞİN YAPILACAĞI YER VE ADRESİ', 'İşçi, iş görme borcunu esas olarak, $yer adresinde kurulu bulunan işverene ait $a adlı işyerinde yerine getirecektir. Ancak, işverenin işin düzenlenmesi yetkisi çerçevesinde, işçiyi işverene ya da iştiraklerine ait aynı ya da başka illerde bulunan işyerlerinde, şubelerinde muvafakat aranmaksızın geçici veya devamlı olarak görevlendirmesini (nakil yetkisini), çalışan kabul ve taahhüt eder. Nakil sebebiyle çalışanın haklarında indirim ya da eksiltme yapılamaz.'),
    _madde('4.SÖZLEŞME KONUSU İŞ', 'Çalışan, işverenin $a adıyla yukarıda belirtilen adresteki işyerinde, sözleşmenin kapsamında ve ekinde yer alan şartlarla $is_ personeli olarak çalışacaktır. Çalışanın görev alanına giren konular bu sözleşmenin ekinde yer alan görev tanımında ayrıntılı olarak tanımlanan konulardır.'),
    _madde('5.DENEME SÜRESİ', 'İş bu iş sözleşmesi belirsiz süreli olarak akdedilmiş olup, çalışan ${_tarih(v.baslangic)} tarihinde işe başlayacaktır. Deneme süresi ${v.denemeMetin} ay olup, gerek işveren ve gerekse de çalışan deneme süresi içinde iş bu sözleşmeyi bildirim süresine gerek olmaksızın ve tazminatsız olarak feshedebilir. Çalışılan günlerin ücreti ve diğer haklar işverence çalışana ödenir.'),
    _madde('6.İŞİN KAPSAMI VE ÇALIŞANIN YÜKÜMLÜLÜKLERİ', 'Çalışanın iş ve görev tanımı; başlıca (bunlarla sınırlı olmamak üzere) aşağıda yer alan hususları kapsamaktadır.'),
    _par('İşverene ait işyerinde $is_ olarak İşveren, İş Kanunu hükümlerine uygun olmak kaydıyla, yukarıda yer alan görevlerle sınırlı olmamak üzere, çalışana kendi görevi ile ilgili eğitim, deneyim ve mevkiine uygun olmak koşuluyla ek görev verebilir veya çalışandan çeşitli işlerin yerine getirilmesini isteyebilir. Çalışan, söz konusu ek görev ve işleri tam ve eksiksiz olarak yerine getireceğini kabul ve taahhüt eder. Çalışan, bu hizmetleri karşılığında belirtilen aylık ücreti dışında herhangi bir ücret talep edemez.'),
    _par('Çalışan, işin ve görevin tam olarak yapılabilmesi için, işin tamamlayıcısı olan işleri ve diğer çalışanlar ile gerekli işbirliğinin sağlanması görevlerini ve iş bu iş sözleşmesinde ve görev tanımında ayrı ayrı yazılmamış olsalar bile işin muhtevasına dahil olduğu anlaşılan tüm işleri yapmakla görevlidir. Yazılı olmadıkları gerekçesiyle bunları yapmaktan kaçınamaz.'),
    _par('Çalışan, iş bu sözleşmenin ekinde bulunan genel ve özel işyeri kurallarına ve İş Kanunda belirtilen kurallara, İşyerinin İç Yönetmeliklerine, İşçi Sağlığı İş Güvenliği Talimatlarına ve bu yönetmelik ve talimatlarda sonradan yapılacak değişikliklere, yürürlüğe konulacak yeni yönetmelik ve talimatlara uymayı ve bunların iş sözleşmesinin eki ve tamamlayıcısı olduklarını peşinen kabul ve taahhüt eder.'),
    _par('Çalışan, iş tanımı ve kapsamında yer alan asıl görevleri ve işveren tarafından verilecek ek görevler kapsamında verilen işi özenle yapmak, dürüstlük ve iyiniyet kurallarına uymak, işçi sağlığı ve iş güvenliği tedbirlerine riayet etmekle yükümlüdür. Çalışan, görevi ifasında ve işyeri disiplinin sağlanmasında işverenin talimatlarına ve işveren tarafından belirlenen çalışma kurallarına uyacağını, her durumda işverenin ve iştiraklerinin menfaatlerini koruyacağını kabul ve taahhüt eder.'),
    _par('Çalışan, iş bu sözleşmenin devamı süresince, işveren nezdindeki görevinden ayrı olarak, kendi inisiyatifiyle serbest zamanlarda, her türlü tatil günlerinde, ücretli boş zamanlarında başka bir işveren yanında çalışamaz. Aksi davranış haklı nedenle fesih sebebidir.'),
    _par('Çalışan, kendi kusur ve ihmali neticesinde meydana gelen zararlardan sorumludur.'),
    _madde('7.ÜCRET', 'Çalışan aylık ücretle çalışır. Ücreti, işverence tanzim olunan ücret bordrosunda yer alan ücrettir. İşe başladığı tarih itibariyle ${v.ucretMetni} Bütün ücret düzenlemeleri aylık net ücret üzerinden hesap edilir. Ücret ödemeleri, bir sonraki ayın ilk 10 günü içinde işverence uygun görülen zamanda yapılır. Son günün tatil gününe denk gelmesi halinde ödemeler tatili izleyen ilk iş günü yapılır. Bu sebeple ortaya çıkacak gecikme ücretin ödenmesinde gecikme sayılmaz. Mücbir sebepler dışında ücretin ödenmesinde herhangi bir gecikme olursa bu gecikme 20 günü geçemez. Çalışanın avans talebi işverenin kabulüne bağlıdır.'),
    _par('Çalışanın ücreti, çalışanın banka hesabına yatırılmak suretiyle ödenir. İşveren bu ödeme ile borçtan kurtulmuş olur.'),
    _par('Çalışan, ay sonunda tahakkuk eden ve kendisine ücret bordrosu ile bildirilen ödemelere bir hafta içerisinde yazılı olarak itiraz eder. Bir hafta içinde itirazda bulunulmaması halinde bordroya mutabık kalındığını kabul eder.'),
    _par('Ücret dışında, ikramiye, prim v.b. diğer ücret eklerinin tahsisi ve ödenmesi işverenin takdir yetkisindedir. İşveren, çalışanların bir bölümüne veya tamamına sözleşme gereği olmaksızın, teşvik amaçlı olarak yapacağı süreklilik arz etmeyen nakdi ve ayni ödemeler, çalışanlar tarafından kazanılmış hak olmayıp, tekrarlanacağı anlamına gelmez.'),
    _par('Çalışan, aylık ücretine, yasal sınırlar içinde kalan 270 saatlik fazla çalışma ücreti, hafta tatili ücreti, ulusal bayram ve genel tatilde çalışılmayan sürelerdeki ücretler ile ücretli boş zamanlara ait ücretler ve telafi çalışması ücretleri dahildir. Çalışan, ücrete dahil fazla çalışma yapmayı peşinen kabul eder. Ücrete dahil fazla çalışma günlük en çok çalışma süresi olan 11 saati aşmayacak şekilde yapılır. Bir yıl içinde 270 saatin altında fazla çalışma yapılmaması nedeniyle, çalışanın ücretinden bir indirim yapılamaz.'),
    _par('Çalışanın ücretine dahil olan yıllık 270 saatin üstünde fazla çalışma yapması halinde, yapılan fazla çalışma aylık ücret bordrosunda gösterilir ve fazla çalışma ücreti işçiye ödenir. Çalışan, ücret bordrosunda görünenin dışında da, fazla çalışma yaptığı iddiasıyla sonradan fazla çalışma ücreti talep edemez.'),
    _par('Çalışanın ücretinde yapılacak ayarlama, çalışanın iş disiplini, verim ve performansı, ülkenin ve işletmenin ekonomik koşulları dikkate alınarak işveren tarafından uygun görülen zamanda ve işverence tek taraflı olarak belirlenen miktarda yapılır. Bu hüküm, her halükarda işverence ücret ayarlaması yapma taahhüdü anlamına gelmez.'),
    _madde('8.ÇALIŞMA SÜRESİ', 'Çalışma süresi, İş Kanununda belirtilen haftalık normal çalışma süresidir. Haftalık çalışma süresi 45 saattir. Haftalık çalışma süresinin günlere göre dağılımı, başlama ve bitiş saatleri, hafta tatili günü, vardiya saatlerinin ve ara dinlenmesinin belirlenmesi ve değişimi işveren tarafından yapılır. Zorlayıcı şartların varlığı halinde veya işin gereğine göre işveren, mesai başlama ve bitim saatlerini ve ara dinlenmelerini ileri veya geri alabilir.'),
    _par('Çalışan, İş Kanunu uyarınca hüküm altına alınan denkleştirme süresine ilişkin uygulamayı kabul ve taahhüt eder. Çalışan, denkleştirme esasına uygun çalışma düzeninin belirlenmesinde, yoğunlaştırılmış iş haftalarının uygulanmasında işverenin belirlediği kurallara ve çalışma süresine göre çalışmayı kabul eder. Çalışan, denkleştirme esasına göre kullanacağı ücretli boş zamanlarda günlük çalışma süresini aşmamak kaydıyla fazla çalışma yapmayı kabul eder.'),
    _par('Çalışan, işveren tarafından belirlenen günlük ve haftalık çalışma saatleri ile ilgili düzenlemelere uymak zorundadır. Çalışan, çalışma saatlerine uymaması veya işe geç kalması halinde çalışmadığı saat ücreti kesilir. Geçerli ve yazılı bir mazereti olmadan bir ay içinde iki defa işe geç gelen çalışana ihtar verilir. İhtar almış çalışan bir daha işe geç gelirse, o gün işbaşı yaptırılmaz ve işe gelmemiş kabul edilerek o günkü ücreti ile hafta tatili ücreti kesilir.'),
    _madde('9.FAZLA ÇALIŞMA', 'Çalışan iş programında ihtiyaç olduğu takdirde ve işverence gerekli görülen hallerde yasa hükümleri çerçevesinde geçici veya sürekli olarak, normal günlerde, hafta tatili, genel tatil ve resmi tatil günlerinde fazla çalışma yapmayı peşinen kabul ve taahhüt eder.'),
    _par('Bu hallerde, fazla çalışma, işverenin isteği üzerine ve işverenin belirleyeceği gün ve zamanlarda yapılır.'),
    _madde('10.TATİL GÜNLERİNDE ÇALIŞMA', 'Çalışan, işverenin talebi halinde, Ulusal Bayram ve genel Tatil günlerinde çalışmayı kabul ve taahhüt eder. Çalışanın bu günlerde çalışması halinde, her gün için bir günlük ücreti aylık ücrete ek olarak ödenir.'),
    _madde('11.TELAFİ ÇALIŞMASI', 'Zorunlu nedenlerle, işin durması, ulusal bayram ve genel tatillerden önce veya sonra işyerinin tatil edilmesi veya benzer nedenlerle, işyerinde normal çalışma sürelerinin önemli ölçüde altında çalışılması veya tamamen tatil edilmesi ya da çalışanın talebi ile kendisine izin verilmesi hallerinde, işveren iki ay içinde çalışılmayan süreler için telafi çalışması yaptırabilir. Bu çalışmalar fazla çalışma veya fazla sürelerle çalışma sayılmaz.'),
    _par('Telafi çalışmaları, günlük en çok çalışma süresini aşmamak koşulu ile günde üç saatten fazla olamaz. Tatil günlerinde telafi çalışması yaptırılamaz. İşverenin talebi üzerine telafi çalışması yapılması gerekirken bundan kaçınan çalışanın iş sözleşmesi haklı nedenle derhal feshedilir.'),
    _madde('12.HAFTA TATİLİ', 'Çalışan, işveren tarafından belirlenen haftalık izin çizelgesine göre haftada bir gün izin kullanma hakkına sahiptir. Haftalık izin nedeniyle çalışanın ücretinden kesinti yapılamaz.'),
    _madde('13.YILLIK ÜCRETLİ İZİN', 'İşveren bünyesinde, İş Kanunun belirlediği şekilde en az bir yıl çalışmış olmak koşuluyla, çalışan yıllık ücretli izne hak kazanır. Çalışanın yıllık ücretli izni, kıdemine göre İş Kanunun belirlediği asgari sürelerdir. Çalışan, İş Kanununa göre kullanacağı yıllık ücretli iznini, işverenin iş şartlarına göre belirleyeceği zamanda kullanmayı kabul eder.'),
    _madde('14.REKABET YASAĞI', 'Çalışan, gerek bu sözleşme süresince, gerekse sözleşmenin herhangi bir sebeple sona ermesini takip eden bir yıl boyunca, işveren ile doğrudan rekabet teşkil edecek faaliyetlerden uzak duracak ve işveren ile aynı çevrede ve aynı alanda faaliyet gösteren rakip bir müessesede her ne sıfatla olursa olsun görev almayacaktır. Aksi halde, işçi Borçlar Kanunun 351 maddesi uyarınca son aylık net ücretinin bir yıllık tutarını maktu tazminat olarak ödemeyi kabul ve taahhüt eder.'),
    _madde('15.SIR SAKLAMA YÜKÜMLÜLÜĞÜ', 'Çalışan, istihdam süresi boyunca yaptığı çalışmalar ve/veya istihdamı dolayısıyla elde ettiği bilgi ve belgeleri hiçbir surette üçüncü şahıslara iletmeyecek ve söz konusu bilgi ve belgelerin üçüncü şahısların eline geçmemesi için gerekli tüm özeni ve gayreti göstereceğini kabul ve taahhüt eder. Çalışan, bu yükümlülüğüne aykırı davranması neticesinde işverenin zararından mesul olacağını kabul eder. Ayrıca, sır saklama yükümlülüğüne aykırılık iş sözleşmesinin haklı nedenle derhal feshedilmesi sonucunu doğurur.'),
    _madde('16.SÖZLEŞMENİN SONA ERMESİNDE UYULACAK BİLDİRİM SÜRELERİ', 'Gerek işveren ve gerekse çalışan tarafından yapılacak bildirimli fesihler, İş Kanununda yer alan şekil, şart ve niteliklere uygun olarak yapılacaktır.'),
    _par('Çalışan, işveren yanındaki işinden ayrılmaya karar verdiği takdirde bu kararını yazılı olarak aşağıda belirtilen ihbar sürelerine uymak suretiyle işverene bildirmekle yükümlüdür. Yine, işveren tarafından iş bu sözleşmenin sona erdirilmesi durumunda, işveren aşağıda yer alan ihbar sürelerini çalışana tanımayı kabul ve taahhüt eder.'),
    _par('İhbar müddetleri aşağıdaki gibidir.', bosluk: 2),
    _par('6 aydan daha az çalışmış olanlar için 2 hafta,', bosluk: 1),
    _par('6 aydan 1.5 yıla kadar çalışmış olanlar için 4 hafta,', bosluk: 1),
    _par('1.5 yıldan 3 yıla kadar çalışmış olanlar için 6 hafta,', bosluk: 1),
    _par('3 yıldan daha fazla çalışmış olanlar için 8 hafta,'),
    _par('Yukarıda belirtilen ihbar müddetleri, iş bu sözleşmenin haklı nedenlerle feshi halinde uygulanmayacaktır.'),
    _par('İş Kanunu hükümleri dahilinde, çalışan hakkında, işveren tarafından belirlenecek olan dönemlerde yine işveren tarafından belirlenecek olan performans değerlendirme sistemi uygulanacaktır. Performans değerlendirme sistemi neticesinde elde edilen verilere göre işveren, çalışmalarında diğer çalışanlara oranla verilen görevleri gerektiği gibi yerine getiremeyen ve/veya geç yerine getiren, kendisi ile aynı görev pozisyonunda olan çalışanlara oranla daha az verimli çalışan, kendisinde aranılan niteliklere göre beklenilen iş veriminin altında çalışan, çalışmakta olduğu pozisyonun layığını yerine getirmeyen ve/veya benzer nedenlerle düşük performanslı çalışanların iş sözleşmeleri İş Kanunda yer alan şartlar saklı kalmak kaydıyla feshedilebilecektir.'),
    _madde('17.İŞE İADE HALİNDE MAHSUP HÜKÜMLERİ', 'Çalışanın, Mahkeme veya hakem kararı ile işe iadesine karar verilmesi halinde; işveren çalışanı işe başlatırsa, geçersiz kılınan fesih sırasında eğer çalışana kıdem ve ihbar tazminatı ödenmişse, işverenin bu alacağı öncelikle yasa gereği çalışanın boşta geçirdiği süre için hükmedilmiş ücret ve diğer hakları ile mahsup edilir; arta kalan kısım olursa çalışan arta kalan miktarı yasal faizi ile birlikte işverene iade eder. İade işlemi çalışanın talebi üzerine aylık ücretinden kesinti yapmak suretiyle de gerçekleştirilebilir. Yapılacak kesinti en fazla çalışanın ücretinin % 25\'i kadar olabilir.'),
    _madde('18.ÖZEL HÜKÜMLER', ''),
    _baslikSatiri('A) ÇALIŞANIN GÖREV VE YÜKÜMLÜLÜKLERİ'),
    for (final s in [
      'a) Çalışan, işveren veya işveren vekili tarafından kendisine verilen görevleri ve taahhüt ettiği işi özen ile yapmak zorundadır.',
      'b) Çalışan, kasıt veya ihmal ve dikkatsizlik sonucu işverene ve/veya müşterilere verdiği tüm zarar ve ziyandan sorumlu olup, bu tür zarar ziyanların tamamı çalışanın ücretinden kesilecektir.',
      'c) Çalışan, çalışma saatleri içinde işyerinde olmak zorundadır. Çalışan, işveren veya işveren vekilinden izin almadıkça çalışma saatleri içinde işyerinden ayrılamaz. İş için başka bir yere gönderildiğinde de verilen görevi yerine getirip makul sürede işine dönmek zorundadır.',
      'd) Çalışan, müşterileri rahatsız edecek her türlü davranıştan kaçınacak, müşterilerle ve işyerindeki diğer personel ve yöneticilerle ilişkilerinde her zaman genel ahlak ve adap kurallarına uyacaktır.',
      'e) Çalışanın, işini yerine getirirken dahi, diğer işçilerle müşteriyi rahatsız edecek şekilde yüksek sesle konuşması, işletme içerisinde cep telefonu, elektronik eşya vb. cihazları kullanması iş saati içerisinde uyuması, gazete, mecmua okuması ve ziyaretçi kabul etmesi yasaktır.',
      'f) Çalışan, çalışma saatleri içerisinde, kendisine verilen, adı-soyadı ve görevinin belirtildiği isimliği takmak zorundadır.',
      'g) İşyerinde, kıyafet tüzüğüne uygun olarak, işverence verilen iş elbiselerinin giyilmesi zorunludur. İş elbisesiyle dışarı çıkmak yasaktır.',
      'h) Çalışan, işyerinde kullanılan araç ve gereçleri, demirbaşları kullanım talimatlarına uygun olarak kullanmayı ve kendisine işinde kullanılmak üzere teslim edilen malzeme, araç ve gereçleri işyerinden çıkarmamayı, amacı dışında kullanmamayı, kendisine teslim edilmemiş makine, alet ve edevatı kullanmamayı, görevi ile ilgili olmayan işlerle uğraşmamayı kabul ve taahhüt eder.',
      'i) Çalışan, görevi gereği kendisine ya da bağlı bulunduğu birime teslim edilen demirbaş ile her türlü alet ve edevat vb. eşyanın muhafazasından, hasar ve ziyan görmesinden sorumludur.',
      'j) Çalışan, iş çıkışında, işveren tarafından görevlendirilen elemanlarca yapılacak üst aramasına rıza göstermek zorundadır.',
      'k) Çalışan, işyerindeki temizlik ve hijyen kurallarına harfiyen uymak ve kullanılması gerekli olan yerlerde bone, galoş, eldiven vs. ekipmanları kullanmak, işyerinde haftalık ve aylık olarak yapılan ilaçlama nedeniyle gerekli önlemleri almak ve bunlara uymak zorundadır.',
      'l) İşyerine ait müşteri otoparkının çalışanlar tarafından kullanılması yasaktır.',
      'm) İşyerindeki elektrik, su, doğalgaz vs. amacına uygun olarak ve israfa yol açmayacak şekilde kullanılması zorunludur. İşyeri telefonunun özel görüşmelerde kullanılması yasaktır.',
      'n) İşyerinde, yemek saati haricinde yemek yemek yasaktır.',
      'o) İşyerine alkol ve uyuşturucu madde etkisiyle gelmek ve işyerinde bu tür maddeler ile sigara ve diğer keyif verici maddelerinin kullanılması, işyerinde bıçak, silah v.b. kesici, delici alet ve edevat taşınması, bulundurulması kesinlikle yasaktır.',
      'p) Çalışan, iş sağlığı ve güvenliği konusunda alınmış tüm önlem ve kurallara uymayı, iş sağlığı ve güvenliği malzemesini kullanmayı kabul ve taahhüt eder.',
      'r) Çalışan gerek işe başlarken gerekse çalıştığı süre içinde, işverenin istediği evrakları (sabıka kaydı, ikametgah, sağlık raporu v.s.) getirmek zorundadır.',
      's) Çalışan, hiçbir şekilde işyeri adresini posta ve tebligat adresi olarak kullanamaz.',
      't) Çalışan, istendiğinde hizmet içi veya görevin gerektirdiği diğer eğitimlere katılmak zorundadır.',
      'u) Çalışanın iş sözleşmesi hükümlerine ve görev tanımında yer alan hususlara aykırı hareket etmesi ya da yasak olan fiil ve hareketleri yapması halinde, iş sözleşmesi, süre verilmeksizin, tazminatsız olarak derhal feshedilir. İş Yasasının, iş sözleşmesinin sona ermesine ilişkin diğer hükümleri saklıdır.',
      'v) İş sözleşmesinin sona ermesi ile ilgili hak ve yükümlülük doğuran hususlarda, işyerindeki diğer çalışma koşulları hakkında ve iş sözleşmesinde yer almayan diğer hususlarda işyeri iç yönetmelik ve talimatları ile İş Yasası ve diğer mevzuat hükümleri uygulanır.',
    ])
      _par(s, bosluk: 3),
    _baslikSatiri('B) İŞVERENİN GÖREV VE SORUMLULUKLARI'),
    for (final s in [
      'a) İşveren, çalışanın ücretini, bir sonraki ayın ilk 10 günü içinde ödeyecektir.',
      'b) İşveren, işçilik haklarını ödemek, ahlak ve iyiniyet kurallarına uymak, işçi sağlığı ve iş güvenliği tedbirlerini almakla yükümlüdür.',
      'c) Çalışanın avans talebi ve ücretine yapılacak zam tamamen işverenin takdirindedir.',
      'd) İşveren, çalışanın evlilik halinde 3 gün, ana-baba-kardeş-eş ve çocukların ölümü halinde 3 gün, eşin doğum yapması halinde 3 gün izin verir. Ancak bu izinlerin ücretinin ödenip ödenmeyeceği tamamen işverenin takdirindedir. İşveren, İş Kanununda belirtilen kıdeme göre yıllık ücretli izin vermek zorundadır.',
      'e) Çalışanın talep ettiği ücretsiz izinlerin verilip verilmemesi tamamen işverenin takdirindedir. İşverence çalışana ücretsiz izin verilmişse, ücretsiz izin süresince çalışana herhangi bir ücret ödenmez. Bir haftaya kadar verilen ücretsiz izinlerde hafta tatili ücreti kesilmez ve işçi çalışmadığı halde hafta tatili ücretine hak kazanır. Bir haftayı aşan ücretsiz izinlerde hafta tatili ücreti kesilir.',
    ])
      _par(s, bosluk: 3),
    _madde('19.SÖZLEŞME EKİ OLAN DÜZENLEMELER', 'İşverenin işyerinde uygulanan performans ve verimlilik standartları, görev tanımı, çalışma saatlerine ilişkin düzenlemeler, işyeri yönetmelikleri, disiplin yönetmelikleri ve iş talimatları iş bu sözleşmenin ekidir. Çalışan, düzenlemeleri okuduğunu ve içeriğini kabul ettiğini, düzenlemelerde belirlenmiş kurallara uyacağını beyan ve taahhüt eder.'),
    _madde('20.TEBLİGAT', 'Adres değişikliği halinde taraflar, bu değişiklikleri yazılı ve/veya iadeli taahhütlü mektup ile birbirlerine bildireceklerdir. Aksi takdirde, tarafların iş bu sözleşmede belirtilen adreslerine yapılacak her türlü tebligat bizzat kendilerine yapılmış sayılacaktır.'),
    _madde('21.SÖZLEŞMENİN BAŞLANGIÇ TARİHİ', 'İş bu sözleşme ${_tarih(v.baslangic)} tarihinde yürürlüğe girecektir.'),
    _madde('22.SON HÜKÜMLER', 'Bu sözleşmede hüküm bulunmayan hususlarda İş Kanunu hükümleri uygulanacaktır. Uyuşmazlıklarda çözüm mercii İlgili Mahkeme ve İcra Daireleridir.'),
    _madde('23.İMZA TARİHİ', 'İş bu belirsiz süreli iş sözleşmesi ${_tarih(v.baslangic)} tarihinde, taraflarca iki nüsha olarak tanzim edilip, okunarak imzalanmış olup, işveren çalışana iş ve ücret vermeyi, çalışan da belirtilen şartlarla iş görmeyi karşılıklı olarak kabul, beyan ve taahhüt etmişlerdir.'),
    _imza(
      isciBaslik: 'ÇALIŞAN',
      ek: 'İş Sözleşmesinin bir suretini ve ekindeki görev tanımı ile çalışan yönetmeliği ve disiplin yönetmeliğini teslim aldım.',
    ),
  ];
}

Future<Uint8List> sozlesmePdf(SozlesmeTuru tur, SozlesmeVeri v) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
    ),
  );
  final icerik = tur == SozlesmeTuru.belirsizDetayli ? _detayliGovde(v) : _kisaGovde(v, tur == SozlesmeTuru.belirli);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 40),
    footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8.5))),
    build: (c) => icerik,
  ));
  return doc.save();
}

/// Personel için sözleşme türünü ve eksik bilgileri sorar, PDF olarak indirir.
Future<void> sozlesmeIndir(BuildContext context, Personel p) async {
  final mesaj = ScaffoldMessenger.of(context);
  final firma = FirmaDeposu.ornek.bul(p.firmaId);
  final meslekAd = p.meslek.contains(' - ') ? p.meslek.substring(p.meslek.indexOf(' - ') + 3) : p.meslek;
  var tur = SozlesmeTuru.belirsiz;
  final is_ = TextEditingController(text: meslekAd);
  final il = TextEditingController();
  final deneme = TextEditingController();
  final baba = TextEditingController();
  final dogum = TextEditingController();
  final adres = TextEditingController();
  var baslangic = p.giris;
  DateTime? bitis;
  String? hata;
  var mesgul = false;

  String ucretMetni() {
    if (p.asgari) return 'İşçinin brüt ücreti ASGARİ ÜCRET\'tir.';
    if (p.ucret <= 0) return 'İşçinin aylık ücreti $_nokta TL\'dir.';
    final tutar = p.ucret.toStringAsFixed(2).replaceAll('.', ',').replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
    return 'İşçinin aylık ${p.maasTuru == 'brut' ? 'BRÜT' : 'NET'} ücreti $tutar TL\'dir.';
  }

  final tamam = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: Text('İş sözleşmesi: ${p.ad}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              RadioGroup<SozlesmeTuru>(
                groupValue: tur,
                onChanged: (v) => setD(() => tur = v ?? tur),
                child: Column(children: const [
                  RadioListTile<SozlesmeTuru>(dense: true, title: Text('Belirsiz süreli (kısa, 2 sayfa)'), value: SozlesmeTuru.belirsiz),
                  RadioListTile<SozlesmeTuru>(dense: true, title: Text('Belirsiz süreli (ayrıntılı, 5 sayfa)'), value: SozlesmeTuru.belirsizDetayli),
                  RadioListTile<SozlesmeTuru>(dense: true, title: Text('Belirli süreli (2 sayfa)'), value: SozlesmeTuru.belirli),
                ]),
              ),
              const SizedBox(height: 6),
              TextField(controller: is_, decoration: const InputDecoration(labelText: 'Yapılacak iş (örn. Eczane İşçisi)')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(context: c, initialDate: baslangic, firstDate: DateTime(1990), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                      if (d != null) setD(() => baslangic = d);
                    },
                    child: Text('Başlangıç: ${_tarih(baslangic)}'),
                  ),
                ),
                if (tur == SozlesmeTuru.belirli) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(context: c, initialDate: bitis ?? baslangic.add(const Duration(days: 365)), firstDate: baslangic, lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
                        if (d != null) setD(() => bitis = d);
                      },
                      child: Text(bitis == null ? 'Bitiş tarihi seç' : 'Bitiş: ${_tarih(bitis!)}'),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 8),
              TextField(controller: deneme, decoration: InputDecoration(labelText: tur == SozlesmeTuru.belirsizDetayli ? 'Deneme süresi (ay sayısı, boşsa noktalı)' : 'Deneme süresi (örn. 2 ay, boşsa noktalı)')),
              const SizedBox(height: 8),
              TextField(controller: il, decoration: const InputDecoration(labelText: 'Çalışma yeri ili (örn. İstanbul, boş bırakılabilir)')),
              const SizedBox(height: 8),
              TextField(controller: baba, decoration: const InputDecoration(labelText: 'İşçinin baba adı (boş bırakılabilir)')),
              const SizedBox(height: 8),
              TextField(controller: dogum, decoration: const InputDecoration(labelText: 'Doğum yeri ve yılı (boş bırakılabilir)')),
              const SizedBox(height: 8),
              TextField(controller: adres, decoration: const InputDecoration(labelText: 'İşçinin adresi (boş bırakılabilir)')),
              if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 6),
              const Text('Boş bırakılan alanlar PDF\'te noktalı satır olarak kalır, elle doldurabilirsin.', style: TextStyle(fontSize: 12, color: Colors.black87)),
            ]),
          ),
        ),
        actions: [
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
                      final v = SozlesmeVeri(
                        isverenAd: _buyuk(firma?.unvan ?? ''),
                        isverenAdres: firma?.adres ?? '',
                        sgkSicil: firma?.sgkSicilNo ?? '',
                        isciAd: _buyuk(p.ad),
                        tc: p.tc,
                        babaAdi: baba.text.trim(),
                        dogum: dogum.text.trim(),
                        isciAdres: adres.text.trim(),
                        yapilacakIs: is_.text.trim(),
                        il: il.text,
                        deneme: deneme.text,
                        ucretMetni: ucretMetni(),
                        baslangic: baslangic,
                        bitis: tur == SozlesmeTuru.belirli ? bitis : null,
                      );
                      final bytes = await sozlesmePdf(tur, v);
                      final etiket = tur == SozlesmeTuru.belirli ? 'belirli' : 'belirsiz';
                      await bordroKaydet('${etiket}_sureli_is_sozlesmesi_${_ascii(p.ad)}', bytes, 'pdf');
                      try {
                        await Supabase.instance.client.from('personel').update({
                          'sozlesme_turu': etiket,
                          'sozlesme_bitis': tur == SozlesmeTuru.belirli && bitis != null ? bitis!.toIso8601String().substring(0, 10) : null,
                        }).eq('id', p.id);
                      } catch (_) {}
                      if (c.mounted) Navigator.pop(c, true);
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
  if (tamam == true) mesaj.showSnackBar(const SnackBar(content: Text('İş sözleşmesi indirildi.')));
}
