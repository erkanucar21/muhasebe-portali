import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'beyannameler.dart';
import 'bordro.dart';
import 'firma_ozet_pdf.dart';
import 'firmalar.dart';
import 'personel_takip.dart';
import 'secili_firma.dart';
import 'firma_arsiv.dart';
import 'tazminat.dart';
import 'ucret_takip.dart';

/// Tek firmanın bütün işleri tek yerde: bilgiler, personel, beyannameler, bordro ve ücret takibi.
/// Firmalar listesinde bir firmaya tıklayınca açılır (sadece yönetici).
class FirmaSayfasi extends StatefulWidget {
  final int firmaId;
  final Future<void> Function() duzenle; // firma düzenleme formunu açar
  const FirmaSayfasi({super.key, required this.firmaId, required this.duzenle});
  @override
  State<FirmaSayfasi> createState() => _FirmaSayfasiState();
}

class _FirmaSayfasiState extends State<FirmaSayfasi> {
  @override
  void initState() {
    super.initState();
    // Personel, Beyannameler ve Bordro sayfaları seçili firmaya göre çalışır
    seciliFirmaId.value = widget.firmaId;
  }

  Firma? get _firma => FirmaDeposu.ornek.bul(widget.firmaId);

  String _tarih(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Widget _satir(String etiket, String deger) {
    if (deger.trim().isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: deger));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$etiket kopyalandı'), duration: const Duration(seconds: 1)));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(etiket, style: const TextStyle(color: Colors.black87))),
          Expanded(child: Text(deger, style: const TextStyle(fontWeight: FontWeight.w500))),
          const Icon(Icons.copy, size: 14, color: Colors.black26),
        ]),
      ),
    );
  }

  Widget _genel(Firma f) => ListView(padding: const EdgeInsets.all(16), children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(f.unvan, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                OutlinedButton.icon(
                  onPressed: () => firmaOzetPdfIndir(context, f),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Özet PDF'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await widget.duzenle();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Düzenle'),
                ),
              ]),
              const SizedBox(height: 10),
              if (f.not.trim().isNotEmpty)
                Card(
                  elevation: 0,
                  color: const Color(0xFFFFF4D6),
                  child: ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined, color: Color(0xFFEF6C00)),
                    title: Text(f.not),
                  ),
                ),
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(children: [
                    _satir('Vergi dairesi', f.vergiDairesi),
                    _satir('Vergi no', f.vergiNo),
                    _satir('TC kimlik no', f.tcNo),
                    _satir('SGK sicil no', f.sgkSicilNo),
                    _satir('SGK şubesi', f.sgkSubesi),
                    _satir('Ticaret sicil no', f.ticaretSicilNo),
                    _satir('MERSİS no', f.mersisNo),
                    _satir('Faaliyet', [f.faaliyetKodu, f.faaliyetAciklama].where((e) => e.isNotEmpty).join(' - ')),
                    _satir('Kuruluş tarihi', f.kurulus == null ? '' : _tarih(f.kurulus!)),
                    _satir('Adres', f.adres),
                    _satir('Telefon / WhatsApp', f.telefon),
                    _satir('E-Defter', f.eDefter ? 'Var (${f.eDefterTercih == 'gecici' ? 'geçici vergi dönemleri' : 'aylık'})' : ''),
                    _satir('GEKAP', f.gekap ? 'Var' : ''),
                    _satir('Mükellef girişi',
                        !f.erisimVar ? 'Yok' : (f.girisAktif ? 'Açık, giriş adı: ${f.girisAdi}' : 'Kapalı')),
                  ]),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Bir satıra tıklayınca değeri kopyalanır.', style: TextStyle(fontSize: 12, color: Colors.black87)),
              ),
            ]),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final f = _firma;
    if (f == null) return const Scaffold(body: Center(child: Text('Firma bulunamadı.')));
    return DefaultTabController(
      length: yoneticiOturumu ? 7 : 6,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          title: Text(f.unvan, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.info_outline), text: 'Bilgiler'),
              Tab(icon: Icon(Icons.folder_outlined), text: 'Arşiv'),
              Tab(icon: Icon(Icons.badge_outlined), text: 'Personel'),
              Tab(icon: Icon(Icons.description_outlined), text: 'Beyannameler'),
              Tab(icon: Icon(Icons.payments_outlined), text: 'Bordro'),
              Tab(icon: Icon(Icons.calculate_outlined), text: 'Kıdem / ihbar'),
              if (yoneticiOturumu) const Tab(icon: Icon(Icons.request_quote_outlined), text: 'Ücret'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _genel(f),
            FirmaArsivSayfasi(firmaId: widget.firmaId),
            const PersonelTakipSayfasi(),
            const BeyannamelerSayfasi(),
            const BordroSayfasi(),
            const TazminatSayfasi(),
            if (yoneticiOturumu) UcretTakipSayfasi(firmaId: widget.firmaId),
          ],
        ),
      ),
    );
  }
}
