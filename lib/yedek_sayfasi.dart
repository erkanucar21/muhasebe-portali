import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cop_kutusu.dart';
import 'eposta_ozet.dart';
import 'islem_kaydi.dart';
import 'yedek.dart';

/// Sunucudaki otomatik (haftalık) ve elle alınan yedekler. Sadece yönetici.
class YedekSayfasi extends StatefulWidget {
  const YedekSayfasi({super.key});
  @override
  State<YedekSayfasi> createState() => _YedekSayfasiState();
}

class _YedekSayfasiState extends State<YedekSayfasi> {
  final _db = Supabase.instance.client;
  bool _yukleniyor = true;
  bool _mesgul = false;
  int _sekme = 0;
  String? _hata;
  List<Map<String, dynamic>> _liste = [];

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
      final r = await _db
          .from('yedek_arsiv')
          .select('id, tarih, tur, satir_sayisi')
          .order('tarih', ascending: false)
          .limit(60);
      _liste = r.cast<Map<String, dynamic>>();
    } catch (e) {
      _hata = 'Yedekler okunamadı: $e\n(supabase_yedek.sql çalıştırıldı mı?)';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  void _bilgi(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _tarih(String iso) {
    final t = DateTime.parse(iso).toLocal();
    String i(int n) => n.toString().padLeft(2, '0');
    return '${i(t.day)}.${i(t.month)}.${t.year}  ${i(t.hour)}:${i(t.minute)}';
  }

  Future<void> _simdiYedekle() async {
    setState(() => _mesgul = true);
    try {
      await _db.rpc('yedek_olustur', params: {'p_tur': 'elle'});
      _bilgi('Yedek alındı.');
      await _yukle();
    } catch (e) {
      _bilgi('Yedek alınamadı: $e');
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _dosyadanYukle() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    setState(() => _mesgul = true);
    try {
      final d = jsonDecode(utf8.decode(r.files.first.bytes!));
      if (d is! Map || !d.containsKey('firmalar')) {
        _bilgi('Bu dosya bir yedek dosyası gibi görünmüyor.');
      } else {
        await _db.rpc('yedek_ice_aktar', params: {'p_veri': d});
        _bilgi('Yedek listeye eklendi. Şimdi satırdaki "Geri yükle" ile firmayı seç.');
        await _yukle();
      }
    } catch (e) {
      _bilgi('Dosya yüklenemedi: $e (supabase_yedek_ice_aktar.sql çalıştırıldı mı?)');
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _indir(int id) async {
    try {
      await arsivYedegiIndir(id);
      _bilgi('Excel indirildi.');
    } catch (e) {
      _bilgi('İndirilemedi: $e');
    }
  }

  Future<void> _sil(Map<String, dynamic> y) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bu yedek silinsin mi?'),
        content: Text('${_tarih(y['tarih'] as String)} tarihli yedek kalıcı olarak silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _db.from('yedek_arsiv').delete().eq('id', y['id'] as int);
      await _yukle();
    } catch (e) {
      _bilgi('Silinemedi: $e');
    }
  }

  Future<void> _geriYukle(Map<String, dynamic> y) async {
    List<Map<String, dynamic>> firmalar;
    try {
      final r = await _db.rpc('yedek_firmalari', params: {'p_yedek': y['id']});
      firmalar = (r as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _bilgi('Yedek okunamadı: $e (supabase_geri_yukle.sql çalıştırıldı mı?)');
      return;
    }
    if (!mounted) return;
    if (firmalar.isEmpty) {
      _bilgi('Bu yedekte firma yok.');
      return;
    }
    Map<String, dynamic>? secili;
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Firma geri yükle - ${_tarih(y['tarih'] as String)}'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Seçtiğin firmanın personel, kontrol listesi, belge ve ücret kayıtları bu yedekteki haline döner. '
                'Yedekten sonra girilen kayıtlar o firmada silinir. İşlemden hemen önce otomatik bir güvenlik yedeği alınır.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final f in firmalar)
                      ListTile(
                        dense: true,
                        selected: identical(secili, f),
                        leading: Icon(identical(secili, f) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        title: Text('${f['unvan']}'),
                        subtitle: Text(
                            '${f['mevcut'] == true ? 'Şu an var' : 'Silinmiş, yeniden oluşturulur'} • ${f['personel']} personel, ${f['kontrol']} kontrol, ${f['belge']} belge, ${f['ucret']} ücret ayı'),
                        onTap: () => set(() => secili = f),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: secili == null ? null : () => Navigator.pop(c, true), child: const Text('Geri yükle')),
          ],
        ),
      ),
    );
    if (onay != true || secili == null) return;
    setState(() => _mesgul = true);
    try {
      await _db.rpc('yedek_firma_geri_yukle', params: {'p_yedek': y['id'], 'p_firma': secili!['firma_id']});
      _bilgi('${secili!['unvan']} geri yüklendi. Önceki hali "Elle" yedek olarak saklandı.');
      await _yukle();
    } catch (e) {
      _bilgi('Geri yüklenemedi: $e');
    }
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Center(child: CircularProgressIndicator());
    const turuncu = Color(0xFFEF6C00);
    const yesil = Color(0xFF2E7D32);
    final sonOtomatik = _liste.where((y) => y['tur'] == 'otomatik').firstOrNull;
    final gunFarki = sonOtomatik == null ? null : DateTime.now().difference(DateTime.parse(sonOtomatik['tarih'] as String).toLocal()).inDays;
    final sorunlu = _hata == null && (sonOtomatik == null || (gunFarki ?? 99) > 8);

    final sekmeler = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: Text('Yedekler'), icon: Icon(Icons.backup_outlined)),
          ButtonSegment(value: 1, label: Text('İşlem kaydı'), icon: Icon(Icons.history)),
          ButtonSegment(value: 2, label: Text('E-posta özeti'), icon: Icon(Icons.mail_outline)),
          ButtonSegment(value: 3, label: Text('Çöp kutusu'), icon: Icon(Icons.delete_outline)),
        ],
        selected: {_sekme},
        onSelectionChanged: (v) => setState(() => _sekme = v.first),
      ),
    );
    if (_sekme != 0) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              sekmeler,
              if (_sekme == 1) const IslemKaydiSekmesi() else if (_sekme == 3) const CopKutusuSekmesi() else const EpostaSekmesi(),
            ]),
          ),
        ),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sekmeler,
            Row(children: [
              const Expanded(child: Text('Yedekler', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh)),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: _mesgul ? null : _dosyadanYukle,
                icon: const Icon(Icons.upload_file),
                label: const Text('Dosyadan yükle'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _mesgul ? null : _simdiYedekle,
                icon: _mesgul
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.backup_outlined),
                label: const Text('Şimdi yedekle'),
              ),
            ]),
            const SizedBox(height: 8),
            if (_hata != null) Text(_hata!, style: const TextStyle(color: Colors.red)),
            Card(
              elevation: 0,
              color: sorunlu ? const Color(0xFFFFF4D6) : Colors.white,
              child: ListTile(
                leading: Icon(sorunlu ? Icons.warning_amber_rounded : Icons.check_circle, color: sorunlu ? turuncu : yesil),
                title: Text(sonOtomatik == null
                    ? 'Henüz otomatik yedek yok.'
                    : 'Son otomatik yedek: ${_tarih(sonOtomatik['tarih'] as String)}'),
                subtitle: Text(sorunlu
                    ? 'Otomatik yedek çalışmıyor olabilir. supabase_yedek_cron.sql dosyasını çalıştırdın mı ve pg_cron açık mı kontrol et.'
                    : 'Her pazar gece 03:00\'te otomatik alınır, 90 günden eski otomatik yedekler silinir.'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 12),
              child: Text(
                'Bu yedekler uygulamanın veritabanında durur: yanlışlıkla silinen veya bozulan verileri geri getirmeye yarar. '
                'Hesap veya proje tamamen kaybolursa onlar da gider, bu yüzden ayda bir "Excel indir" ile kendi bilgisayarına da kaydet.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
            Card(
              elevation: 0,
              color: Colors.white,
              child: _liste.isEmpty
                  ? const ListTile(title: Text('Kayıtlı yedek yok.'))
                  : Column(children: [
                      for (final y in _liste)
                        ListTile(
                          dense: true,
                          leading: Icon(y['tur'] == 'otomatik' ? Icons.schedule : Icons.touch_app_outlined),
                          title: Text(_tarih(y['tarih'] as String)),
                          subtitle: Text('${y['tur'] == 'otomatik' ? 'Otomatik' : 'Elle'} • ${y['satir_sayisi'] ?? 0} kayıt'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton.icon(
                              onPressed: _mesgul ? null : () => _geriYukle(y),
                              icon: const Icon(Icons.restore, size: 18),
                              label: const Text('Geri yükle'),
                            ),
                            TextButton.icon(
                              onPressed: () => _indir(y['id'] as int),
                              icon: const Icon(Icons.table_chart_outlined, size: 18),
                              label: const Text('Excel indir'),
                            ),
                            IconButton(tooltip: 'Sil', icon: const Icon(Icons.delete_outline), onPressed: () => _sil(y)),
                          ]),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}
