import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Giriş yapılmış ama Google Authenticator kodu henüz girilmemiş mi?
Future<bool> mfaKodGerekli() async {
  try {
    final a = await Future.value(_db.auth.mfa.getAuthenticatorAssuranceLevel());
    return a.nextLevel == AuthenticatorAssuranceLevels.aal2 && a.currentLevel != AuthenticatorAssuranceLevels.aal2;
  } catch (_) {
    return false;
  }
}

/// Doğrulanmış (kurulumu tamamlanmış) authenticator faktörü; yoksa null.
Future<Factor?> mfaFaktor() async {
  try {
    final f = await _db.auth.mfa.listFactors();
    return f.totp.isEmpty ? null : f.totp.first;
  } catch (_) {
    return null;
  }
}

/// 6 haneli kodu sorar. Doğru girilirse true döner ve oturum güvenli seviyeye yükselir.
Future<bool> mfaKodSor(BuildContext context) async {
  final faktor = await mfaFaktor();
  if (faktor == null) return true;
  if (!context.mounted) return false;
  final kod = TextEditingController();
  String? hata;
  var mesgul = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (c, setD) {
        Future<void> dogrula() async {
          if (kod.text.trim().length != 6) {
            setD(() => hata = '6 haneli kodu yaz');
            return;
          }
          setD(() {
            mesgul = true;
            hata = null;
          });
          try {
            await _db.auth.mfa.challengeAndVerify(factorId: faktor.id, code: kod.text.trim());
            if (c.mounted) Navigator.pop(c, true);
          } catch (_) {
            setD(() {
              mesgul = false;
              hata = 'Kod hatalı veya süresi doldu. Yeni kodu dene.';
            });
          }
        }

        return AlertDialog(
          title: const Text('İki adımlı doğrulama'),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Telefonundaki Google Authenticator uygulamasını aç ve Muhasebe Portalı için gösterilen 6 haneli kodu yaz.'),
              const SizedBox(height: 12),
              TextField(
                controller: kod,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => dogrula(),
                decoration: InputDecoration(labelText: 'Kod', errorText: hata, counterText: ''),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: mesgul ? null : dogrula, child: const Text('Doğrula')),
          ],
        );
      },
    ),
  );
  kod.dispose();
  return ok == true;
}

/// Google Authenticator kurulumunu yapar: QR kodu gösterir, ilk kodu doğrular. Başarılıysa true.
Future<bool> mfaKurulumAc(BuildContext context) async {
  AuthMFAEnrollResponse kayit;
  try {
    // yarım kalmış önceki kurulumları temizle
    final f = await _db.auth.mfa.listFactors();
    for (final x in f.all) {
      if (x.status == FactorStatus.unverified) {
        try {
          await _db.auth.mfa.unenroll(x.id);
        } catch (_) {}
      }
    }
    kayit = await _db.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Muhasebe Portalı',
      friendlyName: 'Telefon ${DateTime.now().millisecondsSinceEpoch}',
    );
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kurulum başlatılamadı: $e')));
    return false;
  }
  final totp = kayit.totp;
  if (totp == null) return false;
  if (!context.mounted) return false;

  final kod = TextEditingController();
  String? hata;
  var mesgul = false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (c, setD) {
        Future<void> dogrula() async {
          if (kod.text.trim().length != 6) {
            setD(() => hata = '6 haneli kodu yaz');
            return;
          }
          setD(() {
            mesgul = true;
            hata = null;
          });
          try {
            await _db.auth.mfa.challengeAndVerify(factorId: kayit.id, code: kod.text.trim());
            if (c.mounted) Navigator.pop(c, true);
          } catch (_) {
            setD(() {
              mesgul = false;
              hata = 'Kod hatalı. Telefonundaki güncel kodu dene.';
            });
          }
        }

        return AlertDialog(
          title: const Text('Google Authenticator kurulumu'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('1. Telefonuna Google Authenticator uygulamasını kur ve aç.\n2. "+" düğmesine bas, "QR kodu tara"yı seç ve aşağıdaki kodu okut.\n3. Uygulamada görünen 6 haneli kodu aşağıya yaz.'),
                const SizedBox(height: 12),
                Center(child: QrImageView(data: totp.uri, size: 190, backgroundColor: Colors.white)),
                const SizedBox(height: 8),
                const Text('Kamera çalışmazsa bu anahtarı uygulamada elle gir. Telefonu kaybedersen lazım olur, güvenli bir yere de not et:', style: TextStyle(fontSize: 12)),
                SelectableText(totp.secret, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: kod,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => dogrula(),
                  decoration: InputDecoration(labelText: 'Uygulamadaki 6 haneli kod', errorText: hata, counterText: ''),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: mesgul
                  ? null
                  : () async {
                      try {
                        await _db.auth.mfa.unenroll(kayit.id);
                      } catch (_) {}
                      if (c.mounted) Navigator.pop(c, false);
                    },
              child: const Text('Vazgeç'),
            ),
            FilledButton(onPressed: mesgul ? null : dogrula, child: const Text('Kurulumu tamamla')),
          ],
        );
      },
    ),
  );
  kod.dispose();
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İki adımlı doğrulama açıldı. Bir sonraki girişte kod istenecek.')));
  }
  return ok == true;
}

/// Üst çubuktaki güvenlik düğmesi: kurulu değilse kurar, kuruluysa kapatma seçeneği sunar.
Future<void> mfaYonet(BuildContext context) async {
  final faktor = await mfaFaktor();
  if (!context.mounted) return;
  if (faktor == null) {
    await mfaKurulumAc(context);
    return;
  }
  final kapat = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('İki adımlı doğrulama açık'),
      content: const Text('Girişte Google Authenticator kodu isteniyor. Kapatırsan yalnızca şifreyle giriş yapılır.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Açık kalsın')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
  if (kapat != true) return;
  try {
    await _db.auth.mfa.unenroll(faktor.id);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İki adımlı doğrulama kapatıldı.')));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kapatılamadı: $e')));
  }
}
