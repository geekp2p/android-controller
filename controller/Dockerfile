FROM debian:stable-slim

# ติดตั้งเครื่องมือที่ต้องใช้
RUN apt-get update && apt-get install -y --no-install-recommends \
      android-tools-adb android-tools-fastboot \
      usbutils udev iputils-ping curl procps ca-certificates python3 python3-pil \
      python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# udev rule สำหรับ Samsung (Vendor ID: 04e8) ให้สิทธิ์อุปกรณ์ USB
RUN groupadd -g 1001 plugdev || true && \
    printf 'SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="plugdev"\n' \
      > /etc/udev/rules.d/51-android.rules

ENV ADB_SERVER_PORT=5037
WORKDIR /work

# Utility scripts
COPY touch_event_capture.py /usr/local/bin/touch-event-capture.py
COPY capture_ui_and_screen.py /usr/local/bin/capture-ui-and-screen.py
COPY overlay_touches.py /usr/local/bin/overlay-touches.py
COPY replay_log.py /usr/local/bin/replay-log.py
COPY ui_dump_capture.py /usr/local/bin/ui-dump-capture.py
RUN chmod +x /usr/local/bin/touch-event-capture.py \
    && chmod +x /usr/local/bin/capture-ui-and-screen.py \
    && chmod +x /usr/local/bin/overlay-touches.py \
    && chmod +x /usr/local/bin/replay-log.py \
    && chmod +x /usr/local/bin/ui-dump-capture.py

# คงอยู่รอคำสั่งจาก docker-compose (ทั้งโหมด server และ client ใช้ภาพเดียวกัน)
CMD ["bash","-lc","echo image ready; tail -f /dev/null"]
