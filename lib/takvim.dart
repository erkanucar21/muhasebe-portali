part of 'beyanname_kontrol.dart';

class _TakvimOlay {
  final DateTime t;
  final String baslik;
  final String detay;
  final int tur; // 0 beyanname, 1 not, 2 personel, 3 belge
  _TakvimOlay(this.t, this.baslik, this.detay, this.tur);
}

const _takvimTurAd = ['Beyanname son günleri', 'Notlar / hatırlatmalar', 'Personel sözleşmeleri', 'Belge geçerlilikleri'];
const _takvimRenk = [Color(0xFF1565C0), Color(0xFFEF6C00), Color(0xFF6A1B9A), Color(0xFFC62828)];

/// Yıllık takvim: beyanname son günleri, not hatırlatmaları, sözleşme ve belge bitişleri. Sadece yönetici.
class TakvimSayfasi extends StatefulWidget {
  const TakvimSayfasi({super.key});
  @override
  State<TakvimSayfasi> createState() => _TakvimSayfasiState();
}

class _TakvimSayfasiState extends State<TakvimSayfasi> {
  final _db = Supabase.instance.client;
  late int _yil;
  late int _ay;
  bool _yukleniyor = true;
  String? _hata;
  final List<_TakvimOlay> _olaylar = [];
  final Set<int> _gizli = {};

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _yil = n.year;
    _ay = n.month;
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      if (FirmaDeposu.ornek.liste.isEmpty) await FirmaDeposu.ornek.yukle();
      await _istisnalariYukle();
      await _ozelYukle();
      _olaylar.clear();
      _beyannameOlaylari();
      await _digerOlaylar();
      _olaylar.sort((a, b) => a.t.compareTo(b.t));
      _abonelikGuncelle();
    } catch (e) {
      _hata = 'Takvim hazırlanamadı: $e';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  void _beyannameOlaylari() {
    final dedupe = <String>{};
    for (final y in [_yil - 1, _yil]) {
      for (var a = 1; a <= 12; a++) {
        for (final tur in _tumTurler(a)) {
          if (tur == _edefter) continue;
          for (final (etiket, tarih) in _sonTarihler(tur, y, a)) {
            if (tarih.year != _yil) continue;
            final ad = tur == _vergi ? '${etiket.trim()} vergi beyannamesi' : (_ozelBul(tur)?.ad ?? tur);
            final donem = tur == _vergi ? '' : '${_aylar[a - 1]} $y dönemi';
            final anahtar = '${tarih.toIso8601String()}|$ad|$donem';
            if (!dedupe.add(anahtar)) continue;
            _olaylar.add(_TakvimOlay(tarih, ad, donem, 0));
          }
        }
      }
    }
    // E-Defter: firmaya göre farklı olduğu için tarih başına firmalar toplanır
    final gruplar = <DateTime, Set<String>>{};
    for (final f in FirmaDeposu.ornek.liste) {
      if (!f.eDefter) continue;
      for (final y in [_yil - 1, _yil]) {
        for (var a = 1; a <= 12; a++) {
          final t = _edefterSonGun(f, y, a).$2;
          if (t.year == _yil) (gruplar[DateTime(t.year, t.month, t.day)] ??= {}).add(f.unvan);
        }
      }
    }
    gruplar.forEach((t, firmalar) {
      _olaylar.add(_TakvimOlay(t, 'E-Defter berat yükleme (${firmalar.length} firma)', firmalar.join(', '), 0));
    });
  }

  Future<void> _digerOlaylar() async {
    try {
      final r = await _db.from('ozet_not').select('metin, hatirlatma, firma_id').eq('tamam', false).not('hatirlatma', 'is', null);
      for (final n in r) {
        final t = DateTime.parse(n['hatirlatma'] as String);
        if (t.year != _yil) continue;
        final f = n['firma_id'] == null ? null : FirmaDeposu.ornek.bul((n['firma_id'] as num).toInt());
        _olaylar.add(_TakvimOlay(t, '${n['metin']}', f?.unvan ?? '', 1));
      }
    } catch (_) {}
    try {
      final r = await _db.from('personel').select('ad, firma_id, sozlesme_bitis').not('sozlesme_bitis', 'is', null).filter('cikis', 'is', null);
      for (final p in r) {
        final t = DateTime.parse(p['sozlesme_bitis'] as String);
        if (t.year != _yil) continue;
        final f = FirmaDeposu.ornek.bul((p['firma_id'] as num).toInt());
        _olaylar.add(_TakvimOlay(t, '${p['ad']}: sözleşme bitişi', f?.unvan ?? '', 2));
      }
    } catch (_) {}
    try {
      final r = await _db.from('firma_belge').select('ad, firma_id, gecerlilik').not('gecerlilik', 'is', null);
      for (final b in r) {
        final t = DateTime.parse(b['gecerlilik'] as String);
        if (t.year != _yil) continue;
        final f = FirmaDeposu.ornek.bul((b['firma_id'] as num).toInt());
        _olaylar.add(_TakvimOlay(t, '${b['ad']}: geçerlilik bitişi', f?.unvan ?? '', 3));
      }
    } catch (_) {}
  }

  List<_TakvimOlay> _gorunen() => [for (final o in _olaylar) if (!_gizli.contains(o.tur)) o];

  List<_TakvimOlay> _gunOlaylari(List<_TakvimOlay> l, int ay, int gun) =>
      [for (final o in l) if (o.t.month == ay && o.t.day == gun) o];

  String _ics(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

  String _gunKod(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// Aynı olay güncellemede aynı kimliği taşısın diye kararlı kısa özet.
  String _kararliKod(String s) {
    var h = 5381;
    for (final c in s.codeUnits) {
      h = ((h * 33) ^ c) & 0x7fffffff;
    }
    return h.toRadixString(36);
  }

  String _icsMetni(List<_TakvimOlay> olaylar, {bool abonelik = false}) {
    final b = StringBuffer()
      ..write('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Muhasebe Portali//TR\r\nCALSCALE:GREGORIAN\r\n');
    if (abonelik) {
      b.write('X-WR-CALNAME:Muhasebe Portalı\r\nREFRESH-INTERVAL;VALUE=DURATION:PT6H\r\nX-PUBLISHED-TTL:PT6H\r\n');
    }
    final damga = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first;
    final gorulen = <String, int>{};
    for (final o in olaylar) {
      final bitis = DateTime(o.t.year, o.t.month, o.t.day + 1);
      final anahtar = '${_gunKod(o.t)}-${o.tur}-${_kararliKod('${o.baslik}|${o.detay}')}';
      final sira = gorulen.update(anahtar, (v) => v + 1, ifAbsent: () => 0);
      b
        ..write('BEGIN:VEVENT\r\n')
        ..write('UID:muhasebe-$anahtar-$sira@portal\r\n')
        ..write('DTSTAMP:${damga}Z\r\n')
        ..write('DTSTART;VALUE=DATE:${_gunKod(o.t)}\r\n')
        ..write('DTEND;VALUE=DATE:${_gunKod(bitis)}\r\n')
        ..write('SUMMARY:${_ics(o.detay.isEmpty || o.tur == 0 ? o.baslik : '${o.baslik} - ${o.detay}')}\r\n');
      if (o.tur == 0 && o.detay.isNotEmpty) b.write('DESCRIPTION:${_ics(o.detay)}\r\n');
      // bir gün önce 09:00 ve o gün 09:00 bildirim
      final baslik = _ics(o.baslik);
      b
        ..write('BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Yarın: $baslik\r\nTRIGGER:-PT15H\r\nEND:VALARM\r\n')
        ..write('BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Bugün: $baslik\r\nTRIGGER:PT9H\r\nEND:VALARM\r\n');
      b.write('END:VEVENT\r\n');
    }
    b.write('END:VCALENDAR\r\n');
    return b.toString();
  }

  Future<void> _icsAktar() async {
    try {
      await bordroKaydet('takvim_$_yil', Uint8List.fromList(utf8.encode(_icsMetni(_gorunen()))), 'ics');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Takvim dosyası indirildi. Mac\'te çift tıklayıp iCloud takvimine eklersen iPhone\'a da gelir. Bildirimler bir gün önce ve o gün 09:00\'da çalar.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İndirilemedi: $e')));
    }
  }

  // ------------------------------------------------------------ canlı abonelik
  String _yeniJeton() {
    const harfler = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(40, (_) => harfler[r.nextInt(harfler.length)]).join();
  }

  String _abonelikAdresi(String jeton) {
    final taban = _db.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '');
    return '$taban/functions/v1/takvim?t=$jeton';
  }

  /// Abonelik kurulmuşsa takvimin güncel halini sessizce yayınlar (yalnızca bu yılın takvimi).
  Future<void> _abonelikGuncelle() async {
    if (_yil != DateTime.now().year) return;
    try {
      final r = await _db.from('takvim_abonelik').select('token').eq('id', 1).maybeSingle();
      if (r == null) return;
      await _db.from('takvim_abonelik').update({'ics': _icsMetni(_olaylar, abonelik: true), 'guncelleme': DateTime.now().toUtc().toIso8601String()}).eq('id', 1);
    } catch (_) {}
  }

  Future<void> _aboneOl() async {
    try {
      final r = await _db.from('takvim_abonelik').select('token').eq('id', 1).maybeSingle();
      var jeton = r == null ? _yeniJeton() : r['token'] as String;
      await _db.from('takvim_abonelik').upsert({'id': 1, 'token': jeton, 'ics': _icsMetni(_olaylar, abonelik: true), 'guncelleme': DateTime.now().toUtc().toIso8601String()});
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) {
            final adres = _abonelikAdresi(jeton);
            final webcal = adres.replaceFirst('https://', 'webcal://');
            return AlertDialog(
              title: const Text('Telefon takvimine abone ol'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Bu bağlantı size özeldir; firma adlarını ve tarihleri içerir, başkasıyla paylaşmayın.'),
                    const SizedBox(height: 10),
                    SelectableText(webcal, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                    const Text('iPhone: Ayarlar > Takvim > Hesaplar > Hesap Ekle > Diğer > Abone Olunan Takvim Ekle, bağlantıyı yapıştırın.\n'
                        'Mac: Takvim > Dosya > Yeni Takvim Aboneliği.\n'
                        'Google Takvim: Diğer takvimler > URL\'den ekle (https ile başlayan adresi kullanın).', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    const Text('Takvim, portalda Takvim sayfası her açıldığında güncellenir; telefon birkaç saatte bir yeniler. Portalı hiç açmazsanız yeni olaylar gelmez.', style: TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    jeton = _yeniJeton();
                    try {
                      await _db.from('takvim_abonelik').update({'token': jeton}).eq('id', 1);
                      set(() {});
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yenilenemedi: $e')));
                    }
                  },
                  child: const Text('Yeni bağlantı üret (eskisini iptal eder)'),
                ),
                TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: webcal)), child: const Text('Kopyala')),
                FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Abonelik kurulamadı (supabase_takvim_abonelik.sql çalıştırıldı mı?): $e')));
    }
  }

  void _gunAc(int gun, List<_TakvimOlay> l) {
    final metin = TextEditingController();
    int? firmaId;
    var kaydediyor = false;
    var ekleAcik = false;
    String? hata;
    final firmalar = [...FirmaDeposu.ornek.liste]..sort((x, y) => x.unvan.compareTo(y.unvan));
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('$gun ${_aylar[_ay - 1]} $_yil'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (l.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Bu gün için not veya kayıt yok.', style: TextStyle(color: Colors.black87))),
                for (final o in l) _olaySatiri(o),
                const Divider(height: 24),
                if (!ekleAcik)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(onPressed: () => set(() => ekleAcik = true), icon: const Icon(Icons.add, size: 18), label: const Text('Not ekle')),
                  )
                else ...[
                  const Text('Not ekle', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: metin,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Bu güne hatırlatma notu yaz', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    initialValue: firmaId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Firma (isteğe bağlı)', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Firma yok')),
                      for (final f in firmalar) DropdownMenuItem<int?>(value: f.id, child: Text(f.unvan, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => set(() => firmaId = v),
                  ),
                  if (hata != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hata!, style: const TextStyle(color: Colors.red))),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
            if (ekleAcik)
            FilledButton.icon(
              onPressed: kaydediyor
                  ? null
                  : () async {
                      final m = metin.text.trim();
                      if (m.isEmpty) {
                        set(() => hata = 'Not metnini yaz.');
                        return;
                      }
                      set(() {
                        kaydediyor = true;
                        hata = null;
                      });
                      try {
                        final t = DateTime(_yil, _ay, gun);
                        await _db.from('ozet_not').insert({
                          'metin': m,
                          'hatirlatma': '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}',
                          'firma_id': firmaId,
                          'tamam': false,
                        });
                        if (c.mounted) Navigator.pop(c);
                        await _yukle();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not eklendi.')));
                      } catch (e) {
                        set(() {
                          kaydediyor = false;
                          hata = 'Eklenemedi (supabase_ozet_not.sql çalıştırıldı mı, Özet izniniz var mı?): $e';
                        });
                      }
                    },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _olaySatiri(_TakvimOlay o) => ListTile(
        dense: true,
        leading: Icon(Icons.circle, size: 12, color: _takvimRenk[o.tur]),
        title: Text(o.baslik),
        subtitle: o.detay.isEmpty ? null : Text(o.detay),
      );

  Widget _izgara(List<_TakvimOlay> l) {
    final ilk = DateTime(_yil, _ay, 1);
    final gunSayisi = DateTime(_yil, _ay + 1, 0).day;
    final bosluk = ilk.weekday - 1;
    final satir = ((bosluk + gunSayisi) / 7).ceil();
    final bugun = DateTime.now();
    const gunler = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return Column(children: [
      Row(children: [
        for (final g in gunler)
          Expanded(child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(g, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87))))),
      ]),
      for (var s = 0; s < satir; s++)
        Row(children: [
          for (var k = 0; k < 7; k++)
            Builder(builder: (c) {
              final gun = s * 7 + k - bosluk + 1;
              if (gun < 1 || gun > gunSayisi) return const Expanded(child: SizedBox(height: 96));
              final ol = _gunOlaylari(l, _ay, gun);
              final bugunMu = bugun.year == _yil && bugun.month == _ay && bugun.day == gun;
              return Expanded(
                child: InkWell(
                  onTap: () => _gunAc(gun, ol),
                  child: Container(
                    height: 96,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: bugunMu ? const Color(0xFFE3F2FD) : Colors.white,
                      border: Border.all(color: Colors.black12, width: 0.5),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$gun', style: TextStyle(fontSize: 12, fontWeight: bugunMu ? FontWeight.w800 : FontWeight.w500, color: k >= 5 ? Colors.black87 : Colors.black87)),
                      for (final o in ol.take(3))
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          width: double.infinity,
                          decoration: BoxDecoration(color: _takvimRenk[o.tur].withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                          child: Text(o.baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: _takvimRenk[o.tur])),
                        ),
                      if (ol.length > 3) Text('+${ol.length - 3}', style: const TextStyle(fontSize: 10, color: Colors.black87)),
                    ]),
                  ),
                ),
              );
            }),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    final l = _gorunen();
    final buAy = [for (final o in l) if (o.t.month == _ay) o];
    final genis = MediaQuery.of(context).size.width >= 720;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Takvim', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Önceki yıl', onPressed: () { _yil--; _yukle(); }, icon: const Icon(Icons.chevron_left)),
              Text('$_yil', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(tooltip: 'Sonraki yıl', onPressed: () { _yil++; _yukle(); }, icon: const Icon(Icons.chevron_right)),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _icsAktar, icon: const Icon(Icons.event_available_outlined, size: 18), label: const Text('Takvime aktar (.ics)')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _aboneOl, icon: const Icon(Icons.sync_outlined, size: 18), label: const Text('Telefona abone ol')),
            ]),
            if (_hata != null) Text(_hata!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (var t = 0; t < 4; t++)
                FilterChip(
                  avatar: Icon(Icons.circle, size: 12, color: _takvimRenk[t]),
                  label: Text(_takvimTurAd[t]),
                  selected: !_gizli.contains(t),
                  onSelected: (v) => setState(() => v ? _gizli.remove(t) : _gizli.add(t)),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var a = 1; a <= 12; a++)
                ChoiceChip(
                  label: Text('${_aylar[a - 1]} (${l.where((o) => o.t.month == a).length})'),
                  selected: _ay == a,
                  onSelected: (_) => setState(() => _ay = a),
                ),
            ]),
            const SizedBox(height: 12),
            if (genis) _izgara(l),
            const Padding(
              padding: EdgeInsets.only(top: 14, bottom: 6),
              child: Text('Bu ayın listesi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Card(
              elevation: 0,
              color: Colors.white,
              child: buAy.isEmpty
                  ? const ListTile(title: Text('Bu ay için kayıt yok.'))
                  : Column(children: [
                      for (final o in buAy)
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.circle, size: 12, color: _takvimRenk[o.tur]),
                          title: Text(o.baslik),
                          subtitle: o.detay.isEmpty ? null : Text(o.detay, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(_gunYaz(o.t), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                    ]),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Beyanname son günleri genel kurallara göre gösterilir (hafta sonu ertesi iş gününe kayar, kontrol listesindeki istisnalar dikkate alınır). '
                'Hangi firmanın hangi beyannameyi vermesi gerektiği için Kontrol listesine bak.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
