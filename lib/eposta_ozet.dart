import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Günlük / haftalık e-posta özeti ayarları. E-posta Resend üzerinden gönderilir.
class EpostaSekmesi extends StatefulWidget {
  const EpostaSekmesi({super.key});
  @override
  State<EpostaSekmesi> createState() => _EpostaSekmesiState();
}

class _EpostaSekmesiState extends State<EpostaSekmesi> {
  final _db = Supabase.instance.client;
  final _alici = TextEditingController();
  final _gonderen = TextEditingController();
  final _anahtar = TextEditingController();
  bool _yukleniyor = true;
  bool _mesgul = false;
  bool _aktif = false;
  bool _bosGonder = false;
  final _yedekSifre = TextEditingController();
  bool _yedekAktif = false;
  String _yedekSon = '';
  String _siklik = 'gunluk';
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _alici.dispose();
    _gonderen.dispose();
    _anahtar.dispose();
    _yedekSifre.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final r = await _db.from('eposta_ayar').select().eq('id', 1).maybeSingle();
      if (r != null) {
        _alici.text = (r['alici'] as String?) ?? '';
        _gonderen.text = (r['gonderen'] as String?) ?? 'onboarding@resend.dev';
        _anahtar.text = (r['api_anahtari'] as String?) ?? '';
        _aktif = r['aktif'] == true;
        _bosGonder = r['bos_gonder'] == true;
        _siklik = (r['siklik'] as String?) ?? 'gunluk';
      }
    } catch (e) {
      _hata = 'Ayarlar okunamadı: $e\n(supabase_eposta.sql çalıştırıldı mı?)';
    }
    try {
      final y = await _db.from('yedek_dis_ayar').select().eq('id', 1).maybeSingle();
      if (y != null) {
        _yedekSifre.text = (y['sifre'] as String?) ?? '';
        _yedekAktif = y['aktif'] == true;
        final t = y['son_deneme'] == null ? null : DateTime.parse(y['son_deneme'] as String).toLocal();
        _yedekSon = t == null ? '' : '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} - ${y['son_sonuc'] ?? ''}';
      }
    } catch (_) {
      // tablo yoksa (supabase_yedek_dis.sql çalıştırılmadıysa) bölüm yine görünür, kaydederken hata verir
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<bool> _yedekKaydet() async {
    try {
      await _db.from('yedek_dis_ayar').upsert({'id': 1, 'aktif': _yedekAktif, 'sifre': _yedekSifre.text.trim()});
      return true;
    } catch (e) {
      _bilgi('Kaydedilemedi: $e\n(supabase_yedek_dis.sql çalıştırıldı mı?)');
      return false;
    }
  }

  Future<void> _yedekTest() async {
    setState(() => _mesgul = true);
    if (await _kaydet() && await _yedekKaydet()) {
      try {
        final r = await _db.rpc('yedek_disari_gonder', params: {'p_test': true});
        _bilgi('$r');
        await _yukle();
      } catch (e) {
        _bilgi('Gönderilemedi: $e');
      }
    }
    if (mounted) setState(() => _mesgul = false);
  }

  void _bilgi(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _kaydet() async {
    try {
      await _db.from('eposta_ayar').upsert({
        'id': 1,
        'aktif': _aktif,
        'alici': _alici.text.trim(),
        'gonderen': _gonderen.text.trim().isEmpty ? 'onboarding@resend.dev' : _gonderen.text.trim(),
        'api_anahtari': _anahtar.text.trim(),
        'siklik': _siklik,
        'bos_gonder': _bosGonder,
      });
      return true;
    } catch (e) {
      _bilgi('Kaydedilemedi: $e');
      return false;
    }
  }

  Future<void> _kaydetTikla() async {
    setState(() => _mesgul = true);
    if (await _kaydet()) _bilgi('Kaydedildi.');
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _testGonder() async {
    setState(() => _mesgul = true);
    if (await _kaydet()) {
      try {
        final r = await _db.rpc('eposta_ozet_gonder', params: {'p_test': true});
        _bilgi('$r. Birkaç dakika içinde gelmezse Resend panelindeki Logs bölümüne bak.');
      } catch (e) {
        _bilgi('Gönderilemedi: $e');
      }
    }
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('E-posta özeti', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (_hata != null) Text(_hata!, style: const TextStyle(color: Colors.red)),
      const Text(
        'Notlar ve hatırlatmalar, personel sözleşme uyarıları, geçmiş ücret borçları ve kontrol listesinde onay girilmemiş firma sayısı '
        'sabah 07:00 (Türkiye saati) civarında e-postana gelir. Gönderim için ücretsiz bir Resend hesabı ve API anahtarı gerekir (resend.com).',
        style: TextStyle(fontSize: 12, color: Colors.black87),
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Otomatik gönderim açık'),
              value: _aktif,
              onChanged: (v) => setState(() => _aktif = v),
            ),
            TextField(controller: _alici, decoration: const InputDecoration(labelText: 'Alıcı e-posta', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
              controller: _gonderen,
              decoration: const InputDecoration(
                labelText: 'Gönderen adresi',
                helperText: 'Kendi alan adını Resend\'de doğrulamadıysan onboarding@resend.dev kalsın; bu durumda sadece Resend hesabının e-postasına gönderebilir.',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _anahtar,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Resend API anahtarı (re_...)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Sıklık:  '),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'gunluk', label: Text('Her gün')),
                  ButtonSegment(value: 'haftalik', label: Text('Pazartesileri')),
                ],
                selected: {_siklik},
                onSelectionChanged: (v) => setState(() => _siklik = v.first),
              ),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Bildirilecek bir şey yoksa da gönder'),
              value: _bosGonder,
              onChanged: (v) => setState(() => _bosGonder = v == true),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              FilledButton(onPressed: _mesgul ? null : _kaydetTikla, child: const Text('Kaydet')),
              OutlinedButton.icon(
                onPressed: _mesgul ? null : _testGonder,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Kaydet ve test gönder'),
              ),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 24),
      const Text('Yedeğin dışarıya kopyası', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text(
        'Her pazar sabahı yedek şifrelenip e-postana ek olarak gönderilir. Böylece proje silinse veya hesabına erişemesen bile yedeğin e-posta kutunda durur. '
        'Alıcı ve Resend anahtarı yukarıdaki ayarlardan alınır. Şifreyi kaybedersen yedeği açamazsın, bir yere de not et.',
        style: TextStyle(fontSize: 12, color: Colors.black87),
      ),
      const SizedBox(height: 10),
      Card(
        elevation: 0,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Haftalık şifreli yedek e-postası açık'),
              value: _yedekAktif,
              onChanged: (v) => setState(() => _yedekAktif = v),
            ),
            TextField(
              controller: _yedekSifre,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Yedek şifresi (en az 8 karakter)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, children: [
              FilledButton(
                onPressed: _mesgul
                    ? null
                    : () async {
                        setState(() => _mesgul = true);
                        if (await _yedekKaydet()) _bilgi('Kaydedildi.');
                        if (mounted) setState(() => _mesgul = false);
                      },
                child: const Text('Kaydet'),
              ),
              OutlinedButton.icon(
                onPressed: _mesgul ? null : _yedekTest,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Kaydet ve test yedeği gönder'),
              ),
            ]),
            if (_yedekSon.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Son deneme: $_yedekSon', style: const TextStyle(fontSize: 12))),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SelectableText(
                'Yedeği açmak için (Mac, bir kez: brew install gnupg):\ngpg --decrypt yedek_2026-10-25.asc > yedek.json',
                style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
