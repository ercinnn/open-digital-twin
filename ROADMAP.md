# Yol Haritası – İleride Yapılabilecekler

Bu dosya, planlanan ama henüz uygulanmamış geliştirmeleri listeler.
Bir madde tamamlandığında buradan silinip ilgili açıklama `CLAUDE.md`'ye taşınmalıdır.

---

## 1. Açık maddeler

- [ ] **Supabase plan/fatura kontrolü:** organizasyonda 3 aktif Supabase projesi olduğu not edilmişti; ücretsiz planda
      normalde sınır 2. (Sensör simülasyonu 7/24 veritabanında çalışıyor – migration 004, `CLAUDE.md` §4.)
- [ ] **Veritabanı boyutunu izlemek:** simülatör günde ~130 bin satır yazıyor (4 gün saklama ≈ 100–190 MB). Yeni proje/metrik
      eklenirse `odt_telemetry_retention` süresi yeniden hesaplanmalı.

- [ ] **CAD işlemeyi buluta taşımak:** FastAPI + Blender için Docker imajı (Cloud Run / Render / VPS, ~1–2 GB RAM).
      Önce backend uç noktalarına kimlik doğrulama eklenmeli (Supabase JWT + `is_editor()`); şu an backend
      sadece yerel çalıştığı için yetki kontrolü yok.
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
