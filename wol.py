#!/usr/bin/env python3
"""Wake-on-LAN マジックパケット送信ツール。

標準ライブラリのみで動作します(追加インストール不要)。

使い方:
    # MACアドレスを直接指定して送信
    python3 wol.py 00:11:22:33:44:55

    # devices.json に登録したデバイス名で送信
    python3 wol.py --device desktop-pc

    # ブロードキャスト先やポートを指定(VPN越しなどでサブネットが違う場合)
    python3 wol.py 00:11:22:33:44:55 --ip 192.168.1.255 --port 9
"""

import argparse
import json
import re
import socket
import sys
from pathlib import Path

DEVICES_FILE = Path(__file__).parent / "devices.json"
DEFAULT_IP = "255.255.255.255"
DEFAULT_PORT = 9


def normalize_mac(mac: str) -> str:
    """MACアドレスの区切り文字(: - . 空白)を取り除き、12桁の16進文字列に正規化する。"""
    cleaned = re.sub(r"[.:\-\s]", "", mac).lower()
    if not re.fullmatch(r"[0-9a-f]{12}", cleaned):
        raise ValueError(f"MACアドレスの形式が不正です: {mac!r}")
    return cleaned


def build_magic_packet(mac: str) -> bytes:
    """FF x6 + MACアドレス x16 のマジックパケットを組み立てる。"""
    mac_bytes = bytes.fromhex(normalize_mac(mac))
    return b"\xff" * 6 + mac_bytes * 16


def send_magic_packet(mac: str, ip: str = DEFAULT_IP, port: int = DEFAULT_PORT) -> None:
    packet = build_magic_packet(mac)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        # 取りこぼし対策として3回送る(UDPなので届く保証がないため)
        for _ in range(3):
            sock.sendto(packet, (ip, port))


def load_devices() -> dict:
    if not DEVICES_FILE.exists():
        return {}
    with DEVICES_FILE.open(encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser(description="Wake-on-LAN マジックパケットを送信します。")
    parser.add_argument("mac", nargs="?", help="起動したいPCのMACアドレス (例: 00:11:22:33:44:55)")
    parser.add_argument("--device", "-d", help="devices.json に登録したデバイス名")
    parser.add_argument("--ip", default=None, help=f"送信先IP/ブロードキャストアドレス (既定: {DEFAULT_IP})")
    parser.add_argument("--port", type=int, default=None, help=f"送信先UDPポート (既定: {DEFAULT_PORT})")
    parser.add_argument("--list", action="store_true", help="devices.json の登録デバイス一覧を表示")
    args = parser.parse_args()

    devices = load_devices()

    if args.list:
        if not devices:
            print("devices.json にデバイスが登録されていません。")
        for name, info in devices.items():
            print(f"{name}: {info.get('mac', '?')} (ip={info.get('ip', DEFAULT_IP)}, port={info.get('port', DEFAULT_PORT)})")
        return 0

    mac = args.mac
    ip = args.ip
    port = args.port

    if args.device:
        if args.device not in devices:
            print(f"エラー: デバイス '{args.device}' は devices.json に登録されていません。", file=sys.stderr)
            print("登録済みデバイス: " + (", ".join(devices) or "(なし)"), file=sys.stderr)
            return 1
        entry = devices[args.device]
        mac = entry["mac"]
        ip = ip or entry.get("ip")
        port = port or entry.get("port")

    if not mac:
        parser.print_help()
        return 1

    ip = ip or DEFAULT_IP
    port = port or DEFAULT_PORT

    try:
        send_magic_packet(mac, ip, port)
    except ValueError as e:
        print(f"エラー: {e}", file=sys.stderr)
        return 1

    print(f"マジックパケットを送信しました: MAC={mac} -> {ip}:{port}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
