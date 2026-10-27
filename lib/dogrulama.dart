/// TC kimlik numarası: 11 hane, ilk hane 0 olamaz, 10. ve 11. haneler kontrol hanesidir.
bool tcGecerli(String s) {
  if (!RegExp(r'^[1-9]\d{10}$').hasMatch(s)) return false;
  final d = s.split('').map(int.parse).toList();
  final tek = d[0] + d[2] + d[4] + d[6] + d[8];
  final cift = d[1] + d[3] + d[5] + d[7];
  final d10 = (((tek * 7) - cift) % 10 + 10) % 10;
  final d11 = (tek + cift + d[9]) % 10;
  return d[9] == d10 && d[10] == d11;
}

/// Vergi kimlik numarası: 10 hane, son hane kontrol hanesidir.
bool vknGecerli(String s) {
  if (!RegExp(r'^\d{10}$').hasMatch(s)) return false;
  final d = s.split('').map(int.parse).toList();
  var toplam = 0;
  for (var i = 0; i < 9; i++) {
    final t = (d[i] + (9 - i)) % 10;
    var p = (t * (1 << (9 - i))) % 9;
    if (t != 0 && p == 0) p = 9;
    toplam += p;
  }
  return (10 - toplam % 10) % 10 == d[9];
}

bool epostaGecerli(String s) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(s);
