/// Resmî tatil günleri ve yıllık izne sayılmayan günler.
/// İş Kanunu m.56: yıllık ücretli izin süresine rastlayan ulusal bayram, hafta tatili ve genel tatil günleri izin süresinden sayılmaz.
/// Hafta tatili Pazar kabul edilir. Arife yarım günleri tam gün sayılır.

// Her yıl aynı olan tatiller: (ay, gün)
const _sabitTatiller = [(1, 1), (4, 23), (5, 1), (5, 19), (7, 15), (8, 30), (10, 29)];

// Dini bayramlar her yıl kayar, yıl yıl yazılır. Yeni yıl için ekle: (yıl: [ilk gün, son gün] aralıkları)
const _dini = <int, List<((int, int), (int, int))>>{
  2022: [((5, 2), (5, 4)), ((7, 9), (7, 12))],
  2023: [((4, 21), (4, 23)), ((6, 28), (7, 1))],
  2024: [((4, 10), (4, 12)), ((6, 16), (6, 19))],
  2025: [((3, 30), (4, 1)), ((6, 6), (6, 9))],
  2026: [((3, 20), (3, 22)), ((5, 27), (5, 30))],
  2027: [((3, 9), (3, 11)), ((5, 16), (5, 19))],
};

/// Dini bayramları tanımlı son yıl. Sonraki yıllarda yalnızca sabit tatiller bilinir.
const dinaiBayramSonYil = 2027;

bool genelTatilMi(DateTime d) {
  for (final (ay, gun) in _sabitTatiller) {
    if (d.month == ay && d.day == gun) return true;
  }
  for (final (bas, son) in _dini[d.year] ?? const <((int, int), (int, int))>[]) {
    final t = DateTime(d.year, d.month, d.day);
    if (!t.isBefore(DateTime(d.year, bas.$1, bas.$2)) && !t.isAfter(DateTime(d.year, son.$1, son.$2))) return true;
  }
  return false;
}

/// Yıllık izin hesabında sayılmayan gün mü (Pazar veya genel tatil)?
bool izneSayilmaz(DateTime d) => d.weekday == DateTime.sunday || genelTatilMi(d);

/// Başlangıç ve bitiş dahil, yıllık izinden düşülecek gün sayısı.
int izinGunSayisi(DateTime bas, DateTime son) {
  var n = 0;
  for (var t = DateTime(bas.year, bas.month, bas.day); !t.isAfter(son); t = DateTime(t.year, t.month, t.day + 1)) {
    if (!izneSayilmaz(t)) n++;
  }
  return n;
}
