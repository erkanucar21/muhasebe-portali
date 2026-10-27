import 'package:flutter/material.dart';
import 'asgari_guncelle.dart';
import 'bordro.dart';
import 'personel_takip.dart';
import 'secili_firma.dart';
import 'tazminat.dart';

/// Personel menüsü: devam takibi, bordro ve tazminat hesabı sekmeleri (yönetici ve yardımcı kullanıcılar için).
class PersonelMenuSayfasi extends StatelessWidget {
  const PersonelMenuSayfasi({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Material(
          color: Colors.white,
          child: Row(children: [
            Expanded(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Theme.of(context).colorScheme.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.badge_outlined), text: 'Personel takibi'),
                  Tab(icon: Icon(Icons.payments_outlined), text: 'Bordro'),
                  Tab(icon: Icon(Icons.calculate_outlined), text: 'Kıdem / ihbar'),
                ],
              ),
            ),
            if (yoneticiOturumu)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: OutlinedButton.icon(
                  onPressed: () => asgariGuncelleAc(context),
                  icon: const Icon(Icons.price_change_outlined, size: 18),
                  label: const Text('Asgari ücret güncelle'),
                ),
              ),
          ]),
        ),
        const Expanded(
          child: TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [
              PersonelTakipSayfasi(),
              BordroSayfasi(),
              TazminatSayfasi(),
            ],
          ),
        ),
      ]),
    );
  }
}
