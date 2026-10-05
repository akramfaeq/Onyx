"""
update_servers.py — V2Ray Edition with TCP verification
نفس المنهجية الصحيحة:
① جلب configs من مصادر متعددة
② parse صحيح مع reserved من client_id (وليس id)
③ TCP test متوازي
④ رفع Supabase
"""

import os
import re
import json
import base64
import socket
import random
import urllib.parse
import concurrent.futures
import requests
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_SERVERS     = 60
MAX_PER_COUNTRY = 5
TCP_TIMEOUT     = 4
MAX_WORKERS     = 40

SOURCES = [
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
    {
        "url":      "https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/Sub3.txt",
        "name":     "Epodonios-3",
        "encoded":  True,
        "priority": 3,
    },
    # مصادر إضافية موثوقة
    {
        "url":      "https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/main/mci/sub_1.txt",
        "name":     "mahsanet-mci-1",
        "encoded":  True,
        "priority": 2,
    },
    {
        "url":      "https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge_base64.txt",
        "name":     "V2RayAggregator",
        "encoded":  True,
        "priority": 3,
    },
]

VALID_PROTOCOLS = ("vless://", "vmess://", "trojan://", "ss://")


# ─── جلب configs ──────────────────────────────────────────────
def fetch_source(source: dict) -> list[str]:
    try:
        r = requests.get(
            source["url"],
            timeout=15,
            headers={"User-Agent": "Hiddify/2.0 (compatible; sing-box)"},
        )
        if r.status_code != 200:
            print(f"  ⚠️  {source['name']}: HTTP {r.status_code}")
            return []

        text = r.text.strip()
        if source["encoded"] or not any(p in text for p in VALID_PROTOCOLS):
            try:
                padded = text + "==" 
                text   = base64.b64decode(padded).decode("utf-8", errors="ignore")
            except Exception:
                pass

        lines   = [l.strip() for l in text.splitlines()]
        configs = [l for l in lines if l.startswith(VALID_PROTOCOLS)]
        print(f"  ✅  {source['name']}: {len(configs)} configs")
        return configs
    except Exception as e:
        print(f"  ⚠️  {source['name']}: {e}")
        return []


# ─── parse config ─────────────────────────────────────────────
def parse_config(config: str) -> dict | None:
    try:
        protocol = config.split("://")[0].lower()

        if protocol == "vmess":
            b64  = config[8:]
            b64 += "=" * (-len(b64) % 4)
            info    = json.loads(base64.b64decode(b64).decode("utf-8", errors="ignore"))
            ip      = info.get("add", "")
            port    = int(info.get("port", 443))
            remark  = info.get("ps", "")
            tls     = info.get("tls", "") == "tls"

        elif protocol in ("vless", "trojan"):
            parsed  = urllib.parse.urlparse(config)
            ip      = parsed.hostname or ""
            port    = parsed.port or 443
            remark  = urllib.parse.unquote(parsed.fragment or "")
            params  = urllib.parse.parse_qs(parsed.query)
            tls     = params.get("security", [""])[0] in ("tls", "reality")

        elif protocol == "ss":
            parsed  = urllib.parse.urlparse(config)
            ip      = parsed.hostname or ""
            port    = parsed.port or 443
            remark  = urllib.parse.unquote(parsed.fragment or "")
            tls     = port == 443

        else:
            return None

        if not ip or len(ip) < 3:
            return None

        is_hard = tls and (port == 443 or "reality" in config.lower())

        return {
            "ip":               ip,
            "port":             port,
            "protocol":         protocol,
            "config":           config,
            "remark":           remark,
            "is_hard_to_block": is_hard,
        }
    except Exception:
        return None


# ─── TCP test ─────────────────────────────────────────────────
def tcp_ping(ip: str, port: int, timeout: float = TCP_TIMEOUT) -> int:
    import time
    try:
        start  = time.time()
        sock   = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((ip, port))
        sock.close()
        if result == 0:
            return int((time.time() - start) * 1000)
        return 9999
    except Exception:
        return 9999


def test_server(info: dict) -> dict | None:
    ping = tcp_ping(info["ip"], info["port"])
    if ping >= 9999:
        return None
    info["ping"] = ping
    return info


# ─── country map ──────────────────────────────────────────────
COUNTRY_MAP = {
    "US": ["US", "UNITED STATES", "AMERICA", "USA"],
    "DE": ["DE", "GERMANY", "DEUTSCH"],
    "NL": ["NL", "NETHERLANDS", "HOLLAND"],
    "FR": ["FR", "FRANCE"],
    "GB": ["GB", "UK", "BRITAIN", "ENGLAND"],
    "JP": ["JP", "JAPAN"],
    "SG": ["SG", "SINGAPORE"],
    "TR": ["TR", "TURKEY"],
    "CA": ["CA", "CANADA"],
    "AU": ["AU", "AUSTRALIA"],
    "FI": ["FI", "FINLAND"],
    "SE": ["SE", "SWEDEN"],
    "NO": ["NO", "NORWAY"],
    "CH": ["CH", "SWITZERLAND"],
    "PL": ["PL", "POLAND"],
    "KR": ["KR", "KOREA"],
    "HK": ["HK", "HONG KONG"],
    "IN": ["IN", "INDIA"],
    "BR": ["BR", "BRAZIL"],
    "IQ": ["IQ", "IRAQ"],
    "IR": ["IR", "IRAN"],
}

def guess_country(remark: str) -> tuple[str, str]:
    r = remark.upper()
    m = re.search(r"[\[\(]([A-Z]{2})[\]\)]", r)
    if m:
        code = m.group(1)
        if code in COUNTRY_MAP:
            return code, code
    for code, keywords in COUNTRY_MAP.items():
        if any(k in r for k in keywords):
            return code, code
    return "UN", "Unknown"


# ─── main ─────────────────────────────────────────────────────
def main():
    print("=" * 55)
    print("🚀 V2Ray — مع اختبار TCP حقيقي (Hiddify style)")
    print("=" * 55)

    # ① جلب
    all_configs: list[str] = []
    for source in sorted(SOURCES, key=lambda s: s["priority"]):
        configs = fetch_source(source)
        all_configs.extend(configs)
        if source["priority"] == 1 and len(all_configs) >= 150:
            break

    print(f"\n[Total] {len(all_configs)} config قبل الفلتر")
    if not all_configs:
        print("❌ ما لقينا configs")
        return

    # ② parse + dedup بالـ IP
    parsed_list = []
    seen_ips    = set()
    for cfg in all_configs:
        info = parse_config(cfg)
        if not info or info["ip"] in seen_ips:
            continue
        seen_ips.add(info["ip"])
        parsed_list.append(info)

    print(f"[Parse] {len(parsed_list)} سيرفر فريد")

    # ③ TCP test متوازي
    print(f"\n[TCP] نختبر {len(parsed_list)} سيرفر بـ {MAX_WORKERS} thread...")
    alive = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(test_server, info): info for info in parsed_list}
        done    = 0
        for future in concurrent.futures.as_completed(futures):
            done += 1
            result = future.result()
            if result:
                alive.append(result)
            if done % 50 == 0:
                print(f"  ... {done}/{len(parsed_list)} — شغال: {len(alive)}")

    print(f"\n[TCP] ✅ {len(alive)} سيرفر من {len(parsed_list)}")
    if not alive:
        print("❌ كل السيرفرات ماتت!")
        return

    # ④ ترتيب: TLS/Reality أولاً ثم ping
    alive.sort(key=lambda s: (0 if s["is_hard_to_block"] else 1, s["ping"]))

    # ⑤ حد لكل دولة
    country_count: dict[str, int] = {}
    final = []
    for s in alive:
        code, name = guess_country(s["remark"])
        count = country_count.get(code, 0)
        if count >= MAX_PER_COUNTRY:
            continue
        country_count[code] = count + 1

        final.append({
            "country_name":     name if name != "Unknown" else s["remark"][:30] or "Unknown",
            "country_code":     code,
            "ip":               s["ip"],
            "ping":             s["ping"],
            "ovpn_config":      s["config"],
            "protocol":         s["protocol"],
            "num_sessions":     0,
            "is_active":        True,
            "is_hard_to_block": s["is_hard_to_block"],
            "source":           "github_v2ray",
        })

        if len(final) >= MAX_SERVERS:
            break

    hard = sum(1 for s in final if s["is_hard_to_block"])
    print(f"[Filter] {len(final)} سيرفر نهائي ({hard} TLS/Reality)")

    # ⑥ Supabase
    client = create_client(SUPABASE_URL, SUPABASE_KEY)
    client.table("servers").delete().neq("ip", "").execute()
    print("\n[Supabase] حذفنا القديم")

    uploaded = 0
    for i in range(0, len(final), 20):
        batch     = final[i:i + 20]
        client.table("servers").insert(batch).execute()
        uploaded += len(batch)
        print(f"[Supabase] {uploaded}/{len(final)}")

    avg = sum(s["ping"] for s in final) // len(final) if final else 0
    print("\n" + "=" * 55)
    print(f"✅ {len(final)} سيرفر مختبر وشغال")
    print(f"   🔒 {hard} TLS/Reality | 🌐 {len(final)-hard} عادي")
    print(f"   ⚡ متوسط ping: {avg}ms")
    print("=" * 55)


if __name__ == "__main__":
    main()
