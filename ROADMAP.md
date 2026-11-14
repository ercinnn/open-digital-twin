# Yol Haritası – İleride Yapılabilecekler

Bu dosya, planlanan ama henüz uygulanmamış geliştirmeleri listeler.
Bir madde tamamlandığında buradan silinip ilgili açıklama `CLAUDE.md`'ye taşınmalıdır.

---

## 1. Açık maddeler

- [ ] **Supabase plan/fatura kontrolü:** organizasyonda 3 aktif Supabase projesi olduğu not edilmişti; ücretsiz planda
      normalde sınır 2. (Sensör simülasyonu 7/24 veritabanında çalışıyor – migration 004, `CLAUDE.md` §4.)
- [ ] **Veritabanı boyutunu izlemek:** simülatör günde ~130 bin satır yazıyor (4 gün saklama ≈ 100–190 MB). Yeni proje/metrik
      eklenirse `odt_telemetry_retention` süresi yeniden hesaplanmalı.

- [ ] **CAD işlemeyi (ingest) buluta taşımak:** kod hazır – editör girişi kontrolü (`app/auth.py`), arka plan işleri,
      `backend/Dockerfile` (Blender 4.2 LTS Linux), uygulama uyuyan sunucunun uyanmasını bekliyor. Sadece barındırma seçilmeli
      (Kasım 2026 fiyatları, uygulamadan önce tekrar kontrol edilmeli):
  - Google Cloud Run: kart gerekir; instance-based billing aylık 240k vCPU-sn ücretsiz kota, imaj deposu için birkaç sent.
    Arka plan işleri yanıt döndükten sonra da CPU istediği için `--no-cpu-throttling` (instance-based) kullanılmalı.
  - Hetzner VPS CX23 (2 vCPU / 4 GB): ~€5,5–6/ay, sürekli açık.
  - Hugging Face Docker Space: PRO (~9 $/ay) gerekir; `scripts/deploy_hf_space.py` hazır.
  - Barındırma sonrası: GitHub repo değişkeni `BACKEND_URL`, sunucuda `CORS_ORIGINS=https://ercinnn.github.io`.
- [ ] **Ingest işlerini kalıcı yapmak:** işler bellekte tutuluyor; sunucu yeniden başlarsa yarım kalan iş kaybolur
      (kullanıcı tekrar başlatır). Gerekirse `ingest_jobs` tablosuna taşınabilir.
- [ ] **Gerçek sensör entegrasyonu** (ayrıntılar `CLAUDE.md` → "Sensor / Telemetry Integration Contract"):
  - [ ] Eşik kontrolünü veritabanına taşımak: `telemetry_logs` insert tetikleyicisi, `metric_profiles` eşiklerine göre
        `components.status` günceller (`in_progress` hariç). Böylece gerçek sensör verisi de 3D'de renk değiştirir.
        `metric_profiles` tablosu migration 004 ile hazır; simülatör kendi statü güncellemesini yaptığı için
        tetikleyici simülatör satırlarını atlamalı (ya da simülatör statü güncellemesini tetikleyiciye bırakmalı).
  - [ ] Cihaz anahtarlı güvenli ölçüm giriş noktası (Supabase Edge Function + `devices` tablosu, cihaz başına iptal edilebilir anahtar,
        sadece telemetri yazma yetkisi). Sahadaki cihazlara `service_role` anahtarı asla konmamalı.
  - [ ] Hazır ağ geçidi programı (Raspberry Pi / PC): Modbus TCP, MQTT ve HTTP kaynaklarından okuyup dakikalık ortalamayla gönderen,
        internet kesintisinde yerelde biriktirip sonra gönderen yapı (gemiler için önemli).
  - [ ] Gemi alarm/izleme sistemi (AMS) için OPC UA / NMEA 2000, bina otomasyonu için BACnet bağlayıcıları.
- [ ] **Gerçek dosyalarla test:** `.step` ve `.ocx` okuyucuları henüz gerçek bir dosyayla denenmedi.
- [ ] **Masaüstü ve mobil test:** Windows (`flutter run -d windows`, WebView2) ve Android/iOS 3D görüntüleyici yolları
      yazıldı ama çalıştırılarak denenmedi.
- [ ] **GitHub Actions güncellemesi:** Node.js 20 kullanan action'lar (`checkout@v4`, `configure-pages@v5`,
      `upload-pages-artifact@v3`, `deploy-pages@v4`) yeni sürümlere yükseltilmeli.
- [ ] **Demo verisini sıfırlama:** durumları ve telemetriyi `seed.sql`'deki başlangıç hâline döndüren bir betik/komut.
