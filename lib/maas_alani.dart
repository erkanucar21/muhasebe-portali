import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Yazarken binlik noktası koyar (28075,5 -> 28.075,5). Virgülden sonra en fazla 2 hane.
class _MaasBicimi extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue eski, TextEditingValue yeni) {
    var t = yeni.text.replaceAll('.', '');
    t = t.replaceAll(RegExp(r'[^0-9,]'), '');
    final v = t.indexOf(',');
    var tam = v < 0 ? t : t.substring(0, v);
    var kurus = v < 0 ? null : t.substring(v + 1).replaceAll(',', '');
    if (kurus != null && kurus.length > 2) kurus = kurus.substring(0, 2);
    tam = tam.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
    final s = kurus == null ? tam : '$tam,$kurus';
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}

/// Maaş alanı: binlik noktasını kendisi koyar. Alan boşken Enter'a basılırsa
/// [oneri] (son girilen maaş) alana yazılır, tekrar elle yazmak gerekmez.
class MaasAlani extends StatelessWidget {
  final TextEditingController controller;
  final String? oneri; // örn. 28.075,50
  final bool kilitli; // asgari ücretli işaretliyken elle değiştirilemez
  final String etiket;
  final String? ipucu; // boş alanda görünen soluk örnek
  const MaasAlani({super.key, required this.controller, this.oneri, this.kilitli = false, this.etiket = 'Maaş (TL)', this.ipucu});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        readOnly: kilitli,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_MaasBicimi()],
        onSubmitted: (_) {
          if (controller.text.trim().isEmpty && oneri != null) {
            controller.text = oneri!;
            controller.selection = TextSelection.collapsed(offset: controller.text.length);
          }
        },
        decoration: InputDecoration(
          labelText: etiket,
          hintText: ipucu ?? oneri ?? '28.075,50',
          helperText: kilitli ? 'Asgari ücret yazıldı' : oneri == null ? null : 'Boşken Enter: $oneri yazılır',
          suffixIcon: (oneri == null || kilitli)
              ? null
              : IconButton(
                  tooltip: 'Son maaşı yaz ($oneri)',
                  icon: const Icon(Icons.keyboard_return),
                  onPressed: () {
                    controller.text = oneri!;
                    controller.selection = TextSelection.collapsed(offset: controller.text.length);
                  },
                ),
        ),
      );
}

/// Tablo içinde kullanılan küçük tutar kutusu (etiketsiz, sağa yaslı, binlik noktalı).
class TutarKutusu extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? degisti;
  const TutarKutusu({super.key, required this.controller, this.degisti});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_MaasBicimi()],
        onChanged: (_) => degisti?.call(),
        decoration: const InputDecoration(isDense: true, hintText: '0,00'),
      );
}
