import 'package:flutter/foundation.dart';

/// Luca'daki gibi: üst çubuktan seçilen firma. Personel, Beyannameler, Faturalar ve Luca aktarımı
/// bölümleri hep bu firma için çalışır.
final ValueNotifier<int?> seciliFirmaId = ValueNotifier<int?>(null);

/// Başka bir yerden (ör. Firmalar listesindeki "Aç" düğmesi) belirli bir bölüme geçmek için.
final ValueNotifier<String?> bolumIstegi = ValueNotifier<String?>(null);

/// Giriş yapan gerçek yönetici mi (yardımcı kullanıcılar için ücret ve yedek alanları gizlenir).
bool yoneticiOturumu = true;
