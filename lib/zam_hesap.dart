import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bordro_cikti.dart' show tl, bordroKaydet;
import 'hesap_cikti.dart';
import 'maas_alani.dart';

String _t(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Gecikme zammı ve pişmanlık zammı hesaplayıcı. Oran elle değiştirilebilir.
class ZamHesapSayfasi extends StatefulWidget {
  final bool gomulu; // true ise başka bir sayfanın içinde gösterilir (başlıksız, kaydırmasız)
  const ZamHesapSayfasi({super.key, this.gomulu = false});
  @override
  State<ZamHesapSayfasi> createState() => _ZamHesapSayfasiState();
}

class _ZamHesapSayfasiState extends State<ZamHesapSayfasi> {
  final _tutar = TextEditingController();
  final _oran = TextEditingController(text: '4,5');
  final _firma = TextEditingController();
  DateTime? _vade;
  DateTime _odeme = DateTime.now();
  bool _pismanlik = false;

  @override
  void initState() {
    super.initState();
    _tutar.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tutar.dispose();
    _oran.dispose();
    _firma.dispose();
    super.dispose();
  }

  double? _sayi(String s) => double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

  /// Ay kesirleri tam ay sayılır; ödeme vadeden sonra değilse 0.
  int _ayAdedi(DateTime vade, DateTime odeme) {
    final v = DateTime(vade.year, vade.month, vade.day);
    final o = DateTime(odeme.year, odeme.month, odeme.day);
    if (!o.isAfter(v)) return 0;
    var m = (o.year - v.year) * 12 + o.month - v.month;
    if (o.day > v.day) m++;
    return m < 1 ? 1 : m;
  }

  Future<void> _tarihSec(bool vade) async {
    final d = await showDatePicker(
      context: context,
      initialDate: (vade ? _vade : _odeme) ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (d != null) setState(() => vade ? _vade = d : _odeme = d);
  }

  String _mesaj(double tutar, double oran, int ay, double zam) {
    final ad = _firma.text.trim().isEmpty ? '' : 'Sayın ${_firma.text.trim()} yetkilisi, ';
    if (_pismanlik) {
      return '${ad}vadesi ${_t(_vade!)} olan ${tl(tutar)} TL tutarındaki verginin ${_t(_odeme)} tarihinde ödenmesi halinde '
          '%${oran.toString().replaceAll('.', ',')} aylık oranla $ay ay için ${tl(zam)} TL pişmanlık zammı hesaplanmıştır. '
          'Toplam ödenecek tutar ${tl(tutar + zam)} TL\'dir.';
    }
    return '${ad}vadesi ${_t(_vade!)} olan ${tl(tutar)} TL tutarındaki borcun ${_t(_odeme)} tarihinde ödenmesi halinde '
        '%${oran.toString().replaceAll('.', ',')} aylık oranla $ay ay için ${tl(zam)} TL gecikme zammı hesaplanmıştır. '
        'Toplam ödenecek tutar ${tl(tutar + zam)} TL\'dir.';
  }

  @override
  Widget build(BuildContext context) {
    final tutar = _sayi(_tutar.text);
    final oran = _sayi(_oran.text);
    final hazir = tutar != null && tutar > 0 && oran != null && _vade != null;
    final ay = hazir ? _ayAdedi(_vade!, _odeme) : 0;
    final tt = tutar ?? 0;
    final oo = oran ?? 0;
    final zam = hazir ? tt * oo / 100 * ay : 0.0;
    final icerik = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!widget.gomulu) const Text('Zam hesaplayıcı', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            if (!widget.gomulu) const SizedBox(height: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Gecikme zammı')),
                ButtonSegment(value: true, label: Text('Pişmanlık zammı')),
              ],
              selected: {_pismanlik},
              onSelectionChanged: (v) => setState(() => _pismanlik = v.first),
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: _firma, decoration: const InputDecoration(labelText: 'Firma (mesaj için, isteğe bağlı)'), onChanged: (_) => setState(() {})),
                  const SizedBox(height: 10),
                  MaasAlani(
                    controller: _tutar,
                    etiket: _pismanlik ? 'Vergi aslı (TL)' : 'Borç tutarı (TL)',
                    ipucu: '0,00',
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _tarihSec(true),
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(_vade == null ? 'Vade tarihi seç' : 'Vade: ${_t(_vade!)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _tarihSec(false),
                        icon: const Icon(Icons.event_available_outlined, size: 18),
                        label: Text('Ödeme: ${_t(_odeme)}'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _oran,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Aylık oran (%)', helperText: 'Cumhurbaşkanı kararıyla değişir. Güncel oranı kontrol edip gerekirse değiştir.'),
                    onChanged: (_) => setState(() {}),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (hazir)
              Card(
                elevation: 0,
                color: const Color(0xFFE8F5E9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (ay == 0)
                      const Text('Ödeme tarihi vadeden sonra değil, zam doğmaz.')
                    else ...[
                      Text('Geçen süre: $ay ay (ay kesirleri tam ay sayıldı)'),
                      const SizedBox(height: 4),
                      Text('${_pismanlik ? 'Pişmanlık' : 'Gecikme'} zammı: ${tl(zam)} TL', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Toplam ödenecek: ${tl(tt + zam)} TL', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _mesaj(tt, oo, ay, zam)));
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mesaj kopyalandı.')));
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Mükellef mesajını kopyala'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final ad = _pismanlik ? 'pismanlik_zammi' : 'gecikme_zammi';
                              await hesapPdfKaydet(ad, _pismanlik ? 'Pişmanlık zammı hesabı' : 'Gecikme zammı hesabı', [
                                (_pismanlik ? 'Pişmanlık zammı hesabı' : 'Gecikme zammı hesabı', ''),
                                if (_firma.text.trim().isNotEmpty) ('Firma', _firma.text.trim()),
                                (_pismanlik ? 'Vergi aslı' : 'Borç tutarı', tl(tt)),
                                ('Vade tarihi', _t(_vade!)),
                                ('Ödeme tarihi', _t(_odeme)),
                                ('Aylık oran', '%${oo.toString().replaceAll('.', ',')}'),
                                ('Geçen süre', '$ay ay'),
                                ('>${_pismanlik ? 'Pişmanlık' : 'Gecikme'} zammı', tl(zam)),
                                ('>Toplam ödenecek', tl(tt + zam)),
                              ]);
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF hazırlanamadı: $e')));
                            }
                          },
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: const Text('PDF indir'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await bordroKaydet(_pismanlik ? 'pismanlik_zammi' : 'gecikme_zammi',
                                  zamXlsx(pismanlik: _pismanlik, tutar: tt, vade: _vade!, odeme: _odeme, aylikOran: oo), 'xlsx');
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel hazırlanamadı: $e')));
                            }
                          },
                          icon: const Icon(Icons.table_chart_outlined, size: 18),
                          label: const Text('Excel indir (formüllü)'),
                        ),
                      ]),
                    ],
                  ]),
                ),
              )
            else
              const Text('Tutar, vade tarihi ve oranı gir.', style: TextStyle(color: Colors.black87)),
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text(
                'Hesap: tutar x aylık oran x ay sayısı. Vadeyi izleyen günden ödeme gününe kadar geçen süre ay olarak sayılır, ay kesri tam ay kabul edilir. '
                'Pişmanlık zammı bu hesaba ek olarak ayrıca usulsüzlük cezası doğuruyorsa onu içermez; vergi ziyaı cezası yerine pişmanlık zammı '
                'uygulanması için başvuru şartlarını ayrıca kontrol et. Bu araç bir ön hesaptır, kesin tutar için GİB / SGK hesaplamasını esas al.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
    ]);
    if (widget.gomulu) return icerik;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: icerik),
      ),
    ]);
  }
}
