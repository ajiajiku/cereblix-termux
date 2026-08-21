# Panduan Instalasi Cereblix Termux

Panduan ini dimulai dari Termux yang belum dikonfigurasi sampai miner berjalan dan mengirim share ke pool.

## 1. Persyaratan

Perangkat harus memenuhi:

- Android 7.0 atau lebih baru (API 24+).
- CPU ARM64 (`arm64-v8a`) atau ARMv7 (`armeabi-v7a`).
- Internet aktif.
- Ruang penyimpanan yang cukup untuk Termux, paket compiler, source, dan hasil build.
- Termux yang terpasang dan dapat menjalankan `pkg`.

> Catatan: repository ini menargetkan Android 7+, tetapi tidak berarti semua perangkat Android 7 telah diuji satu per satu.

## 2. Instal Termux

Untuk instalasi Termux, gunakan sumber tepercaya. F-Droid menyediakan paket Termux yang mendukung Android 7.0+.

1. Instal aplikasi **F-Droid** dari situs resminya.
2. Buka F-Droid dan tunggu katalog selesai dimuat.
3. Cari **Termux**.
4. Instal Termux.
5. Buka Termux.

Jika Android meminta izin untuk memasang aplikasi dari sumber tersebut, ikuti konfirmasi Android.

## 3. Persiapan pertama Termux

Pada Termux yang baru dibuka, jalankan satu per satu:

```sh
pkg update -y
pkg install -y git
```

Tunggu sampai selesai.

> Pesan `No mirror or mirror group selected` tidak otomatis berarti error. Jika `pkg` tetap berhasil mengambil paket dan selesai tanpa error, lanjutkan ke langkah berikutnya. Jika pengunduhan gagal, jalankan `termux-change-repo` dan pilih mirror yang aktif.

## 4. Download repository

Jalankan:

```sh
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
```

Pastikan prompt berubah ke direktori:

```text
~/cereblix-termux $
```

## 5. Jalankan installer

Beri izin eksekusi:

```sh
chmod +x install.sh
```

Kemudian:

```sh
./install.sh
```

Installer akan:

1. Memeriksa versi Android/API.
2. Memeriksa ABI CPU.
3. Memperbarui daftar paket Termux.
4. Memasang `clang`, `curl`, dan `make` bila belum ada.
5. Mengambil source native engine yang dibutuhkan.
6. Mengompilasi miner untuk perangkat.
7. Membuat konfigurasi lokal.
8. Meminta wallet pada instalasi pertama jika belum ada.

Contoh pemeriksaan yang normal:

```text
[INFO] Android API : 33
[INFO] ABI         : arm64-v8a
[INFO] Machine     : aarch64
```

## 6. Masukkan wallet

Pada instalasi pertama, akan muncul:

```text
CRB wallet address (crb1...):
```

Masukkan alamat wallet CRB Anda, misalnya formatnya dimulai dengan:

```text
crb1...
```

Wallet disimpan lokal. Installer tidak meminta wallet lagi pada pemasangan ulang selama konfigurasi lama masih ada.

**Jangan kirim isi file konfigurasi ke GitHub atau orang lain.**

## 7. Atur worker dan threads

Setelah installer selesai, konfigurasi dapat diatur dengan:

```sh
~/.local/share/cereblix-termux/start.sh --setup
```

Akan muncul tiga pertanyaan.

### Wallet

```text
CRB wallet address (crb1...):
```

Masukkan wallet.

### Worker

```text
Worker name [nmminer-termux]:
```

Contoh:

```text
hp1
```

### Threads

```text
Threads [0 = otomatis, 0]:
```

Contoh:

```text
8
```

Atau gunakan `0` untuk deteksi otomatis.

Setelah selesai:

```text
Konfigurasi tersimpan.
```

## 8. Jalankan miner

Jalankan:

```sh
~/.local/share/cereblix-termux/start.sh
```

Contoh output yang benar:

```text
Cereblix Termux — APK v2.0 native engine
Pool: stratum.cereblix.com:3333
Worker: hp1
Threads: 8

job ... height ...
hashes=... accepted=0 rejected=0
share accepted: 1
hashes=... accepted=1 rejected=0
```

Jika angka `accepted` terus bertambah dan `rejected=0`, miner berhasil berkomunikasi dengan pool dan mengirim share yang diterima.

## 9. Cek worker di dashboard

Buka dashboard Cereblix dan cari nama worker yang Anda masukkan.

Contoh:

```text
hp1
```

Worker dapat membutuhkan waktu sebelum muncul atau diperbarui di dashboard. Jangan langsung mengubah konfigurasi hanya karena dashboard belum berubah dalam beberapa detik.

## 10. Menghentikan miner

Saat miner sedang berjalan, tekan:

```text
Ctrl+C
```

Anda akan kembali ke prompt:

```text
~/cereblix-termux $
```

## 11. Menjalankan kembali

Tidak perlu mengisi wallet lagi. Cukup:

```sh
~/.local/share/cereblix-termux/start.sh
```

## 12. Mengubah konfigurasi di kemudian hari

Gunakan:

```sh
~/.local/share/cereblix-termux/start.sh --setup
```

Untuk melihat konfigurasi lokal:

```sh
cat ~/.local/share/cereblix-termux/config
```

File ini berisi wallet dan **harus tetap privat**.

## 13. Update repository

Masuk ke repository:

```sh
cd ~/cereblix-termux
```

Ambil perubahan terbaru:

```sh
git pull
```

Lalu jalankan installer lagi:

```sh
./install.sh
```

Installer dirancang untuk mempertahankan konfigurasi yang sudah ada saat melakukan rebuild/reinstall.

## 14. Jika muncul `No mirror or mirror group selected`

Jika terlihat seperti ini:

```text
No mirror or mirror group selected. You might want to select one by running 'termux-change-repo'
```

dan setelahnya terdapat:

```text
Reading package lists... Done
Building dependency tree... Done
...
```

itu biasanya hanya pemberitahuan mirror. Tidak perlu melakukan apa-apa jika proses paket berhasil.

Jika `pkg update` atau `pkg install` benar-benar gagal, jalankan:

```sh
termux-change-repo
```

Pilih mirror utama Termux yang dapat diakses perangkat, lalu ulangi:

```sh
pkg update -y
```

## 15. Jika wallet terus diminta

Periksa:

```sh
cat ~/.local/share/cereblix-termux/config
```

Cari:

```text
CRB_WALLET="crb1..."
```

Jika baris tersebut ada dan berisi wallet, `start.sh` seharusnya tidak meminta wallet lagi.

## 16. Jika `accepted=0`

Jangan langsung menganggap miner gagal. Biarkan berjalan beberapa menit.

Perhatikan dua nilai:

```text
accepted=...
rejected=...
```

Kondisi yang diharapkan:

```text
accepted=1 rejected=0
accepted=2 rejected=0
accepted=3 rejected=0
```

Waktu munculnya share dapat berubah-ubah.

## 17. Jika `rejected` bertambah

Hentikan miner dengan `Ctrl+C` dan periksa:

- wallet;
- nama worker;
- pool host;
- port;
- konfigurasi threads.

Jangan membagikan wallet lengkap di screenshot publik.

## 18. Ringkasan paling singkat

Jika Termux sudah terpasang, seluruh proses utama cukup:

```sh
pkg update -y
pkg install -y git
git clone https://github.com/ajiajiku/cereblix-termux.git
cd cereblix-termux
chmod +x install.sh
./install.sh
~/.local/share/cereblix-termux/start.sh --setup
~/.local/share/cereblix-termux/start.sh
```

Pada `--setup`, masukkan wallet, worker, dan jumlah threads.

Setelah miner berjalan, pastikan output menunjukkan `share accepted` dan `rejected=0`.
