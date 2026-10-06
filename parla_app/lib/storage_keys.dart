abstract final class StorageKeys {
  static const onboarded = 'parla:onboarded';
  static const tracking = 'parla:tracking'; // {"car": bool, "glass": bool}
  static const reminders = 'parla:reminders'; // hatırlatma anahtarları (JSON)
  static const lastWash = 'parla:lastWash'; // ISO tarih
  static const streak = 'parla:streak'; // sayı
  static const deviceId = 'parla:deviceId'; // Android ID alınamazsa üretilen kimlik
}
