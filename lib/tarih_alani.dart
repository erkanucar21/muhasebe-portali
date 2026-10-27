import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Yazarken noktaları kendisi koyan (21042025 -> 21.04.2025) ve takvim simgesiyle
/// tarih seçtiren alan. Metin yine gg.aa.yyyy biçiminde kalır.
class _TarihBicimi extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue eski, TextEditingValue yeni) {
    final r = yeni.text.replaceAll(RegExp(r'[^0-9]'), '');
    final kisa = r.length > 8 ? r.substring(0, 8) : r;
    final b = StringBuffer();
    for (var i = 0; i < kisa.length; i++) {
      if (i == 2 || i == 4) b.write('.');
      b.write(kisa[i]);
    }
    final s = b.toString();
    return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}

DateTime? _coz(String s) {
  final p = s.trim().split('.');
  if (p.length != 3) return null;
  final g = int.tryParse(p[0]), a = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (g == null || a == null || y == null || y < 1900) return null;
  final d = DateTime(y, a, g);
  return (d.day == g && d.month == a) ? d : null;
}

class TarihAlani extends StatelessWidget {
  final TextEditingController controller;
  final String etiket;
  final String? ipucu;
  const TarihAlani({super.key, required this.controller, required this.etiket, this.ipucu});

  Future<void> _sec(BuildContext context) async {
    final su = DateTime.now();
    final mevcut = _coz(controller.text) ?? su;
    final d = await showDatePicker(
      context: context,
      initialDate: mevcut,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
      helpText: etiket,
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (d != null) {
      controller.text =
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [_TarihBicimi()],
        decoration: InputDecoration(
          labelText: etiket,
          hintText: ipucu ?? 'gg.aa.yyyy',
          suffixIcon: IconButton(
            tooltip: 'Takvimden seç',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _sec(context),
          ),
        ),
      );
}
