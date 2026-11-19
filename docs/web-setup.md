# Panduan menyiapkan Supabase, Vercel, dan GitHub Secrets

Panduan ini untuk deployment web. Android tidak berubah dan tidak memakai salah satu
dari sini. Lakukan urut; tandai centang sendiri.

Keputusan yang sudah dipakai: `email + password`, seed kategori oleh Flutter setelah
login, region `ap-southeast-1` (Singapore), versi `1.12.0+25`.

---

## 1. Supabase

### 1.1 Buat project

1. Buka https://supabase.com/dashboard → **New project**.
2. Name: `expense-tracker` (bebas, lowercase).
3. Database password: simpan di password manager. **Jangan** dipakai di Flutter.
4. Region: **jangan pilih Auto**. Pilih **Asia-Pacific** (general region, akan
   ditempatkan di Singapore) atau **Southeast Asia (Singapore) —
   `ap-southeast-1`** dari daftar specific regions.

   Auto memilih dari lokasi jaringan yang terdeteksi saat itu (bisa IP/VPN),
   bukan lokasi user aplikasi. Auto sering menghasilkan `ap-northeast-1`
   (Tokyo). Region **tidak bisa diubah setelah project dibuat** — satu-satunya
   cara pindah adalah project baru lalu migrasi. Supabase tidak punya region
   Indonesia; Singapore yang terdekat.
5. Tunggu sampai status project **Active** (biasanya 1–3 menit).

### 1.2 Ambil kredensial yang dipakai web

**Project Settings → API**:

- `Project URL` → nilai `SUPABASE_URL`
- `anon public` → nilai `SUPABASE_ANON_KEY`

Keduanya **boleh** tertanam di build web dan boleh masuk GitHub Secrets. Anon key
h diberi akses oleh RLS, jadi bukan rahasia.

**Jangan pernah** memakai `service_role` di Flutter, di `--dart-define`, atau di
GitHub Actions. Kunci itu melewati RLS.

### 1.3 Jalankan skema SQL

**SQL Editor → New query**, tempel isi `docs/supabase_schema.sql`, lalu **Run**.
File itu membuat:

- tabel `categories`, `subcategories`, `transactions`
- `user_id uuid references auth.users` pada ketiganya
- index `(user_id, date DESC)` pada `transactions`
- RLS `auth.uid() = user_id` untuk SELECT/INSERT/UPDATE/DELETE
- policy seed yang mengizinkan user menulis kategori bawaan miliknya

Verifikasi di **Table Editor**: ketiga tabel ada, dan kolom `RLS enabled`
tercentang.

### 1.4 Aktifkan auth email + password

**Authentication → Providers → Email**:

- pastikan **Enabled**
- **Confirm email**: boleh dibiarkan aktif untuk produksi. Untuk smoke test
  lebih mudah, matikan dulu — atau buat user langsung dari dashboard (langkah
  berikut) supaya tidak perlu menunggu email.

**Authentication → URL Configuration**:

- Site URL: `http://localhost:5000`
- Redirect URLs, tambahkan:
  - `http://localhost:*/**`
  - `http://127.0.0.1:*/**`
  - `https://<nama-project>.vercel.app/**`
  - domain final kalau ada

### 1.5 Buat dua user uji

**Authentication → Users → Add user** dua kali:

- user A: `usera@example.test` / password
- user B: `userb@example.test` / password

Keduanya dipakai untuk uji RLS: A tidak boleh melihat data B.

---

## 2. Vercel

Vercel hanya jadi host static. Flutter di-build di GitHub Actions, Vercel **tidak**
build apa pun.

### 2.1 Buat project lewat CLI

Di WSL / terminal apa pun yang punya Node:

```sh
npm i -g vercel
vercel login
vercel project create expense-tracker-web
```

Lalu set supaya tidak ada build otomatis:

```sh
vercel project update expense-tracker-web \
  --framework other \
  --build-command "" \
  --output-directory build/web
```

Kalau `--build-command ""` ditolak CLI, lakukan lewat dashboard:
**Project → Settings → Build & Development Settings** → Framework Preset `Other`,
Build Command dikosongkan, Output Directory `build/web`.

Pastikan project **tidak** dihubungkan ke repository GitHub — biar tidak ada
build yang dipicu dari Git. Deploy hanya lewat Actions.

### 2.2 Ambil tiga nilai untuk GitHub Secrets

```sh
vercel project inspect expense-tracker-web --json
```

Dari hasilnya:

- `id` → `VERCEL_PROJECT_ID`
- `accountId` (atau team id) → `VERCEL_ORG_ID`

Buat token: **Vercel dashboard → Settings → Tokens → Create Token**.
Namanya misalnya `github-actions-expense-tracker`. Isinya → `VERCEL_TOKEN`.

Token ini rahasia. Jangan taruh di kode, jangan tempel di chat kalau tidak perlu.

Catatan: `vercel.json` di repo akan berisi rewrite `/(.*) → /index.html` supaya
`/statistics` tidak 404 saat di-refresh.

---

## 3. GitHub

Bagian ini saya yang kerjakan setelah kode selesai:

- `vercel.json` di root repo
- `.github/workflows/deploy-web.yml` — jalankan `flutter test`, build web dengan
  `--dart-define`, lalu `vercel deploy --prod`
- tidak menyentuh `.github/workflows/release.yml` (APK tetap dari tag `v*`)

Yang masih harus kamu isi (atau beri saya untuk saya set lewat `gh secret set`):

| Secret | Sumber |
|---|---|
| `SUPABASE_URL` | Supabase Project Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Supabase Project Settings → API → anon public |
| `VERCEL_TOKEN` | Vercel → Settings → Tokens |
| `VERCEL_ORG_ID` | `vercel project inspect --json` |
| `VERCEL_PROJECT_ID` | `vercel project inspect --json` |

Perintah kalau mau saya set setelah kamu beri nilainya:

```sh
gh secret set SUPABASE_URL --repo Zierch/expense_tracker
gh secret set SUPABASE_ANON_KEY --repo Zierch/expense_tracker
gh secret set VERCEL_TOKEN --repo Zierch/expense_tracker
gh secret set VERCEL_ORG_ID --repo Zierch/expense_tracker
gh secret set VERCEL_PROJECT_ID --repo Zierch/expense_tracker
```

anon key memang publik; tetap saya simpan sebagai secret supaya tidak perlu
ditulis ulang di workflow.

---

## 4. Setelah semua siap

1. Beri saya kelima nilai di atas (token boleh kamu isi sendiri lewat `gh secret set`).
2. Saya set Secrets, jalankan workflow, dan cek deploy.
3. Smoke test di Chrome: login A, CRUD, pindah bulan, statistik, tema, export.
4. Login B → harus tidak melihat transaksi A. Kalau melihat, RLS gagal.

Sebelum itu, saya bisa menyelesaikan kode + build web memakai dart-define dummy.
Yang **tidak** bisa saya buktikan tanpa project asli: login, CRUD, dan RLS.

## 5. Akun demo untuk portofolio

Situs live: https://expense-tracker-web-ruddy-sigma.vercel.app

| | |
|---|---|
| Email | `demo@expensetracker.app` |
| Password | `Demo12345!` |

Akun ini berisi 10 transaksi **palsu** dari kategori bawaan — bukan data
siapa-siapa. Boleh dipublikasikan di portofolio supaya pembuka tautan bisa
langsung melihat dashboard dan statistik yang terisi. Jangan pakai akun ini
untuk data sungguhan: kata sandinya sengaja dibagikan.

Akun `usera@example.test` dan `userb@example.test` dipakai untuk uji RLS dan
tidak boleh dicantumkan di portofolio.
