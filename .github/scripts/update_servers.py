"""
update_servers.py — V2Ray Edition
يجيب configs من مصادر GitHub المجانية، يفلترهم، يحفظهم في Supabase.
يشتغل بإيران والدول المحجوبة لأن البروتوكول V2Ray/Xray مو OpenVPN.
"""

import os
import re
import json
import base64
import random
import urllib.parse
import requests
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_SERVERS     = 80
MAX_PER_COUNTRY = 6  # أكثر من OpenVPN لأن السيرفرات تموت أسرع

# ─── مصادر V2Ray المجانية — تتحدث كل 5-15 دقيقة ─────────────
SOURCES = [
    # ① 0xRadikal — مفلترة ومتحقق منها (أفضل مصدر)
    {
        "url":      "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt",
        "name":     "0xRadikal-top100",
        "encoded":  False,
        "priority": 1,
    },
    {
        "url":      "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt",
        "name":     "0xRadikal-verified",
        "encoded":  False,
        "priority": 1,
    },
    {
        "url":      "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/fast/configs.txt",
        "name":     "0xRadikal-fast",
        "encoded":  False,
        "priority": 2,
    },
    # ② Epodonios — يتحدث كل 5 دقائق
    {
        "url":      "https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub1.txt",
        "name":     "Epodonios-1",
        "encoded":  True,
        "priority": 2,
    },
    {
        "url":      "https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub2.txt",
        "name":     "Epodonios-2",
        "encoded":  True,
        "priority": 2,
    },
    # ③ احتياطي إضافي
    {
        "url":      "https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub3.txt",
        "name":     "Epodonios-3",
        "encoded":  True,
        "priority": 3,
    },
]

VALID_PROTOCOLS = ("vless://", "vmess://", "trojan://", "ss://")


# ─── جلب configs من مصدر واحد ────────────────────────────────
def fetch_source(source: dict) -> list[str]:
    try:
        r = requests.get(source["url"], timeout=15,
                         headers={"User-Agent": "Mozilla/5.0"})
        if r.status_code != 200:
            print(f"  ⚠️  {source['name']}: HTTP {r.status_code}")
            return []

        text = r.text.strip()

        # لو base64
        if source["encoded"] or not any(p in text for p in VALID_PROTOCOLS):
            try:
                text = base64.b64decode(text + "==").decode("utf-8", errors="ignore")
            except Exception:
                pass

        lines = [l.strip() for l in text.splitlines()]
        configs = [l for l in lines if l.startswith(VALID_PROTOCOLS)]
        print(f"  ✅  {source['name']}: {len(configs)} configs")
        return configs

    except Exception as e:
        print(f"  ⚠️  {source['name']}: {e}")
        return []


# ─── استخرج معلومات الـ config ───────────────────────────────
def parse_config(config: str) -> dict | None:
    try:
        protocol = config.split("://")[0].lower()

        if protocol == "vmess":
            b64 = config[8:]
            b64 += "=" * (-len(b64) % 4)
            info = json.loads(base64.b64decode(b64).decode("utf-8", errors="ignore"))
            ip      = info.get("add", "")
            port    = int(info.get("port", 443))
            remark  = info.get("ps", "")
            tls     = info.get("tls", "") == "tls"
            network = info.get("net", "tcp")

        elif protocol in ("vless", "trojan"):
            parsed  = urllib.parse.urlparse(config)
            ip      = parsed.hostname or ""
            port    = parsed.port or 443
            remark  = urllib.parse.unquote(parsed.fragment or "")
            params  = urllib.parse.parse_qs(parsed.query)
            tls     = params.get("security", [""])[0] in ("tls", "reality")
            network = params.get("type", ["tcp"])[0]

        elif protocol == "ss":
            parsed  = urllib.parse.urlparse(config)
            ip      = parsed.hostname or ""
            port    = parsed.port or 443
            remark  = urllib.parse.unquote(parsed.fragment or "")
            tls     = port == 443
            network = "tcp"

        else:
            return None

        if not ip or len(ip) < 3:
            return None

        # is_hard_to_block = TLS على port 443 أو Reality
        is_hard = tls and (port == 443 or "reality" in config.lower())

        return {
            "ip":               ip,
            "port":             port,
            "protocol":         protocol,
            "config":           config,
            "remark":           remark,
            "is_hard_to_block": is_hard,
            "network":          network,
        }

    except Exception:
        return None


# ─── خمّن الدولة من الـ remark ───────────────────────────────
COUNTRY_MAP = {
    "US": ["US", "UNITED STATES", "AMERICA", "USA"],
    "DE": ["DE", "GERMANY", "DEUTSCH", "GERMAN"],
    "NL": ["NL", "NETHERLANDS", "HOLLAND", "DUTCH"],
    "FR": ["FR", "FRANCE", "FRENCH"],
    "GB": ["GB", "UK", "BRITAIN", "ENGLAND"],
    "JP": ["JP", "JAPAN"],
    "SG": ["SG", "SINGAPORE"],
    "TR": ["TR", "TURKEY", "TURKISH"],
    "CA": ["CA", "CANADA"],
    "AU": ["AU", "AUSTRALIA"],
    "FI": ["FI", "FINLAND"],
    "SE": ["SE", "SWEDEN"],
    "NO": ["NO", "NORWAY"],
    "CH": ["CH", "SWITZERLAND"],
    "AT": ["AT", "AUSTRIA"],
    "PL": ["PL", "POLAND"],
    "HU": ["HU", "HUNGARY"],
    "RO": ["RO", "ROMANIA"],
    "KR": ["KR", "KOREA", "KOREAN"],
    "HK": ["HK", "HONG KONG"],
    "TW": ["TW", "TAIWAN"],
    "IN": ["IN", "INDIA", "INDIAN"],
    "BR": ["BR", "BRAZIL"],
    "AR": ["AR", "ARGENTINA"],
    "MX": ["MX", "MEXICO"],
    "ZA": ["ZA", "SOUTH AFRICA"],
    "NG": ["NG", "NIGERIA"],
}

def guess_country(remark: str) -> tuple[str, str]:
    r = remark.upper()
    # ابحث عن كود دولة بين brackets مثل [US] أو (DE)
    m = re.search(r'[\[\(]([A-Z]{2})[\]\)]', r)
    if m:
        code = m.group(1)
        for full_name, keywords in COUNTRY_MAP.items():
            if code == full_name:
                return full_name, full_name
    # ابحث في النص
    for code, keywords in COUNTRY_MAP.items():
        if any(k in r for k in keywords):
            return code, code
    return "UN", "Unknown"


# ─── الفلترة والترتيب ─────────────────────────────────────────
def filter_and_sort(raw_configs: list[str]) -> list[dict]:
    seen_ips = set()
    parsed   = []

    for cfg in raw_configs:
        info = parse_config(cfg)
        if not info or info["ip"] in seen_ips:
            continue
        seen_ips.add(info["ip"])

        code, name = guess_country(info["remark"])
        ping = random.randint(40, 180)  # ping مؤقت، التطبيق يقيسه لاحقاً

        parsed.append({
            "country_name":     name if name != "Unknown" else info["remark"][:30] or "Unknown",
            "country_code":     code,
            "ip":               info["ip"],
            "ping":             ping,
            "ovpn_config":      info["config"],
            "protocol":         info["protocol"],
            "num_sessions":     0,
            "is_active":        True,
            "is_hard_to_block": info["is_hard_to_block"],
            "source":           "github_v2ray",
        })

    # الأولوية: is_hard_to_block أولاً (يشتغل بإيران)
    parsed.sort(key=lambda s: (0 if s["is_hard_to_block"] else 1, s["ping"]))

    # حد لكل دولة
    country_count: dict[str, int] = {}
    result = []
    for s in parsed:
        cc    = s["country_code"]
        count = country_count.get(cc, 0)
        if count < MAX_PER_COUNTRY:
            result.append(s)
            country_count[cc] = count + 1
        if len(result) >= MAX_SERVERS:
            break

    hard = sum(1 for s in result if s["is_hard_to_block"])
    print(f"\n[Filter] {len(result)} سيرفر ({hard} منهم TLS/Reality — يشتغل بإيران)")
    return result


# ─── رفع لـ Supabase ──────────────────────────────────────────
def upload_to_supabase(servers: list[dict]):
    client = create_client(SUPABASE_URL, SUPABASE_KEY)

    # احذف القديم
    client.table("servers").delete().neq("ip", "").execute()
    print("\n[Supabase] حذفنا السيرفرات القديمة")

    # ارفع الجديد
    batch_size = 20
    uploaded   = 0
    for i in range(0, len(servers), batch_size):
        batch = servers[i:i + batch_size]
        client.table("servers").insert(batch).execute()
        uploaded += len(batch)
        print(f"[Supabase] رفعنا {uploaded}/{len(servers)}")

    print(f"[Supabase] ✅ اكتمل — {len(servers)} سيرفر")


# ─── Main ─────────────────────────────────────────────────────
def main():
    print("=" * 55)
    print("🚀 بدأ تحديث السيرفرات — V2Ray Edition (يشتغل بإيران)")
    print("=" * 55)

    all_configs: list[str] = []

    # رتّب المصادر حسب الأولوية
    for source in sorted(SOURCES, key=lambda s: s["priority"]):
        configs = fetch_source(source)
        all_configs.extend(configs)
        # لو عندنا كفاية من priority 1 نوقف
        if source["priority"] == 1 and len(all_configs) >= 150:
            print(f"\n✅ كفاية configs ({len(all_configs)}) من المصادر عالية الأولوية")
            break

    print(f"\n[Total] جبنا {len(all_configs)} config قبل الفلتر")

    if not all_configs:
        print("❌ ما لقينا أي config")
        return

    final = filter_and_sort(all_configs)

    if not final:
        print("❌ ما في سيرفرات بعد الفلتر")
        return

    upload_to_supabase(final)

    hard = sum(1 for s in final if s.get("is_hard_to_block"))
    print("\n" + "=" * 55)
    print(f"✅ خلصنا — {len(final)} سيرفر")
    print(f"   🔒 {hard} منهم TLS/Reality (يشتغل بإيران)")
    print(f"   🌐 {len(final) - hard} منهم عادي")
    print("=" * 55)


if __name__ == "__main__":
    main()
