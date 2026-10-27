import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firmalar.dart';
import 'pusula_cikti.dart' show whatsappMesajAc;

/// Seçilen mükelleflere toplu e-posta duyurusu. Sadece yönetici.
class DuyuruSayfasi extends StatefulWidget {
  const DuyuruSayfasi({super.key});
  @override
  State<DuyuruSayfasi> createState() => _DuyuruSayfasiState();
}

class _DuyuruSayfasiState extends State<DuyuruSayfasi> {
  final _db = Supabase.instance.client;
  final _baslik = TextEditingController();
  final _metin = TextEditingController();
  final Set<int> _secili = {};
  List<Map<String, dynamic>> _gecmis = [];
  bool _yukleniyor = true;
  bool _mesgul = false;
  String? _hata;
  String _ara = '';

  static const _sablonlar = <String, (String, String)>{
    'Resmî tatil': (
      'Resmî tatil duyurusu',
      'Sayın mükellefimiz,\n\nresmî tatil nedeniyle ofisimiz kapalı olacaktır. Beyanname ve ödeme son tarihleri tatilden etkileniyorsa ayrıca bilgilendireceğiz.\n\nİyi bayramlar dileriz.'
    ),
    'Belge hatırlatması': (
      'Aylık belgelerinizi bekliyoruz',
      'Sayın mükellefimiz,\n\nbu ayın gelir ve gider belgelerinizi (fatura, fiş, banka dekontları) ayın 10\'una kadar bize iletmenizi rica ederiz. Geç gelen belgeler beyanname sürecini etkileyebilir.\n\nTeşekkür ederiz.'
    ),
    'Mevzuat değişikliği': (
      'Önemli mevzuat değişikliği',
      'Sayın mükellefimiz,\n\nyeni yayımlanan düzenleme firmanızı şu şekilde etkileyebilir:\n\n[Buraya özet yazın]\n\nDetaylar için bizimle iletişime geçebilirsiniz.'
    ),
  };

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      if (FirmaDeposu.ornek.liste.isEmpty) await FirmaDeposu.ornek.yukle();
      final r = await _db.from('duyuru').select('zaman, baslik, test, hedef, iletilen, atlanan').order('zaman', ascending: false).limit(20);
      _gecmis = r.cast<Map<String, dynamic>>();
    } catch (e) {
      _hata = 'Duyuru geçmişi okunamadı: $e\n(supabase_duyuru_acilis.sql çalıştırıldı mı?)';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  void _bilgi(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _zaman(String iso) {
    final t = DateTime.parse(iso).toLocal();
    String i(int n) => n.toString().padLeft(2, '0');
    return '${i(t.day)}.${i(t.month)}.${t.year} ${i(t.hour)}:${i(t.minute)}';
  }

  Future<void> _whatsappGonder() async {
    if (_baslik.text.trim().isEmpty || _metin.text.trim().isEmpty) {
      _bilgi('Başlık ve metni doldur.');
      return;
    }
    if (_secili.isEmpty) {
      _bilgi('En az bir firma seç.');
      return;
    }
    final mesaj = '*${_baslik.text.trim()}*\n\n${_metin.text.trim()}';
    final firmalar = [for (final f in FirmaDeposu.ornek.liste) if (_secili.contains(f.id)) f];
    final gonderilen = <int>{};
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('WhatsApp ile gönder'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'WhatsApp toplu otomatik gönderime izin vermez. Her firmanın yanındaki "Aç" tuşu sohbeti mesaj hazır olarak açar, '
                'sen "Gönder"e basarsın. Gönderdiklerin işaretlenir.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text('${gonderilen.length} / ${firmalar.length} firma', style: const TextStyle(fontWeight: FontWeight.w600)),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final f in firmalar)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(gonderilen.contains(f.id) ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: gonderilen.contains(f.id) ? const Color(0xFF2E7D32) : Colors.black87),
                        title: Text(f.unvan),
                        subtitle: Text(f.telefon.isEmpty ? 'Telefon kayıtlı değil' : f.telefon,
                            style: TextStyle(fontSize: 12, color: f.telefon.isEmpty ? const Color(0xFFC62828) : Colors.black87)),
                        trailing: FilledButton.tonal(
                          onPressed: f.telefon.isEmpty
                              ? null
                              : () async {
                                  final ok = await whatsappMesajAc(f.telefon, mesaj);
                                  if (ok) set(() => gonderilen.add(f.id));
                                },
                          child: const Text('Aç'),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: mesaj));
                if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Mesaj kopyalandı.')));
              },
              child: const Text('Mesajı kopyala'),
            ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
          ],
        ),
      ),
    );
  }

  Future<void> _gonder({required bool test}) async {
    if (_baslik.text.trim().isEmpty || _metin.text.trim().isEmpty) {
      _bilgi('Başlık ve metni doldur.');
      return;
    }
    if (!test && _secili.isEmpty) {
      _bilgi('En az bir firma seç.');
      return;
    }
    if (!test) {
      final onay = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Duyuru gönderilsin mi?'),
          content: Text('${_secili.length} firmaya "${_baslik.text.trim()}" konulu e-posta gidecek. Gönderilen e-posta geri alınamaz.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Gönder')),
          ],
        ),
      );
      if (onay != true) return;
    }
    setState(() => _mesgul = true);
    try {
      final r = await _db.rpc('duyuru_gonder', params: {
        'p_baslik': _baslik.text.trim(),
        'p_metin': _metin.text.trim(),
        'p_firmalar': _secili.toList(),
        'p_test': test,
      });
      final m = r as Map;
      final atlanan = (m['atlanan'] as List?) ?? [];
      _bilgi(test
          ? 'Test e-postası gönderildi, kendi kutunu kontrol et.'
          : '${m['iletilen']} e-posta gönderime verildi.${atlanan.isEmpty ? '' : ' E-postası olmayan ${atlanan.length} firma atlandı.'}');
      await _yukle();
    } catch (e) {
      _bilgi('Gönderilemedi: $e');
    }
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) {
    final tum = FirmaDeposu.ornek.liste;
    final q = _ara.trim().toLowerCase();
    final gorunen = q.isEmpty ? tum : tum.where((f) => f.unvan.toLowerCase().contains(q)).toList();
    final epostasiz = tum.where((f) => f.eposta.isEmpty).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Duyurular', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Seçtiğin mükelleflere e-posta veya WhatsApp ile duyuru gönderirsin. E-posta adresleri firma formundaki "İletişim e-postası", WhatsApp numaraları "Telefon / WhatsApp" alanından alınır. '
              'Yanıtlar, E-posta özeti sekmesinde yazdığın adrese gelmez, gönderen adresine gider; bu yüzden gönderen adresini kontrol et.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            if (_hata != null) Text(_hata!, style: const TextStyle(color: Colors.red)),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in _sablonlar.entries)
                ActionChip(
                  label: Text(e.key),
                  onPressed: () => setState(() {
                    _baslik.text = e.value.$1;
                    _metin.text = e.value.$2;
                  }),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _baslik, decoration: const InputDecoration(labelText: 'Konu')),
            const SizedBox(height: 10),
            TextField(controller: _metin, maxLines: 8, decoration: const InputDecoration(labelText: 'Mesaj', alignLabelWithHint: true)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('Alıcılar (${_secili.length} seçili)', style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(onPressed: () => setState(() => _secili.addAll([for (final f in tum) if (f.eposta.isNotEmpty) f.id])), child: const Text('E-postası olanlar')),
              TextButton(onPressed: () => setState(() => _secili.addAll([for (final f in tum) if (f.telefon.isNotEmpty) f.id])), child: const Text('Telefonu olanlar')),
              TextButton(onPressed: () => setState(_secili.clear), child: const Text('Temizle')),
            ]),
            if (epostasiz > 0)
              Text('$epostasiz firmanın e-postası yok, firma formundan ekleyebilirsin.', style: const TextStyle(fontSize: 12, color: Color(0xFFEF6C00))),
            TextField(
              decoration: const InputDecoration(hintText: 'Firma ara', prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (v) => setState(() => _ara = v),
            ),
            const SizedBox(height: 6),
            Card(
              elevation: 0,
              color: Colors.white,
              child: SizedBox(
                height: 260,
                child: ListView(children: [
                  for (final f in gorunen)
                    CheckboxListTile(
                      dense: true,
                      value: _secili.contains(f.id),
                      onChanged: (v) => setState(() => v == true ? _secili.add(f.id) : _secili.remove(f.id)),
                      title: Text(f.unvan),
                      subtitle: Text('${f.eposta.isEmpty ? 'E-posta yok' : f.eposta}  •  ${f.telefon.isEmpty ? 'Telefon yok' : f.telefon}',
                          style: TextStyle(fontSize: 12, color: (f.eposta.isEmpty && f.telefon.isEmpty) ? const Color(0xFFC62828) : Colors.black87)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, children: [
              FilledButton.icon(
                onPressed: _mesgul ? null : () => _gonder(test: false),
                icon: const Icon(Icons.send),
                label: Text(_mesgul ? 'Gönderiliyor...' : 'Seçilenlere gönder'),
              ),
              OutlinedButton.icon(
                onPressed: _mesgul ? null : _whatsappGonder,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('WhatsApp ile gönder'),
              ),
              OutlinedButton.icon(
                onPressed: _mesgul ? null : () => _gonder(test: true),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Önce bana test gönder'),
              ),
            ]),
            const SizedBox(height: 18),
            const Text('Son duyurular', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (_yukleniyor)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else if (_gecmis.isEmpty)
              const Text('Henüz duyuru gönderilmedi.')
            else
              Card(
                elevation: 0,
                color: Colors.white,
                child: Column(children: [
                  for (final g in _gecmis)
                    ListTile(
                      dense: true,
                      leading: Icon(g['test'] == true ? Icons.science_outlined : Icons.campaign_outlined),
                      title: Text('${g['test'] == true ? '[Test] ' : ''}${g['baslik']}'),
                      subtitle: Text(
                          '${_zaman(g['zaman'] as String)} • ${g['iletilen']} / ${g['hedef']} gönderime verildi'
                          '${((g['atlanan'] as List?) ?? []).isEmpty ? '' : '\nAtlanan (e-posta yok): ${(g['atlanan'] as List).join(', ')}'}'),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }
}
