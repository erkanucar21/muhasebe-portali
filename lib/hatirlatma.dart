import 'dart:convert';
import 'dart:typed_data';

import 'bordro_cikti.dart' show bordroKaydet;

String _ics(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

String _gun(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// Tek günlük bir vadeyi takvim dosyası (.ics) olarak indirir. Bir gün önce 09:00 ve o gün 09:00'da bildirim çalar.
Future<void> vadeIcsKaydet(String baslik, DateTime tarih, {String aciklama = ''}) async {
  final bitis = DateTime(tarih.year, tarih.month, tarih.day + 1);
  final damga = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first;
  final b = StringBuffer()
    ..write('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Muhasebe Portali//TR\r\nCALSCALE:GREGORIAN\r\n')
    ..write('BEGIN:VEVENT\r\n')
    ..write('UID:vade-${_gun(tarih)}-${baslik.hashCode}@portal\r\n')
    ..write('DTSTAMP:${damga}Z\r\n')
    ..write('DTSTART;VALUE=DATE:${_gun(tarih)}\r\n')
    ..write('DTEND;VALUE=DATE:${_gun(bitis)}\r\n')
    ..write('SUMMARY:${_ics(baslik)}\r\n');
  if (aciklama.isNotEmpty) b.write('DESCRIPTION:${_ics(aciklama)}\r\n');
  b
    ..write('BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Yarın: ${_ics(baslik)}\r\nTRIGGER:-PT15H\r\nEND:VALARM\r\n')
    ..write('BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Bugün: ${_ics(baslik)}\r\nTRIGGER:PT9H\r\nEND:VALARM\r\n')
    ..write('END:VEVENT\r\nEND:VCALENDAR\r\n');
  await bordroKaydet('hatirlatma_${_gun(tarih)}', Uint8List.fromList(utf8.encode(b.toString())), 'ics');
}
