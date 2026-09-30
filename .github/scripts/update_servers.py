"""
update_servers.py — يجيب سيرفرات V2Ray من 4 مصادر ويحفظهم في Supabase
مع معرفة الدولة من الـ IP تلقائياً
"""

import os
import base64
import json
import requests
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_SERVERS = 120

# ─── المصادر ──────────────────────────────────────────────────
SOURCE_1_URLS = [
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/vless.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/vmess.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/trojan.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/shadowsocks.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt",
]
SOURCE_2_URLS = [
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/reality.txt",
]
SOURCE_3_URLS = [
    "https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub1.txt",
    "https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub2.txt",
]
SOURCE_4_URLS = [
    "https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/mix",
    "https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/hysteria2",
]

# ─── IP Cache ─────────────────────────────────────────────────
_ip_cache = {}

def lookup_country(ip: str) -> tuple[str, str]:
    """يجيب اسم الدولة ورمزها من الـ IP"""
    if ip in _ip_cache:
        return _ip_cache[ip]
    try:
        r = requests.get(
            f"http://ip-api.com/json/{ip}?fields=country,countryCode",
            timeout=5
        )
        if r.status_code == 200:
            data = r.json()
            country = data.get("country", "Unknown")
            code    = data.get("countryCode", "XX")
            _ip_cache[ip] = (country, code)
            return country, code
    except Exception:
        pass
    return "Unknown", "XX"

# ─── Helpers ──────────────────────────────────────────────────
def fetch_text(url: str) -> str:
    try:
        r = requests.get(url, timeout=20, headers={"User-Agent": "Mozilla/5.0"})
        if r.status_code == 200:
            return r.text
    except Exception as e:
        print(f"  [خطأ] {url}: {e}")
    return ""

def decode_if_base64(text: str) -> str:
    try:
        decoded = base64.b64decode(text + "==").decode("utf-8")
        if any(p in decoded for p in ["vless://","vmess://","trojan://","ss://","hysteria2://","hy2://"]):
            return decoded
    except Exception:
        pass
    return text

def parse_configs(raw: str) -> list:
    text = decode_if_base64(raw.strip())
    prefixes = ("vless://","vmess://","trojan://","ss://","hysteria2://","hy2://")
    return [l.strip() for l in text.splitlines() if any(l.strip().startswith(p) for p in prefixes)]

def detect_protocol(config: str) -> str:
    if config.startswith("vless://"):
        return "vless-reality" if ("reality" in config.lower() or "xtls" in config.lower()) else "vless"
    if config.startswith("vmess://"):   return "vmess"
    if config.startswith("trojan://"):  return "trojan"
    if config.startswith("ss://"):      return "shadowsocks"
    if config.startswith("hysteria2://") or config.startswith("hy2://"): return "hysteria2"
    return "unknown"

def is_hard_to_block(protocol: str) -> bool:
    return protocol in ("hysteria2", "vless-reality", "vless")

def extract_host(config: str) -> str:
    try:
        after = config.split("://", 1)[1]
        if config.startswith("vmess://"):
            data = json.loads(base64.b64decode(after + "==").decode("utf-8"))
            return data.get("add", "")
        at_part = after.split("@")[-1] if "@" in after else after
        return at_part.split(":")[0].split("?")[0].split("#")[0]
    except Exception:
        return ""

def config_to_row(config: str, source_name: str) -> dict | None:
    protocol = detect_protocol(config)
    if protocol == "unknown":
        return None
    host = extract_host(config)
    if not host:
        return None

    # جيب الدولة من الـ IP
    country_name, country_code = lookup_country(host)

    return {
        "ip":               host,
        "country_name":     country_name,
        "country_code":     country_code,
        "ping":             80 if is_hard_to_block(protocol) else 180,
        "ovpn_config":      config,
        "num_sessions":     0,
        "protocol":         protocol,
        "source":           source_name,
        "is_active":        True,
        "is_hard_to_block": is_hard_to_block(protocol),
    }

# ─── المصادر ──────────────────────────────────────────────────
def fetch_source(urls: list, source_name: str, filter_protocols: list = None, limit: int = 40) -> list:
    rows = []
    for url in urls:
        raw = fetch_text(url)
        if not raw:
            continue
        configs = parse_configs(raw)
        if filter_protocols:
            configs = [c for c in configs if detect_protocol(c) in filter_protocols]
        configs = configs[:limit]
        print(f"  ← {len(configs)} كونفيغ من {url.split('/')[-1]}")
        for c in configs:
            row = config_to_row(c, source_name)
            if row:
                rows.append(row)
    return rows

# ─── Merge ────────────────────────────────────────────────────
def merge_and_filter(all_rows: list) -> list:
    seen = set()
    unique = []
    for row in all_rows:
        key = f"{row['ip']}_{row['protocol']}"
        if key not in seen:
            seen.add(key)
            unique.append(row)

    unique.sort(key=lambda r: (0 if r.get("is_hard_to_block") else 1, r["ping"]))
    return unique[:MAX_SERVERS]

# ─── Upload ───────────────────────────────────────────────────
def upload_to_supabase(servers: list):
    client = create_client(SUPABASE_URL, SUPABASE_KEY)
    client.table("servers").delete().neq("ip", "").execute()
    print(f"\n[Supabase] حذفنا القديمة، نرفع {len(servers)} سيرفر...")
    for i in range(0, len(servers), 20):
        client.table("servers").insert(servers[i:i+20]).execute()
        print(f"  رفعنا {min(i+20, len(servers))}/{len(servers)}")
    print(f"[Supabase] ✅ اكتمل")

# ─── Main ─────────────────────────────────────────────────────
def main():
    print("=" * 50)
    print("بدأ تحديث السيرفرات — 4 مصادر")
    print("=" * 50)

    all_rows = []

    print("\n[المصدر 1] 0xRadikal — كل البروتوكولات")
    all_rows += fetch_source(SOURCE_1_URLS, "source_1_all")

    print("\n[المصدر 2] 0xRadikal — Hysteria2 + REALITY فقط")
    all_rows += fetch_source(SOURCE_2_URLS, "source_2_hard", ["hysteria2", "vless-reality"])

    print("\n[المصدر 3] barry-far — Cloudflare CDN")
    all_rows += fetch_source(SOURCE_3_URLS, "source_3_cloudflare", ["vless", "trojan"], limit=30)

    print("\n[المصدر 4] morpheusadam — مختبر فعلياً")
    all_rows += fetch_source(SOURCE_4_URLS, "source_4_tested")

    if not all_rows:
        print("❌ ما لقينا أي سيرفر")
        return

    final = merge_and_filter(all_rows)
    print(f"\n[دمج] النهائي: {len(final)} سيرفر")

    # إحصاء الدول
    from collections import Counter
    countries = Counter(r["country_name"] for r in final if r["country_name"] != "Unknown")
    print("أكثر الدول:")
    for country, count in countries.most_common(10):
        print(f"  {country}: {count}")

    upload_to_supabase(final)

    print("=" * 50)
    print(f"✅ خلصنا — {len(final)} سيرفر بـ Supabase")
    print("=" * 50)

if __name__ == "__main__":
    main()
