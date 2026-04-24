#!/usr/bin/env python3
import sys
import struct
import binascii
from pathlib import Path
from PIL import Image
from scapy.all import sendp, Ether, Raw, get_if_list

# Cấu hình khớp với FPGA
MAGIC = 0x1606
TARGET_WIDTH = 640 
TARGET_HEIGHT = 480
# THAY ĐỔI ĐỊA CHỈ MAC NÀY (Xem trên nhãn dán ở board DE2 hoặc tự định nghĩa)
DE2_MAC = "00:07:ed:ff:ed:15" 
# Tên card mạng máy tính của bạn (VD: "Ethernet", "eth0", "enp3s0")
INTERFACE = "Ethernet" 

def load_and_convert_image(image_path: Path):
    with Image.open(image_path) as im:
        img = im.convert("RGB").resize((TARGET_WIDTH, TARGET_HEIGHT))
        
    raw_565 = bytearray()
    for r, g, b in img.getdata():
        # Chuyển RGB888 sang RGB565 (2 byte)
        pixel = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        raw_565.extend(struct.pack(">H", pixel))
    return bytes(raw_565)

def send_raw_image(image_path: Path):
    if not image_path.exists():
        print("File không tồn tại!")
        return

    print(f"Đang xử lý ảnh: {image_path}...")
    payload = load_and_convert_image(image_path)
    
    # Tạo Header: Magic(2b) + CRC32(4b)
    crc = binascii.crc32(payload) & 0xFFFFFFFF
    header = struct.pack(">HI", MAGIC, crc)
    
    full_data = header + payload

    print(f"Đang gửi gói tin thô qua {INTERFACE}...")
    print(f"Tổng dung lượng: {len(full_data)} bytes")

    # Tạo gói tin Ethernet thô
    # Type 0x0800 thường là IP, nhưng ta gửi Raw nên có thể dùng type tùy ý hoặc 0x88b5 (Local experimental)
    pkt = Ether(dst=DE2_MAC, type=0x88b5) / Raw(load=full_data)
    
    # Gửi gói tin
    sendp(pkt, iface=INTERFACE, verbose=True)
    print("Đã gửi xong!")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Cách dùng: python raw_eth_sender.py <đường_dẫn_ảnh>")
    else:
        send_raw_image(Path(sys.argv[1]))