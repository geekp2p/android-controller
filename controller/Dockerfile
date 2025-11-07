FROM debian:stable-slim

# ติดตั้งเครื่องมือที่ต้องใช้
RUN apt-get update && apt-get install -y --no-install-recommends \
      android-tools-adb android-tools-fastboot \
      usbutils udev iputils-ping curl procps ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# udev rule สำหรับ Samsung (Vendor ID: 04e8) ให้สิทธิ์อุปกรณ์ USB
RUN groupadd -g 1001 plugdev || true && \
    printf 'SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev"\n' \
      > /etc/udev/rules.d/51-android.rules

ENV ADB_SERVER_PORT=5037
WORKDIR /work

# คงอยู่รอคำสั่งจาก docker-compose (ทั้งโหมด server และ client ใช้ภาพเดียวกัน)
CMD ["bash","-lc","echo image ready; tail -f /dev/null"]
