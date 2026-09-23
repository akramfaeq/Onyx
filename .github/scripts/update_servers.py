"""
update_servers.py
يجيب سيرفرات VPN من VPNGate، يختبر كل واحد، يحفظ الشغّالين في Supabase.
"""

import os
import csv
import base64
import socket
import time
import requests
from io import StringIO
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_PING_MS  = 300   # نرفض أي سيرفر أبطأ من كذا
MAX_SERVERS  = 80    # أقصى عدد نحفظه في Supabase
TEST_TIMEOUT = 3     # ثواني لكل ping test
MAX_PER_COUNTRY = 3  # أقصى سيرفرات لكل دولة


# ──────────────────────────────────────────────
# جيب من VPNGate
# ──────────────────────────────────────────────
def fetch_vpngate() -> list[dict]:
    urls = [
        "https://www.vpngate.net/api/iphone/",
        "https://vpngate.net/api/iphone/",
    ]
    for url in urls:
        try:
            r = requests.get(url, timeout=15,
                             headers={"User-Agent": "Mozilla/5.0"})
            if r.status_code != 200:
                continue

            lines = r.text.splitlines()
            # السطر الأول تعليق، الثاني headers
            csv_text = "\n".join(lines[1:])
            reader = csv.reader(StringIO(csv_text))
            headers = next(reader, None)
            if not headers:
                continue

            servers = []
            for row in reader:
                if len(row) <= 14 or not row[14]:
                    continue
                try:
                    ping = int(row[3]) if row[3].isdigit() else 999
                    if ping > MAX_PING_MS:
                        continue
                    config = base64.b64decode(row[14]).decode("utf-8")
                    country_name = row[5].split("(")[0].strip()
                    country_code = row[6].upper()[:2]
                    if not country_name or not country_code:
                        continue
                    sessions = int(row[7]) if row[7].isdigit() else 0
                    servers.append({
                        "country_name": country_name,
                        "country_code": country_code,
                        "ip": row[1],
                        "ping": ping,
                        "ovpn_config": config,
                        "num_sessions": sessions,
                        "source": "vpngate",
                        "protocol": "openvpn",
                    })
                    if len(servers) >= 200:
                        break
                except Exception:
                    continue

            if servers:
                print(f"[VPNGate] جبنا {len(servers)} سيرفر")
                return servers

        except Exception as e:
            print(f"[VPNGate] خطأ: {e}")

    return []


# ──────────────────────────────────────────────
# اختبر ping بـ TCP (أسرع من ICMP ولا يحتاج root)
# ──────────────────────────────────────────────
def tcp_ping(host: str, port: int = 443, timeout: float = TEST_TIMEOUT) -> int:
    """يرجع الـ ping بالمللي ثانية، أو 9999 إذا فشل."""
    try:
        start = time.monotonic()
        with socket.create_connection((host, port), timeout=timeout):
            pass
        ms = int((time.monotonic() - start) * 1000)
        return ms
    except Exception:
        # جرّب port 1194 (OpenVPN الافتراضي)
        try:
            start = time.monotonic()
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, 1194))
            sock.close()
            if result == 0:
                return int((time.monotonic() - start) * 1000)
        except Exception:
            pass
        return 9999


# ──────────────────────────────────────────────
# فلتر وترتيب السيرفرات
# ──────────────────────────────────────────────
def filter_and_sort(servers: list[dict]) -> list[dict]:
    print(f"[Filter] نختبر {len(servers)} سيرفر...")

    tested = []
    seen_ips = set()

    for s in servers:
        ip = s["ip"]
        if ip in seen_ips:
            continue
        seen_ips.add(ip)

        # اختبر الاتصال الفعلي
        actual_ping = tcp_ping(ip)
        if actual_ping > MAX_PING_MS:
            continue

        # استخدم أقل قيمة بين الـ ping المُبلَّغ والمُختبَر
        s["ping"] = min(s["ping"], actual_ping)
        s["is_active"] = True
        tested.append(s)

    print(f"[Filter] {len(tested)} سيرفر نجح في الاختبار")

    # رتّب: ping + ازدحام
    def score(s):
        congestion = min(s.get("num_sessions", 0) // 10, 200)
        return s["ping"] + congestion

    tested.sort(key=score)

    # حدّ لكل دولة
    country_count: dict[str, int] = {}
    result = []
    for s in tested:
        cc = s["country_code"]
        count = country_count.get(cc, 0)
        if count < MAX_PER_COUNTRY:
            result.append(s)
            country_count[cc] = count + 1
        if len(result) >= MAX_SERVERS:
            break

    print(f"[Filter] {len(result)} سيرفر بعد التحديد")
    return result


# ──────────────────────────────────────────────
# ارفع على Supabase
# ──────────────────────────────────────────────
def upload_to_supabase(servers: list[dict]):
    client = create_client(SUPABASE_URL, SUPABASE_KEY)

    # أوقف القديمة
    client.table("servers").update({"is_active": False}).neq("ip", "").execute()

    # ارفع الجديدة
    batch_size = 20
    uploaded = 0
    for i in range(0, len(servers), batch_size):
        batch = servers[i:i + batch_size]
        client.table("servers").upsert(batch, on_conflict="ip").execute()
        uploaded += len(batch)
        print(f"[Supabase] رفعنا {uploaded}/{len(servers)}")

    print(f"[Supabase] ✅ اكتمل — {len(servers)} سيرفر")


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
def main():
    print("=" * 50)
    print("بدأ تحديث السيرفرات")
    print("=" * 50)

    all_servers = []

    # VPNGate
    vpngate = fetch_vpngate()
    all_servers.extend(vpngate)

    if not all_servers:
        print("❌ ما لقينا أي سيرفر")
        return

    # فلتر واختبر
    final = filter_and_sort(all_servers)

    if not final:
        print("❌ كل السيرفرات فشلت في الاختبار")
        return

    # ارفع
    upload_to_supabase(final)
    print("=" * 50)
    print(f"✅ خلصنا — {len(final)} سيرفر جاهز في Supabase")
    print("=" * 50)


if __name__ == "__main__":
    main()
