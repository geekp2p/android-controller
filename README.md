# Android Controller (ADB via Docker) — Galaxy A17

ควบคุม Android (เช่น **Galaxy A17**) ผ่าน **Docker** โดยให้ **ADB Server รันในคอนเทนเนอร์** และใช้งานได้ทั้ง **USB-C** และ **Wi‑Fi (Wireless debugging)**  
ไฟล์คีย์/งานทั้งหมดเก็บที่ **D:\\android-controller** ไม่แตะไดรฟ์ C

---

## โครงสร้างโฟลเดอร์ (บน D:)
```
D:\android-controller\
├─ docker-compose.yml
├─ controller\
│  └─ Dockerfile
├─ adbkeys\        # เก็บคีย์ ADB (persist)
└─ data\           # พื้นที่ใช้งาน (screencap / APK / logs)
```

> **หมายเหตุ**: โปรเจกต์นี้ตั้งค่าให้ `controller` (ADB client) ชี้ไปหา `adb-server` ภายใน container เดียวกัน (ผ่าน `network_mode: service:adb-server`) จึง **ไม่พึ่ง ADB บน Windows**

---

## ความต้องการ (Prerequisites)
- Windows 11 + WSL2 + Docker Desktop (เปิด `Use the WSL 2 based engine`)
- ติดตั้ง **usbipd-win** เพื่อ passthrough USB ไปยัง WSL/Docker (ใช้เฉพาะโหมด USB)  
  ตรวจสอบเวอร์ชัน:
  ```powershell
  usbipd --version
  ```
- โทรศัพท์ Android เปิด **Developer options** พร้อม:
  - ✅ **USB debugging**
  - ✅ **Wireless debugging**
  - ✅ (แนะนำ) **Disable adb authorization timeout**
  - ✅ (แนะนำ) **Stay awake / หน้าจอติดขณะชาร์จ**

---

## Quick Start (TL;DR)
```powershell
# 1) สตาร์ทคอนเทนเนอร์
cd D:\android-controller
docker compose up -d --build
docker compose up --build

# 2A) (USB) แนบมือถือเข้ากับ WSL/Docker
usbipd wsl list
usbipd wsl attach --busid <BUSIDของSamsung> --distribution "docker-desktop"

# 2B) (Wi‑Fi) จับคู่/เชื่อมจากในคอนเทนเนอร์
docker compose exec controller bash
adb pair <PHONE_IP>:<PAIR_PORT>
adb connect <PHONE_IP>:<ADB_PORT>
adb devices -l
```

---

## ขั้นตอนเต็มแบบ **Step‑by‑Step**

### 0) เตรียมโทรศัพท์ (ทำครั้งเดียว)
1. Settings → About phone → Software information → กด **Build number** 7 ครั้ง เพื่อเปิด Developer options  
2. Settings → **Developer options**
   - เปิด **USB debugging**
   - เปิด **Wireless debugging**
   - (แนะนำ) เปิด **Disable adb authorization timeout**
   - (แนะนำ) เปิด **Stay awake**

### 1) สตาร์ทโปรเจกต์ Docker
```powershell
cd D:\android-controller
docker compose up -d --build
```
ระบบจะรัน 2 services:
- **adb-server** — ADB server ในคอนเทนเนอร์ (รองรับ USB+Wi‑Fi)
- **android-controller** — ตัวสั่งงาน (ADB client) ชี้ไป `127.0.0.1:5037` ภายใน network เดียวกัน

เข้าเชลล์ของคอนเทนเนอร์ **controller**:
```powershell
docker compose exec controller bash
```

### 2A) โหมด **USB-C** (เสถียรสุด)
1. เสียบสาย USB-C กับโทรศัพท์ (ปลดล็อกจอไว้)
2. PowerShell (Admin) ที่ Windows:
   ```powershell
   usbipd wsl list
   usbipd wsl attach --busid <BUSIDของSamsung> --distribution "docker-desktop"
   ```
3. ใน shell ของคอนเทนเนอร์ **controller**:
   ```bash
   adb devices -l            # มือถือจะเด้ง RSA popup → ติ๊ก Always allow → Allow
   adb devices -l            # ควรเห็น <serial> device
   ```

> ถ้าไม่เห็น ให้เข้า container **adb-server** รีโหลด udev/adb:
```powershell
docker compose exec adb-server bash
```
```bash
udevadm control --reload-rules && udevadm trigger
adb kill-server
adb start-server -a -H 0.0.0.0 -P 5037
```

### 2B) โหมด **Wi‑Fi (Wireless debugging)**
1. โทรศัพท์ → Developer options → Wireless debugging → **Pair device with pairing code**
   - จด **IP**, **Pairing port**, และ **Pairing code**
   - ในหน้าเดียวกันมี “**IP address & Port**” สำหรับ `adb connect` (อาจไม่ใช่ 5555)
2. ในคอนเทนเนอร์ **controller**:
   ```bash
   adb pair <PHONE_IP>:<PAIR_PORT>     # ใส่ pairing code เมื่อระบบถาม
   adb connect <PHONE_IP>:<ADB_PORT>   # ใช้พอร์ตที่แสดงในหน้า Wireless debugging
   adb devices -l
   ```

> ใช้ทั้ง USB + Wi‑Fi พร้อมกันได้ และเจาะจงเครื่องด้วย `-s`:
```bash
adb -s R5CTxxxxxxx shell getprop ro.product.model
adb -s 192.168.1.55:43435 shell getprop ro.build.id
```

---

## คำสั่งใช้งานที่พบบ่อย
> รันจากในคอนเทนเนอร์ **controller** (ไฟล์งานอยู่ที่ `/work` → `D:\android-controller\data\`)

```bash
# ข้อมูลเครื่อง / เวอร์ชัน
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release

# คลิก/ปัด
adb shell input tap 540 1200
adb shell input swipe 200 1200 200 200 300

# ติดตั้ง/ถอนแอป
adb install -r /work/app.apk
adb shell pm uninstall com.example.app

# จอภาพ / ไฟล์
adb shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png /work/
adb pull /sdcard/Android/data/com.example.app/files/log.txt /work/

# logcat
adb logcat
```

ไฟล์ที่ดึงออกมา (เช่น `s.png`, `log.txt`) จะอยู่ใน `D:\android-controller\data\`

---

## การหยุดงาน/ปิดระบบ
```powershell
# หยุดเฉพาะโปรเจกต์นี้
cd D:\android-controller
docker compose down
```

---

## ล้างโปรเจกต์นี้ให้ “สะอาด”
> ลบเฉพาะสิ่งที่โปรเจกต์นี้สร้าง/ใช้ ไม่กระทบ Docker อื่น ๆ

```powershell
cd D:\android-controller

# 1) หยุดและลบ container + images ที่ build จากโปรเจกต์นี้
docker compose down --remove-orphans --rmi local

# 2) ปลด USB ออกจาก WSL/Docker (ถ้าใช้ USB)
usbipd wsl list
usbipd wsl detach --busid <BUSIDของSamsung>

# 3) เก็บกวาด cache ที่ไม่ใช้งาน
docker builder prune -f

# 4) (ตัวเลือก) ลบข้อมูลผูก mount ทั้งหมดของโปรเจกต์
Remove-Item -Recurse -Force D:\android-controller\adbkeys
Remove-Item -Recurse -Force D:\android-controller\data
```

> ถ้าจะลบทั้งโฟลเดอร์โปรเจกต์:  
> `Remove-Item -Recurse -Force D:\android-controller`

---

## Troubleshooting

- **`device unauthorized`**  
  ถอด–เสียบสายใหม่, ปลดล็อกจอ, ตอบ **Allow** ที่ RSA popup และติ๊ก **Always allow**

- **`offline` (Wi‑Fi)**  
  `adb disconnect <IP:PORT>` แล้ว `adb connect` ใหม่; ตรวจว่ามือถือกับพีซีอยู่ **วง Wi‑Fi เดียวกัน**

- **ไม่เห็นอุปกรณ์ (USB)**  
  เช็กว่า `usbipd wsl attach` สำเร็จ, สาย/พอร์ต USB ดี, ลองรีโหลด udev/adb ใน `adb-server` ตามด้านบน

- **ADB pairing ล้มเหลว**  
  เปิดหน้า Wireless debugging ใหม่ → Pair device with pairing code อีกครั้ง และใช้ **พอร์ตที่แสดงจริง** ใน `adb connect`

- **หลายเครื่องพร้อมกัน**  
  ใช้ `adb -s <serial|ip:port> ...` หรือกำหนด `ANDROID_SERIAL=<serial>` ก่อนสั่ง

---

## ข้อควรระวังด้านความปลอดภัย
- เลือกใช้เฉพาะเครือข่ายที่ไว้ใจได้ (โดยเฉพาะโหมด Wi‑Fi)
- ปิด **Wireless debugging** เมื่อไม่ใช้งาน
- เก็บโฟลเดอร์ `adbkeys` ให้ปลอดภัย เพราะมี private keys สำหรับการเชื่อมต่อ ADB

---

## ใบอนุญาต
MIT (แก้ไขใช้ภายในองค์กร/โครงการได้อิสระ)
