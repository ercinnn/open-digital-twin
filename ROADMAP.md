# Yol Haritası – İleride Yapılabilecekler

Bu dosya, planlanan ama henüz uygulanmamış geliştirmeleri listeler.
Bir madde tamamlandığında buradan silinip ilgili açıklama `CLAUDE.md`'ye taşınmalıdır.

---

## 1. Sensör simülasyonunu Supabase'e taşımak (7/24 canlı ikiz)

**Amaç:** "Simulate Live Sensor" ve "Live" özelliklerinin bilgisayar / FastAPI backend açık olmadan,
her cihazdan (telefon dahil) çalışması ve ikizin 7/24 canlı veri üretmesi.

**Mevcut durum:** Simülasyon `backend/app/services/telemetry_simulator.py` içinde çalışıyor ve
`POST /api/v1/telemetry/simulate/{project_id}` ile tetikleniyor. Site backend'e `localhost:8000`
üzerinden ulaştığı için sadece backend'in çalıştığı bilgisayarda kullanılabiliyor.

**Planlanan çözüm (Edge Function gerekmez, tamamı veritabanında):**
- [ ] Yeni migration: sensör profillerini tutan `metric_profiles` tablosu
      (`category`, `metric_name`, `unit`, `nominal`, `sigma`, `warning`, `alert`, `direction`, `reversion`, `excursion_probability`).
      Değerler `telemetry_simulator.py` içindeki `PROFILES` ile birebir aynı olmalı.
- [ ] PL/pgSQL fonksiyonu `simulate_project_telemetry(project_id uuid)`:
      son değerden devam eden, normale dönme eğilimli rastgele yürüyüş (Box-Muller ile gauss gürültü),
      %4 ihtimalle arıza sıçraması, eşiklere göre `components.status` güncellemesi
      (`in_progress` asla değiştirilmez).
- [ ] Editörlerin düğmeden çağırabileceği RPC (`is_editor()` kontrolü ile, `security definer`).
- [ ] Flutter: `TwinRepositoryImpl.simulateTelemetry` backend yerine `supabase.rpc(...)` çağırsın.
- [ ] **pg_cron** ile her 1 dakikada tüm projeler için otomatik simülasyon.
- [ ] **Veri saklama:** her gün 7 günden eski `telemetry_logs` satırlarını silen ikinci pg_cron görevi
      (tablo boyutu ~30 MB civarında sabit kalır).
- [ ] **Uyku modu koruması:** Supabase ücretsiz projeleri ~1 hafta hareketsiz kalınca duraklatılabiliyor.
      Haftada bir Supabase'e istek atan GitHub Actions zamanlanmış görevi (`schedule:` cron).
- [ ] Python simülatörü yerel testler için kalabilir; iki tarafın profilleri senkron tutulmalı.

**Ücretsiz plan hesabı (dakikada 16 ölçüm ile):**

| Kaynak | Ücretsiz sınır | Tahmini kullanım |
|---|---|---|
| Veritabanı | 500 MB | Temizliksiz ~100+ MB/ay → 7 gün saklama ile ~30 MB |
| Realtime mesajları | 2 milyon / ay | Sadece site açıkken harcanır |
| Egress | 5 GB / ay | GLB modeller 50–150 KB |

**Uygulamadan önce kontrol edilecek:** Supabase organizasyonunun planı ve faturası
(organizasyonda 3 aktif proje var; ücretsiz planda normalde sınır 2).

---

## 2. Diğer açık maddeler

- [ ] **CAD işlemeyi buluta taşımak:** FastAPI + Blender için Docker imajı (Cloud Run / Render / VPS, ~1–2 GB RAM).
      Önce backend uç noktalarına kimlik doğrulama eklenmeli (Supabase JWT + `is_editor()`); şu an backend
      sadece yerel çalıştığı için yetki kontrolü yok.
- [ ] **Gerçek sensör entegrasyonu** (ayrıntılar `CLAUDE.md` → "Sensor / Telemetry Integration Contract"):
  - [ ] Eşik kontrolünü veritabanına taşımak: `telemetry_logs` insert tetikleyicisi, `metric_profiles` eşiklerine göre
        `components.status` günceller (`in_progress` hariç). Böylece gerçek sensör verisi de 3D'de renk değiştirir.
        Madde 1'deki profil tablosuyla aynı altyapı – birlikte yapılmalı.
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
