SAYIM UYGULAMASI - KURULUM

DOSYALAR
  pubspec.yaml                  -> proje kök klasörüne
  lib/main.dart                 -> lib klasörüne
  .github/workflows/build.yml   -> sadece GitHub ile bulutta derleyeceksen

YOL 1: Kendi bilgisayarında
  1) Flutter SDK + Android Studio kur, "flutter doctor" ile kontrol et
  2) flutter create sayim_app
  3) pubspec.yaml ve lib/main.dart dosyalarını oluşan projenin üzerine kopyala
  4) android/app/src/main/AndroidManifest.xml içinde <manifest> etiketinin içine ekle:
     <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
  5) flutter pub get
  6) flutter build apk --release
  7) APK: build/app/outputs/flutter-apk/app-release.apk -> cihaza kopyala ve kur

YOL 2: Bilgisayara kurulum yapmadan (GitHub)
  1) github.com'da ücretsiz hesap aç, yeni bir repo oluştur
  2) Bu klasörün İÇİNDEKİ her şeyi (pubspec.yaml, lib, .github) repoya yükle
  3) Repo > Actions > "Build APK" > Run workflow
  4) Bitince çalışan işe tıkla, en alttaki "sayim-apk" dosyasını indir, zip'i aç
  5) app-release.apk dosyasını cihaza kopyala ve kur

VERİ DOSYASI (CSV) kolonları, ilk satır başlık:
  UrunKodu,UrunAdi,Renk,Beden,Ozellik1Kod,Ozellik1Ad,Ozellik2Kod,Ozellik2Ad,
  Ozellik3Kod,Ozellik3Ad,Ozellik4Kod,Ozellik4Ad,Barkod

EL TERMİNALİ: tarayıcı çıkış modu "klavye (keyboard wedge)" ve sonek "Enter" olmalı.
