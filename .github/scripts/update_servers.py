"""
update_servers.py
يجيب سيرفرات VPN من VPNGate، يفلترهم، يحفظهم في Supabase.
"""

import os 
import csv
import base64
import time
import requests
from io import StringIO
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_PING_MS     = 300
MAX_SERVERS     = 80
MAX_PER_COUNTRY = 3


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
                    servers.append({
                        "country_name": country_name,
                        "country_code": country_code,
                        "ip":           row[1],
                        "ping":         ping,
                        "ovpn_config":  config,
                        "num_sessions": sessions,
                        "protocol":     "openvpn",
                        # ✅ إصلاح ١: is_active دائماً True، ما نعتمد على TCP test
                        "is_active":    True,
                        # ✅ إصلاح ٢: source = supabase
                        "source":       "supabase",
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
# فلتر وترتيب — نعتمد على ping VPNGate مباشرة
# ──────────────────────────────────────────────
def filter_and_sort(servers: list[dict]) -> list[dict]:
    print(f"[Filter] نفلتر {len(servers)} سيرفر...")

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

    print(f"[Filter] {len(filtered)} سيرفر بعد إزالة المكررين")

    # ✅ إصلاح ٣: رتّب الأقوى أولاً (ping + ازدحام)
    def score(s):
        congestion = min(s.get("num_sessions", 0) // 10, 200)
        return s["ping"] + congestion

    filtered.sort(key=score)

    # حدّ لكل دولة — أفضل 3 لكل دولة
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

    print(f"[Filter] {len(result)} سيرفر جاهز للرفع")
    return result


# ──────────────────────────────────────────────
# ارفع على Supabase
# ──────────────────────────────────────────────
def upload_to_supabase(servers: list[dict]):
    client = create_client(SUPABASE_URL, SUPABASE_KEY)

    # احذف كل السيرفرات القديمة نظيف
    client.table("servers").delete().neq("ip", "").execute()
    print("[Supabase] حذفنا السيرفرات القديمة")

    # تأكد كل سيرفر عنده is_active = True
    for s in servers:
        s["is_active"] = True

    # ارفع الجديدة كـ insert نظيف
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
CLOUDFLARE_WORKER = "https://vpn.akramfaeq523.workers.dev"

def fetch_cloudflare() -> list[dict]:
    """يجيب كونفيغات VLESS من Cloudflare Worker"""
    try:
        r = requests.get(f"{CLOUDFLARE_WORKER}/sub", timeout=10)
        if r.status_code != 200:
            print(f"[Cloudflare] فشل: {r.status_code}")
            return []

        decoded = base64.b64decode(r.text + "==").decode("utf-8")
        configs = [l.strip() for l in decoded.splitlines()
                   if l.strip().startswith(("vless://", "vmess://", "trojan://"))]

        servers = []
        for config in configs:
            # استخرج الـ host من الكونفيغ
            try:
                after = config.split("://")[1]
                host = after.split("@")[1].split(":")[0] if "@" in after else after.split(":")[0]
                name = config.split("#")[1] if "#" in config else "Cloudflare"
            except Exception:
                continue

            servers.append({
                "country_name": "Cloudflare",
                "country_code": "CF",
                "ip":           host,
                "ping":         50,  # Cloudflare سريع دايماً
                "ovpn_config":  config,
                "num_sessions": 0,
                "protocol":     "vless",
                "is_active":    True,
                "source":       "cloudflare",
            })

        print(f"[Cloudflare] جبنا {len(servers)} كونفيغ")
        return servers
    except Exception as e:
        print(f"[Cloudflare] خطأ: {e}")
        return []


def main():
    print("=" * 50)
    print("بدأ تحديث السيرفرات")
    print("=" * 50)

    # المصدر 1 — VPN Gate (OpenVPN)
    servers = fetch_vpngate()

    # المصدر 2 — Cloudflare Worker (VLESS)
    cf_servers = fetch_cloudflare()
    servers += cf_servers

    if not servers:
        print("❌ ما لقينا أي سيرفر")
        return

    # OpenVPN بس يمر بالفلتر، Cloudflare يضاف مباشرة
    openvpn = [s for s in servers if s.get("protocol") == "openvpn"]
    cloudflare = [s for s in servers if s.get("protocol") != "openvpn"]

    final = filter_and_sort(openvpn) + cloudflare

    if not final:
        print("❌ ما في سيرفرات بعد الفلتر")
        return

    upload_to_supabase(final)

    print("=" * 50)
    print(f"✅ خلصنا — {len(final)} سيرفر جاهز في Supabase")
    print(f"   OpenVPN: {len(openvpn)} | Cloudflare: {len(cloudflare)}")
    print("=" * 50)


if __name__ == "__main__":
    main()
