part of 'beyannameler.dart';

/// PDF'lerden otomatik belge ayıklama: firma (vergi no / TC no / SGK fişinde unvan), belge türü ve dönem.
/// Okunamayan veya emin olunamayan alanlar önizlemede elle seçilir; hiçbir şey sorulmadan yüklenmez.

class _Aday {
  final String dosyaAdi;
  final Uint8List bytes;
  int? firmaId;
  BelgeTuru? tur;
  String beyanname = ''; // tahakkuk fişinde hangi beyanname
  int? yil;
  String? donem;
  bool sec = false;
  bool tekrar = false;
  String not = '';
  _Aday(this.dosyaAdi, this.bytes);

  bool get tamam =>
      firmaId != null && tur != null && yil != null && donem != null && _donemler(tur!).contains(donem);
}

const _ayAnahtar = [
  'ocak', 'subat', 'mart', 'nisan', 'mayis', 'haziran', 'temmuz', 'agustos', 'eylul', 'ekim', 'kasim', 'aralik'
];

/// Türkçe karakterleri sadeleştirip küçük harfe çevirir.
String _katla(String s) {
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

String _adSade(String s) => _katla(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

Future<String> _pdfMetni(Uint8List b) async {
  try {
    final d = sf.PdfDocument(inputBytes: b);
    final son = d.pages.count > 1 ? 1 : 0;
    final t = sf.PdfTextExtractor(d).extractText(startPageIndex: 0, endPageIndex: son, layoutText: true);
    d.dispose();
    return t;
  } catch (_) {
    return '';
  }
}

int? _ayNoBul(String? ad) {
  if (ad == null) return null;
  final i = _ayAnahtar.indexOf(ad);
  return i < 0 ? null : i + 1;
}

/// Metinden bulunamayan tür / beyanname / yıl / dönem bilgilerini önce dosya adından
/// (örn. 2026_MART_GGeciciUC_AYLIK.xml_THK.pdf), sonra gevşek metin aramasından doldurur.
/// Yalnızca boş kalan alanlara dokunur.
void _eksikleriTamamla(_Aday aday, String dosya, String a) {
  const aylarRe = 'ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik';
  final thk = dosya.contains('thk') || dosya.contains('tahakkuk');
  final byn = dosya.contains('byn') || dosya.contains('beyanname');

  // Beyanname cinsi (dosya adından)
  String? cins;
  if (dosya.contains('kdv')) {
    cins = 'KDV';
  } else if (dosya.contains('muhtasar')) {
    cins = 'Muhtasar ve Prim Hizmet';
  } else if (dosya.contains('gecici')) {
    cins = 'Geçici Vergi';
  } else if (dosya.contains('kurum')) {
    cins = 'Kurumlar Vergisi';
  } else if (dosya.contains('gelir')) {
    cins = 'Gelir Vergisi';
  }

  BelgeTuru? turdenCins(String c) => switch (c) {
        'KDV' => BelgeTuru.kdvBeyannamesi,
        'Muhtasar ve Prim Hizmet' => BelgeTuru.muhtasarBeyannamesi,
        'Geçici Vergi' => BelgeTuru.geciciVergi,
        'Gelir Vergisi' => BelgeTuru.gelirVergisi,
        'Kurumlar Vergisi' => BelgeTuru.kurumlarVergisi,
        _ => null,
      };

  // Tür
  if (aday.tur == null && cins != null) {
    if (thk && !byn) {
      aday.tur = BelgeTuru.tahakkuk;
      aday.beyanname = cins;
    } else {
      aday.tur = turdenCins(cins);
    }
  }
  if (aday.tur == BelgeTuru.tahakkuk && (aday.beyanname.isEmpty || aday.beyanname == 'Diğer') && cins != null) {
    aday.beyanname = cins;
  }
  if (aday.tur == null && a.contains('tahakkuk fisi')) aday.tur = BelgeTuru.tahakkuk;

  // Beyanname cinsi tahakkukta hâlâ boşsa metinde ara
  if (aday.tur == BelgeTuru.tahakkuk && aday.beyanname.isEmpty) {
    if (a.contains('katma deger')) {
      aday.beyanname = 'KDV';
    } else if (a.contains('muhtasar')) {
      aday.beyanname = 'Muhtasar ve Prim Hizmet';
    } else if (a.contains('gecici vergi')) {
      aday.beyanname = 'Geçici Vergi';
    } else if (a.contains('kurumlar vergisi')) {
      aday.beyanname = 'Kurumlar Vergisi';
    } else if (a.contains('gelir vergisi')) {
      aday.beyanname = 'Gelir Vergisi';
    }
  }

  // Beyanname türü (BYN) metinden de bulunamadıysa gevşek ara
  if (aday.tur == null && byn) {
    final bas = a.length > 900 ? a.substring(0, 900) : a;
    if (bas.contains('gecici vergi')) {
      aday.tur = BelgeTuru.geciciVergi;
    } else if (bas.contains('katma deger')) {
      aday.tur = BelgeTuru.kdvBeyannamesi;
    } else if (bas.contains('muhtasar')) {
      aday.tur = BelgeTuru.muhtasarBeyannamesi;
    } else if (bas.contains('kurumlar vergisi')) {
      aday.tur = BelgeTuru.kurumlarVergisi;
    } else if (bas.contains('gelir vergisi')) {
      aday.tur = BelgeTuru.gelirVergisi;
    }
  }

  // Yıl: önce dosya adı, sonra gevşek metin
  if (aday.yil == null) {
    final y = RegExp(r'(?<!\d)(20\d\d)(?!\d)').firstMatch(dosya)?[1] ??
        RegExp(r'\byil[i]?\b[^0-9]{0,60}(20\d\d)').firstMatch(a)?[1];
    if (y != null) aday.yil = int.parse(y);
  }

  // Dönem
  final tur = aday.tur;
  if (tur == null) return;
  final efektifCins = tur == BelgeTuru.tahakkuk ? aday.beyanname : '';
  final geciciMi = tur == BelgeTuru.geciciVergi || efektifCins == 'Geçici Vergi';
  final yillikMi = tur == BelgeTuru.gelirVergisi ||
      tur == BelgeTuru.kurumlarVergisi ||
      efektifCins == 'Gelir Vergisi' ||
      efektifCins == 'Kurumlar Vergisi';

  if (aday.donem == null || !_donemler(tur).contains(aday.donem)) {
    int? ay = _ayNoBul(RegExp('($aylarRe)').firstMatch(dosya)?[1]);
    if (geciciMi) {
      final n = int.tryParse(RegExp(r'(\d)\s*\.\s*donem').firstMatch(a)?[1] ?? '');
      if (n != null && n >= 1 && n <= 4) {
        aday.donem = _geciciDonemler[n - 1];
      } else if (ay != null) {
        aday.donem = _geciciDonemler[((ay - 1) ~/ 3).clamp(0, 3)];
      }
    } else if (yillikMi) {
      aday.donem = 'Yıllık';
    } else {
      ay ??= _ayNoBul(RegExp('\\bay\\b\\s*:?\\s*($aylarRe)\\b').firstMatch(a)?[1]);
      if (ay == null && !thk) {
        final bas = a.length > 900 ? a.substring(0, 900) : a;
        ay = _ayNoBul(RegExp('\\b($aylarRe)\\b').firstMatch(bas)?[1]);
      }
      if (ay != null) aday.donem = _aylar[ay - 1];
    }
  }
}

_Aday _coz(String ad, Uint8List bytes, String metin, List<Firma> firmalar) {
  final aday = _Aday(ad, bytes);
  final a = _katla(metin.replaceAll(RegExp(r'\s+'), ' '));
  final dosya = _katla(ad);
  String? unvan;
  String? vkn;
  int? ay;

  if (a.trim().isEmpty) {
    // Metin okunamadıysa dosya adından tahmin et
    final byn = dosya.contains('_byn') || dosya.contains('byn.');
    final thk = dosya.contains('_thk') || dosya.contains('thk.') || dosya.contains('tahakkuk');
    String? b;
    if (dosya.contains('kdv')) {
      b = 'KDV';
    } else if (dosya.contains('muhtasar')) {
      b = 'Muhtasar ve Prim Hizmet';
    } else if (dosya.contains('gecici')) {
      b = 'Geçici Vergi';
    } else if (dosya.contains('gelir')) {
      b = 'Gelir Vergisi';
    } else if (dosya.contains('kurum')) {
      b = 'Kurumlar Vergisi';
    }
    if (thk && b != null) {
      aday.tur = BelgeTuru.tahakkuk;
      aday.beyanname = b;
    } else if (byn && b != null) {
      aday.tur = switch (b) {
        'KDV' => BelgeTuru.kdvBeyannamesi,
        'Muhtasar ve Prim Hizmet' => BelgeTuru.muhtasarBeyannamesi,
        'Geçici Vergi' => BelgeTuru.geciciVergi,
        'Gelir Vergisi' => BelgeTuru.gelirVergisi,
        _ => BelgeTuru.kurumlarVergisi,
      };
    }
    final y = RegExp(r'(20\d\d)').firstMatch(dosya)?[1];
    if (y != null) aday.yil = int.parse(y);
    for (final k in _ayAnahtar) {
      if (dosya.contains(k)) {
        ay = _ayNoBul(k);
        break;
      }
    }
    if (ay != null && aday.tur != null && _donemler(aday.tur!).contains(_aylar[ay - 1])) aday.donem = _aylar[ay - 1];
    aday.not = 'PDF metni okunamadı, dosya adından tahmin edildi';
  } else if (a.contains('sosyal guvenlik kurumu')) {
    // SGK belgeleri: vergi no yok, unvan ile eşleştirilir
    final tahakkuk = a.contains('tahakkuk fisi');
    if (tahakkuk) {
      aday.tur = BelgeTuru.tahakkuk;
      aday.beyanname = 'SGK Prim';
    } else if (a.contains('hizmet')) {
      aday.tur = BelgeTuru.sgkHizmet;
    }
    final p = RegExp(r'ait oldugu yil\s*/\s*ay\s*:?\s*(\d{4})\s*/\s*(\d{1,2})').firstMatch(a);
    if (p != null) {
      aday.yil = int.parse(p[1]!);
      ay = int.parse(p[2]!);
      if (ay >= 1 && ay <= 12) aday.donem = _aylar[ay - 1];
    }
    unvan = RegExp(r'\bunvani\s*:?\s*(.+?)\s+sgm').firstMatch(a)?[1];
  } else {
    vkn = RegExp(r'vergi kimlik numarasi[^0-9]{0,40}(\d{10,11})').firstMatch(a)?[1];
    if (a.contains('tahakkuk fisi')) {
      // Vergi tahakkuk fişi
      aday.tur = BelgeTuru.tahakkuk;
      final kod = RegExp(r'ana vergi kodu\s*(\d{4})').firstMatch(a)?[1];
      final baslik = RegExp(r'ana vergi kodu\s*\d{4}(.{0,200}?)(?:duzenleme|kabul tarihi)').firstMatch(a)?[1] ?? '';
      String b = switch (kod) {
        '0015' => 'KDV',
        '0003' => 'Muhtasar ve Prim Hizmet',
        '0032' || '0033' => 'Geçici Vergi',
        '0001' => 'Gelir Vergisi',
        _ => '',
      };
      if (b.isEmpty) {
        if (baslik.contains('gecici')) {
          b = 'Geçici Vergi';
        } else if (baslik.contains('katma deger')) {
          b = 'KDV';
        } else if (baslik.contains('muhtasar')) {
          b = 'Muhtasar ve Prim Hizmet';
        } else if (baslik.contains('damga')) {
          b = 'Damga Vergisi';
        } else if (baslik.contains('kurumlar')) {
          b = 'Kurumlar Vergisi';
        } else if (baslik.contains('gelir vergisi')) {
          b = 'Gelir Vergisi';
        } else {
          b = 'Diğer';
        }
      }
      aday.beyanname = b;
      final d = RegExp(r'(\d{2})/(\d{4})\s*-\s*(\d{2})/(\d{4})').firstMatch(a);
      if (d != null) {
        final bas = int.parse(d[1]!);
        final son = int.parse(d[3]!);
        aday.yil = int.parse(d[2]!);
        if (bas == son && bas >= 1 && bas <= 12) {
          aday.donem = _aylar[bas - 1];
        } else if (bas == 1 && son == 12) {
          aday.donem = 'Yıllık';
        } else if (son - bas == 2 && (bas - 1) % 3 == 0) {
          aday.donem = _geciciDonemler[(bas - 1) ~/ 3];
        }
      }
    } else {
      // Beyanname (e-Beyanname onaylı PDF)
      final bas = a.length > 700 ? a.substring(0, 700) : a;
      if (bas.contains('gecici vergi beyannamesi')) {
        aday.tur = BelgeTuru.geciciVergi;
      } else if (bas.contains('katma deger vergisi beyannamesi')) {
        aday.tur = BelgeTuru.kdvBeyannamesi;
      } else if (bas.contains('muhtasar')) {
        aday.tur = BelgeTuru.muhtasarBeyannamesi;
      } else if (bas.contains('yillik gelir vergisi beyannamesi')) {
        aday.tur = BelgeTuru.gelirVergisi;
      } else if (bas.contains('kurumlar vergisi beyannamesi')) {
        aday.tur = BelgeTuru.kurumlarVergisi;
      }
      final y = RegExp(r'donem tipi\s*yil\w*\s*(\d{4})').firstMatch(a)?[1] ?? RegExp(r'\b(20\d\d)\b').firstMatch(bas)?[1];
      if (y != null) aday.yil = int.parse(y);
      switch (aday.tur) {
        case BelgeTuru.kdvBeyannamesi || BelgeTuru.muhtasarBeyannamesi:
          ay = _ayNoBul(RegExp(r'\bay\s+(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)\b')
              .firstMatch(a)?[1]);
          if (ay != null) aday.donem = _aylar[ay - 1];
        case BelgeTuru.geciciVergi:
          final n = int.tryParse(RegExp(r'(\d)\.\s*donem').firstMatch(a)?[1] ?? '');
          if (n != null && n >= 1 && n <= 4) aday.donem = _geciciDonemler[n - 1];
        case BelgeTuru.gelirVergisi || BelgeTuru.kurumlarVergisi:
          aday.donem = 'Yıllık';
        default:
      }
    }
  }

  _eksikleriTamamla(aday, dosya, a);

  // Firma eşleştirme
  if (unvan == null) {
    // Adaylar: önce "Vergi Kimlik Numarası" etiketinden sonraki ilk numara (mükellef),
    // sonra belgenin üst kısmındaki diğer 10-11 haneli numaralar. Belgenin ilerisindeki
    // numaralar (müşavir, çalışanlar, kiraya verenler) bilerek dikkate alınmaz.
    String rk(String x) => x.replaceAll(RegExp(r'[^0-9]'), '');
    final adaylar = <String>[];
    if (vkn != null) adaylar.add(vkn);
    final ust = metin.length > 2500 ? metin.substring(0, 2500) : metin;
    for (final m in RegExp(r'(?<!\d)(\d{10,11})(?!\d)').allMatches('$ust ${ad.replaceAll(RegExp(r'[^0-9]+'), ' ')}')) {
      final no = m[1]!;
      if (!adaylar.contains(no)) adaylar.add(no);
    }
    for (final no in adaylar) {
      Firma? f0;
      for (final f in firmalar) {
        if ((f.vergiNo.isNotEmpty && rk(f.vergiNo) == no) || (f.tcNo.isNotEmpty && rk(f.tcNo) == no)) {
          f0 = f;
          break;
        }
      }
      if (f0 != null) {
        aday.firmaId = f0.id;
        aday.not = no == vkn ? 'Vergi/TC no ($no) ile eşleşti' : 'Belgedeki $no numarası ile eşleşti';
        break;
      }
    }
    if (aday.firmaId == null && vkn != null) aday.not = 'Bu vergi/TC no ($vkn) hiçbir firmada kayıtlı değil';
  } else if (unvan != null) {
    final aranan = _adSade(unvan);
    final eslesen = <Firma>[];
    for (final f in firmalar) {
      final tam = _adSade(f.unvan);
      final parcalar = f.unvan.split('/').map(_adSade);
      if (tam == aranan || parcalar.contains(aranan) || (aranan.length >= 8 && tam.contains(aranan))) {
        eslesen.add(f);
      }
    }
    if (eslesen.length == 1) {
      aday.firmaId = eslesen.first.id;
      aday.not = 'SGK unvanı ile eşleşti';
    } else if (eslesen.length > 1) {
      aday.not = 'SGK fişindeki unvan birden fazla firmayla eşleşti, firmayı seç';
    } else {
      aday.not = 'SGK fişindeki unvan ("$unvan") firmalarla eşleşmedi';
    }
  }

  // Yedek eşleştirme: yukarıdaki yöntemler firmayı bulamadıysa tüm metinde ara
  if (aday.firmaId == null) {
    final metinAd = ' ${_adSade(metin.length > 1500 ? metin.substring(0, 1500) : metin)} ';
    final dosyaAd = ' ${_adSade(ad)} ';
    Firma? bulunan;
    var kaynak = '';
    // 2) Firma unvanı metinde veya dosya adında geçiyor mu (en uzun eşleşme kazanır)
    if (bulunan == null) {
      var enUzun = 0;
      for (final f in firmalar) {
        final tam = _adSade(f.unvan);
        if (tam.length < 6) continue;
        if ((metinAd.contains(' $tam ') || dosyaAd.contains(' $tam ')) && tam.length > enUzun) {
          enUzun = tam.length;
          bulunan = f;
          kaynak = 'Firma unvanı belgede bulundu';
        }
      }
    }
    if (bulunan != null) {
      aday.firmaId = bulunan.id;
      aday.not = kaynak;
    } else if (metin.trim().isNotEmpty) {
      final ozet = metin.replaceAll(RegExp(r'\s+'), ' ').trim();
      final kisa = ozet.substring(0, ozet.length < 90 ? ozet.length : 90);
      aday.not = '${aday.not.isEmpty ? '' : '${aday.not}. '}Firma bulunamadı (okunan metin: $kisa…)';
    }
  }
  return aday;
}

extension _TopluYukleme on _BeyannamelerSayfasiState {
  Future<void> _topluYukle() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (r == null || !mounted) return;
    final dosyalar = r.files.where((f) => f.bytes != null).toList();
    if (dosyalar.isEmpty) return;

    final ilerleme = ValueNotifier<int>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: ilerleme,
          builder: (c, v, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Text("PDF'ler okunuyor: $v/${dosyalar.length}"),
          ]),
        ),
      ),
    );

    final firmalar = FirmaDeposu.ornek.liste;
    final adaylar = <_Aday>[];
    for (final f in dosyalar) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final metin = await _pdfMetni(f.bytes!);
      adaylar.add(_coz(f.name, f.bytes!, metin, firmalar));
      ilerleme.value = adaylar.length;
    }

    // Daha önce yüklenmiş mi?
    try {
      final ids = {for (final a in adaylar) if (a.firmaId != null) a.firmaId!}.toList();
      if (ids.isNotEmpty) {
        final mevcut = await _db.from('belgeler').select('firma_id, tur, beyanname, yil, donem, dosya_adi').inFilter('firma_id', ids);
        for (final a in adaylar) {
          if (a.firmaId == null) continue;
          for (final m in mevcut) {
            if (m['firma_id'] != a.firmaId) continue;
            final ayniDosya = m['dosya_adi'] == a.dosyaAdi;
            final ayniBelge = a.tamam &&
                m['tur'] == a.tur!.name &&
                m['beyanname'] == (a.tur == BelgeTuru.tahakkuk ? a.beyanname : '') &&
                m['yil'] == a.yil &&
                m['donem'] == a.donem;
            if (ayniDosya || ayniBelge) {
              a.tekrar = true;
              a.not = 'Bu belge zaten yüklü';
              break;
            }
          }
        }
      }
    } catch (_) {}
    for (final a in adaylar) {
      a.sec = a.tamam && !a.tekrar;
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // ilerleme penceresi

    final secenekler = <(String, BelgeTuru, String)>[
      for (final t in BelgeTuru.values)
        if (t == BelgeTuru.tahakkuk)
          for (final b in _tahakkukBeyannameleri) ('Tahakkuk fişi: $b', t, b)
        else
          (t.ad, t, ''),
    ];
    var mesgul = false;
    String? hata;
    final yillar = [for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 6; y--) y];

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setD) {
          final yuklenecek = adaylar.where((a) => a.sec && a.tamam).length;
          return AlertDialog(
            title: Text('${adaylar.length} PDF okundu'),
            content: SizedBox(
              width: 920,
              child: ListView(shrinkWrap: true, children: [
                const Text(
                  'Firma, belge türü ve dönem PDF içinden okundu. Kırmızı olanları kontrol et, gerekirse düzelt. '
                  'Seçili olanlar yüklenecek.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                for (final a in adaylar)
                  Card(
                    elevation: 0,
                    color: a.tekrar ? const Color(0xFFF1F1F1) : (a.tamam ? const Color(0xFFEAF6EC) : const Color(0xFFFDECEA)),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Checkbox(
                            value: a.sec && a.tamam,
                            onChanged: a.tamam ? (v) => setD(() => a.sec = v ?? false) : null,
                          ),
                          Expanded(
                            child: Text(a.dosyaAdi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ]),
                        if (a.not.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 4),
                            child: Text(a.not,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: a.firmaId == null || a.tekrar ? const Color(0xFFB3261E) : Colors.black87)),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            SizedBox(
                              width: 250,
                              child: DropdownButton<int>(
                                isExpanded: true,
                                isDense: true,
                                value: firmalar.any((f) => f.id == a.firmaId) ? a.firmaId : null,
                                hint: const Text('Firma seç'),
                                items: [
                                  for (final f in firmalar)
                                    DropdownMenuItem(value: f.id, child: Text(f.unvan, overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setD(() {
                                  a.firmaId = v;
                                  a.tekrar = false;
                                  a.sec = a.tamam;
                                }),
                              ),
                            ),
                            SizedBox(
                              width: 230,
                              child: DropdownButton<int>(
                                isExpanded: true,
                                isDense: true,
                                value: () {
                                  if (a.tur == null) return null;
                                  final i = secenekler.indexWhere(
                                      (s) => s.$2 == a.tur && (a.tur != BelgeTuru.tahakkuk || s.$3 == a.beyanname));
                                  return i < 0 ? null : i;
                                }(),
                                hint: const Text('Belge türü'),
                                items: [
                                  for (var i = 0; i < secenekler.length; i++)
                                    DropdownMenuItem(value: i, child: Text(secenekler[i].$1, overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (i) => setD(() {
                                  if (i == null) return;
                                  a.tur = secenekler[i].$2;
                                  a.beyanname = secenekler[i].$3;
                                  if (!_donemler(a.tur!).contains(a.donem)) a.donem = null;
                                  a.sec = a.tamam;
                                }),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: DropdownButton<int>(
                                isExpanded: true,
                                isDense: true,
                                value: yillar.contains(a.yil) ? a.yil : null,
                                hint: const Text('Yıl'),
                                items: [for (final y in yillar) DropdownMenuItem(value: y, child: Text('$y'))],
                                onChanged: (v) => setD(() {
                                  a.yil = v;
                                  a.sec = a.tamam;
                                }),
                              ),
                            ),
                            SizedBox(
                              width: 250,
                              child: DropdownButton<String>(
                                isExpanded: true,
                                isDense: true,
                                value: (a.tur != null && _donemler(a.tur!).contains(a.donem)) ? a.donem : null,
                                hint: const Text('Dönem'),
                                items: [
                                  if (a.tur != null)
                                    for (final d in _donemler(a.tur!))
                                      DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) => setD(() {
                                  a.donem = v;
                                  a.sec = a.tamam;
                                }),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                if (hata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(hata!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(
                onPressed: (mesgul || yuklenecek == 0)
                    ? null
                    : () async {
                        setD(() {
                          mesgul = true;
                          hata = null;
                        });
                        try {
                          final damga = DateTime.now().microsecondsSinceEpoch;
                          var sira = 0;
                          for (final a in adaylar.where((a) => a.sec && a.tamam)) {
                            final yol = 'firma_${a.firmaId}/belgeler/${damga}_${sira++}.pdf';
                            await _db.storage.from('belgeler').uploadBinary(yol, a.bytes,
                                fileOptions: const FileOptions(contentType: 'application/pdf'));
                            await _db.from('belgeler').insert({
                              'firma_id': a.firmaId,
                              'tur': a.tur!.name,
                              'beyanname': a.tur == BelgeTuru.tahakkuk ? a.beyanname : '',
                              'yil': a.yil,
                              'donem': a.donem,
                              'dosya_adi': a.dosyaAdi,
                              'yol': yol,
                            });
                          }
                          await _getir();
                          if (c.mounted) Navigator.pop(c);
                          _mesaj('$yuklenecek belge ilgili firmalara yüklendi.');
                        } catch (e) {
                          setD(() {
                            hata = 'Yüklenemedi: $e';
                            mesgul = false;
                          });
                        }
                      },
                child: Text(mesgul ? 'Yükleniyor...' : 'Seçilenleri yükle ($yuklenecek)'),
              ),
            ],
          );
        },
      ),
    );
  }
}
