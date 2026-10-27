import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Silinen firma, personel, kontrol ve ücret kayıtları 30 gün burada bekler. Sadece yönetici.
class CopKutusuSekmesi extends StatefulWidget {
  const CopKutusuSekmesi({super.key});
  @override
  State<CopKutusuSekmesi> createState() => _CopKutusuSekmesiState();
}

class _CopKutusuSekmesiState extends State<CopKutusuSekmesi> {
  final _db = Supabase.instance.client;
  bool _yukleniyor = true;
  bool _mesgul = false;
  String? _hata;
  List<Map<String, dynamic>> _liste = [];

  static const _tabloAd = {
    'firmalar': 'Firma',
    'personel': 'Personel',
    'izin_kayitlari': 'İzin kaydı',
    'beyanname_kontrol': 'Kontrol listesi',
    'ucret_ayar': 'Ücret ayarı',
    'ucret_takip': 'Ücret takibi',
    'ucret_kalem': 'Ücret kalemi',
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
      final r = await _db.rpc('cop_listesi');
      _liste = (r as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _hata = 'Çöp kutusu okunamadı: $e\n(supabase_cop_kutusu.sql çalıştırıldı mı?)';
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  void _bilgi(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _zaman(String iso) {
    final t = DateTime.parse(iso).toLocal();
    String i(int n) => n.toString().padLeft(2, '0');
    return '${i(t.day)}.${i(t.month)}.${t.year} ${i(t.hour)}:${i(t.minute)}';
  }

  Future<void> _geriAl(Map<String, dynamic> k) async {
    setState(() => _mesgul = true);
    try {
      final r = await _db.rpc('cop_geri_al', params: {'p_id': k['id']});
      _bilgi('Geri alındı (${r is Map ? r['geri_alinan'] : '-'} kayıt).');
      await _yukle();
    } catch (e) {
      final m = '$e';
      _bilgi(m.contains('Önce bağlı') ? 'Önce bağlı olduğu firmayı geri almalısın.' : 'Geri alınamadı: $e');
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _kaliciSil(Map<String, dynamic> k) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kalıcı olarak silinsin mi?'),
        content: Text('${k['ozet']} çöp kutusundan da silinir, artık geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kalıcı sil')),
        ],
      ),
    );
    if (onay != true) return;
    try {
      await _db.rpc('cop_kalici_sil', params: {'p_id': k['id']});
      await _yukle();
    } catch (e) {
      _bilgi('Silinemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Çöp kutusu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Yenile', onPressed: _yukle, icon: const Icon(Icons.refresh)),
      ]),
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text(
          'Silinen firma, personel, kontrol listesi ve ücret kayıtları 30 gün burada durur. '
          'Firmayı geri alınca personeli, kontrol listesi ve ücret kayıtları da döner. '
          'Yüklenmiş dosyalar (belge, vergi levhası) silinirken sunucudan da kalktığı için geri gelmez.',
          style: TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
      if (_hata != null) Text(_hata!, style: const TextStyle(color: Colors.red)),
      if (_yukleniyor)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_liste.isEmpty && _hata == null)
        const Padding(padding: EdgeInsets.all(12), child: Text('Çöp kutusu boş. Kayıtlar SQL çalıştırıldıktan sonraki silmelerden başlar.'))
      else
        Card(
          elevation: 0,
          color: Colors.white,
          child: Column(children: [
            for (final k in _liste)
              ListTile(
                dense: true,
                leading: const Icon(Icons.delete_outline),
                title: Text('${_tabloAd[k['tablo']] ?? k['tablo']}: ${(k['ozet'] as String? ?? '').isEmpty ? '-' : k['ozet']}'),
                subtitle: Text(
                    '${_zaman(k['zaman'] as String)} • ${k['silen']}'
                    '${(k['firma_unvan'] as String?) == null || k['tablo'] == 'firmalar' ? '' : ' • ${k['firma_unvan']}'}'
                    '${(k['cocuk'] as num? ?? 0) > 0 ? ' • ${k['cocuk']} bağlı kayıt' : ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton.icon(
                    onPressed: _mesgul ? null : () => _geriAl(k),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Geri al'),
                  ),
                  IconButton(tooltip: 'Kalıcı sil', icon: const Icon(Icons.delete_forever_outlined), onPressed: () => _kaliciSil(k)),
                ]),
              ),
          ]),
        ),
    ]);
  }
}
