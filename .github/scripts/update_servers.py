"""
update_servers.py
يجيب سيرفرات VPN من VPNGate، يفلترهم، يحفظهم في Supabase.
"""

import os
import csv
import base64
import requests
from io import StringIO
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_PING_MS     = 300
MAX_SERVERS     = 80
MAX_PER_COUNTRY = 3


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

                    # استخرج الـ port من الكونفيغ
                    port = 1194
                    for line in config.splitlines():
                        if line.startswith("remote "):
                            parts = line.split()
                            if len(parts) >= 3 and parts[2].isdigit():
                                port = int(parts[2])
                            break

                    servers.append({
                        "country_name":     country_name,
                        "country_code":     country_code,
                        "ip":               row[1],
                        "ping":             ping,
                        "ovpn_config":      config,
                        "num_sessions":     sessions,
                        "protocol":         "openvpn",
                        "is_active":        True,
                        "source":           "vpngate",
                        "is_hard_to_block": port == 443,
                    })
                    if len(servers) >= 200:
                        break
                except Exception:
                    continue

            if servers:
                p443 = sum(1 for s in servers if s["is_hard_to_block"])
                print(f"[VPNGate] جبنا {len(servers)} سيرفر ({p443} على port 443)")
                return servers

        except Exception as e:
            print(f"[VPNGate] خطأ: {e}")

    return []


def filter_and_sort(servers: list[dict]) -> list[dict]:
    print(f"[Filter] نفلتر {len(servers)} سيرفر...")

    seen_ips = set()
    filtered = []
    for s in servers:
        if s["ip"] in seen_ips or not s.get("ovpn_config"):
            continue
        seen_ips.add(s["ip"])
        filtered.append(s)

    print(f"[Filter] {len(filtered)} سيرفر بعد إزالة المكررين")

    def score(s):
        port_bonus = -100 if s["is_hard_to_block"] else 0
        congestion = min(s.get("num_sessions", 0) // 10, 200)
        return s["ping"] + congestion + port_bonus

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

    p443 = sum(1 for s in result if s["is_hard_to_block"])
    print(f"[Filter] {len(result)} سيرفر جاهز ({p443} على port 443)")
    return result


def upload_to_supabase(servers: list[dict]):
    client = create_client(SUPABASE_URL, SUPABASE_KEY)

    client.table("servers").delete().neq("ip", "").execute()
    print("[Supabase] حذفنا السيرفرات القديمة")

    for s in servers:
        s["is_active"] = True

    batch_size = 20
    uploaded = 0
    for i in range(0, len(servers), batch_size):
        batch = servers[i:i + batch_size]
        client.table("servers").insert(batch).execute()
        uploaded += len(batch)
        print(f"[Supabase] رفعنا {uploaded}/{len(servers)}")

    print(f"[Supabase] ✅ اكتمل — {len(servers)} سيرفر")


def main():
    print("=" * 50)
    print("بدأ تحديث السيرفرات")
    print("=" * 50)

    servers = fetch_vpngate()
    if not servers:
        print("❌ ما لقينا أي سيرفر")
        return

    final = filter_and_sort(servers)
    if not final:
        print("❌ ما في سيرفرات بعد الفلتر")
        return

    upload_to_supabase(final)

    p443 = sum(1 for s in final if s.get("is_hard_to_block"))
    print("=" * 50)
    print(f"✅ خلصنا — {len(final)} سيرفر ({p443} منهم port 443)")
    print("=" * 50)


if __name__ == "__main__":
    main()
