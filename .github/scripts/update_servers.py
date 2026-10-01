"""
update_servers.py
يجيب سيرفرات VPN من VPNGate، يختبرهم، يحفظهم في Supabase.
"""

import os
import csv
import base64
import socket
import concurrent.futures
import requests
from io import StringIO
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_PING_MS     = 300
MAX_SERVERS     = 80
MAX_PER_COUNTRY = 3
TCP_TIMEOUT     = 5    # ثواني لكل اختبار
MAX_WORKERS     = 30   # اختبارات متوازية


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

                    # استخرج IP والـ port من الكونفيغ
                    ip = row[1]
                    port = 1194
                    for line in config.splitlines():
                        if line.startswith("remote "):
                            parts = line.split()
                            if len(parts) >= 3 and parts[2].isdigit():
                                port = int(parts[2])
                            break

                    servers.append({
                        "country_name": country_name,
                        "country_code": country_code,
                        "ip":           ip,
                        "port":         port,
                        "ping":         ping,
                        "ovpn_config":  config,
                        "num_sessions": sessions,
                        "protocol":     "openvpn",
                        "is_active":    True,
                        "source":       "vpngate",
                    })
                    if len(servers) >= 300:
                        break
                except Exception:
                    continue

            if servers:
                print(f"[VPNGate] جبنا {len(servers)} سيرفر")
                return servers

        except Exception as e:
            print(f"[VPNGate] خطأ: {type(e).__name__}: {e}")

    return []


# ──────────────────────────────────────────────
# TCP test — يتحقق السيرفر حي
# ──────────────────────────────────────────────
def tcp_test(server: dict) -> bool:
    ip   = server["ip"]
    port = server.get("port", 1194)
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(TCP_TIMEOUT)
        result = sock.connect_ex((ip, port))
        sock.close()
        return result == 0
    except Exception:
        return False


def test_all(servers: list[dict]) -> list[dict]:
    print(f"[Test] نختبر {len(servers)} سيرفر بـ {MAX_WORKERS} worker متوازي...")
    alive = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(tcp_test, s): s for s in servers}
        for future in concurrent.futures.as_completed(futures):
            s = futures[future]
            if future.result():
                alive.append(s)
    print(f"[Test] {len(alive)} سيرفر حي من أصل {len(servers)}")
    return alive


# ──────────────────────────────────────────────
# فلتر وترتيب
# ──────────────────────────────────────────────
def filter_and_sort(servers: list[dict]) -> list[dict]:
    seen_ips = set()
    filtered = []
    for s in servers:
        ip = s["ip"]
        if ip in seen_ips:
            continue
        seen_ips.add(ip)
        if not s.get("ovpn_config"):
            continue
        filtered.append(s)

    def score(s):
        congestion = min(s.get("num_sessions", 0) // 10, 200)
        return s["ping"] + congestion

    filtered.sort(key=score)

    country_count: dict[str, int] = {}
    result = []
    for s in filtered:
        cc = s["country_code"]
        count = country_count.get(cc, 0)
        if count < MAX_PER_COUNTRY:
            result.append(s)
            country_count[cc] = count + 1
        if len(result) >= MAX_SERVERS:
            break

    print(f"[Filter] {len(result)} سيرفر بعد الفلتر")
    return result


# ──────────────────────────────────────────────
# ارفع على Supabase
# ──────────────────────────────────────────────
def upload_to_supabase(servers: list[dict]):
    client = create_client(SUPABASE_URL, SUPABASE_KEY)

    client.table("servers").delete().neq("ip", "").execute()
    print("[Supabase] حذفنا السيرفرات القديمة")

    for s in servers:
        s["is_active"] = True
        s.pop("port", None)  # port مو موجود بالجدول

    batch_size = 20
    uploaded = 0
    for i in range(0, len(servers), batch_size):
        batch = servers[i:i + batch_size]
        client.table("servers").insert(batch).execute()
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

    # ① جيب السيرفرات
    servers = fetch_vpngate()
    if not servers:
        print("❌ ما لقينا أي سيرفر من VPNGate")
        return

    # ② فلتر المكررين ورتّب
    filtered = filter_and_sort(servers)

    # ③ اختبر الحيين فقط
    alive = test_all(filtered)
    if not alive:
        print("❌ كل السيرفرات ميتة!")
        return

    # ④ ارفع
    upload_to_supabase(alive)

    print("=" * 50)
    print(f"✅ خلصنا — {len(alive)} سيرفر شغال جاهز في Supabase")
    print("=" * 50)


if __name__ == "__main__":
    main()
