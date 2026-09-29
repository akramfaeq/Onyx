"""
update_servers.py
يجيب سيرفرات V2Ray من 4 مصادر، يفلترهم، يحفظهم في Supabase.

المصادر:
  1. 0xRadikal/Free-v2ray-Configs  — كل البروتوكولات
  2. 0xRadikal مفلتر              — Hysteria2 + REALITY فقط
  3. Cloudflare Workers            — VLESS+WS صعب الحجب
  4. morpheusadam/v2ray-config     — مختبر فعلياً + يشتغل حتى لو GitHub محجوب
"""

import os
import base64
import requests
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

MAX_SERVERS     = 120
MAX_PER_COUNTRY = 3

# ─────────────────────────────────────────────────────────────
# روابط المصادر
# ─────────────────────────────────────────────────────────────

# المصدر 1 — كل البروتوكولات
SOURCE_1_URLS = [
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/vless.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/vmess.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/trojan.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/shadowsocks.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt",
]

# المصدر 2 — Hysteria2 + REALITY فقط (نفس المصدر بفلتر أقوى)
SOURCE_2_URLS = [
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt",
    "https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/reality.txt",
]

# المصدر 4 — morpheusadam (مختبر فعلياً)
SOURCE_4_URLS = [
    "https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/mix",
    "https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/vless",
    "https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/hysteria2",
]

# ─────────────────────────────────────────────────────────────
# دوال مساعدة
# ─────────────────────────────────────────────────────────────

def fetch_text(url: str, timeout: int = 20) -> str:
    """يجيب نص من URL."""
    try:
        r = requests.get(url, timeout=timeout, headers={"User-Agent": "Mozilla/5.0"})
        if r.status_code == 200:
            return r.text
    except Exception as e:
        print(f"  [خطأ] {url}: {e}")
    return ""


def decode_if_base64(text: str) -> str:
    """يفك base64 إذا كان النص مشفر."""
    try:
        decoded = base64.b64decode(text + "==").decode("utf-8")
        if any(p in decoded for p in ["vless://", "vmess://", "trojan://", "ss://", "hysteria2://", "hy2://"]):
            return decoded
    except Exception:
        pass
    return text


def parse_configs(raw: str) -> list[str]:
    """يستخرج الكونفيغات من النص."""
    text = decode_if_base64(raw.strip())
    prefixes = ("vless://", "vmess://", "trojan://", "ss://", "hysteria2://", "hy2://")
    configs = []
    for line in text.splitlines():
        line = line.strip()
        if any(line.startswith(p) for p in prefixes):
            configs.append(line)
    return configs


def detect_protocol(config: str) -> str:
    """يحدد البروتوكول من الكونفيغ."""
    if config.startswith("vless://"):
        if "reality" in config.lower() or "xtls" in config.lower():
            return "vless-reality"
        return "vless"
    if config.startswith("vmess://"):
        return "vmess"
    if config.startswith("trojan://"):
        return "trojan"
    if config.startswith("ss://"):
        return "shadowsocks"
    if config.startswith("hysteria2://") or config.startswith("hy2://"):
        return "hysteria2"
    return "unknown"


def is_hard_to_block(protocol: str) -> bool:
    """البروتوكولات الأصعب حجباً."""
    return protocol in ("hysteria2", "vless-reality", "vless")


def config_to_row(config: str, source_name: str) -> dict | None:
    """يحول كونفيغ لصف قاعدة بيانات."""
    protocol = detect_protocol(config)
    if protocol == "unknown":
        return None

    # استخرج IP أو domain من الرابط
    try:
        after_proto = config.split("://", 1)[1]
        # vmess يكون base64
        if protocol == "vmess":
            try:
                decoded = base64.b64decode(after_proto + "==").decode("utf-8")
                import json
                vmess_data = json.loads(decoded)
                host = vmess_data.get("add", "")
            except Exception:
                host = ""
        else:
            # vless://uuid@host:port?...
            at_part = after_proto.split("@")[-1] if "@" in after_proto else after_proto
            host = at_part.split(":")[0].split("?")[0].split("#")[0]
    except Exception:
        host = ""

    if not host:
        return None

    return {
        "ip": host,
        "country_name": "Unknown",
        "country_code": "XX",
        "ping": 100 if is_hard_to_block(protocol) else 200,
        "ovpn_config": config,        # نحفظ الكونفيغ هنا
        "num_sessions": 0,
        "protocol": protocol,
        "source": source_name,
        "is_active": True,
        "is_hard_to_block": is_hard_to_block(protocol),
    }


# ─────────────────────────────────────────────────────────────
# المصدر 1 — 0xRadikal كل البروتوكولات
# ─────────────────────────────────────────────────────────────
def fetch_source_1() -> list[dict]:
    print("\n[المصدر 1] 0xRadikal — كل البروتوكولات")
    rows = []
    for url in SOURCE_1_URLS:
        raw = fetch_text(url)
        if not raw:
            continue
        configs = parse_configs(raw)
        print(f"  ← {len(configs)} كونفيغ من {url.split('/')[-1]}")
        for c in configs:
            row = config_to_row(c, "source_1_all")
            if row:
                rows.append(row)
    print(f"[المصدر 1] المجموع: {len(rows)}")
    return rows


# ─────────────────────────────────────────────────────────────
# المصدر 2 — 0xRadikal Hysteria2 + REALITY فقط
# ─────────────────────────────────────────────────────────────
def fetch_source_2() -> list[dict]:
    print("\n[المصدر 2] 0xRadikal — Hysteria2 + REALITY فقط")
    rows = []
    for url in SOURCE_2_URLS:
        raw = fetch_text(url)
        if not raw:
            continue
        configs = parse_configs(raw)
        # فلتر — بس Hysteria2 و REALITY
        filtered = [c for c in configs if detect_protocol(c) in ("hysteria2", "vless-reality")]
        print(f"  ← {len(filtered)} كونفيغ مفلتر من {url.split('/')[-1]}")
        for c in filtered:
            row = config_to_row(c, "source_2_hard")
            if row:
                rows.append(row)
    print(f"[المصدر 2] المجموع: {len(rows)}")
    return rows


# ─────────────────────────────────────────────────────────────
# المصدر 3 — Cloudflare Workers VLESS+WS
# ─────────────────────────────────────────────────────────────
def fetch_source_3() -> list[dict]:
    """
    Cloudflare Workers — سيرفرات VLESS+WS تحت Cloudflare CDN.
    هذي السيرفرات تحتاج تضيفها يدوياً من Cloudflare Workers الخاص بك.
    أو تجيبها من مصادر تنشر VLESS+CDN كونفيغات.
    """
    print("\n[المصدر 3] Cloudflare Workers — VLESS+WS")

    # روابط VLESS+WS تحت Cloudflare CDN من مصادر معروفة
    cf_urls = [
        "https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub1.txt",
        "https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub2.txt",
    ]

    rows = []
    for url in cf_urls:
        raw = fetch_text(url)
        if not raw:
            continue
        configs = parse_configs(raw)
        # فلتر — بس VLESS و Trojan (الأقوى مع CDN)
        cf_configs = [c for c in configs if detect_protocol(c) in ("vless", "trojan")]
        print(f"  ← {len(cf_configs)} كونفيغ من {url.split('/')[-1]}")
        for c in cf_configs[:30]:  # أخذ أول 30 بس
            row = config_to_row(c, "source_3_cloudflare")
            if row:
                row["ping"] = 80  # أعطيها أولوية أعلى
                rows.append(row)

    print(f"[المصدر 3] المجموع: {len(rows)}")
    return rows


# ─────────────────────────────────────────────────────────────
# المصدر 4 — morpheusadam (مختبر فعلياً)
# ─────────────────────────────────────────────────────────────
def fetch_source_4() -> list[dict]:
    print("\n[المصدر 4] morpheusadam — مختبر فعلياً")
    rows = []
    for url in SOURCE_4_URLS:
        raw = fetch_text(url)
        if not raw:
            continue
        configs = parse_configs(raw)
        print(f"  ← {len(configs)} كونفيغ من {url.split('/')[-1]}")
        for c in configs:
            row = config_to_row(c, "source_4_tested")
            if row:
                row["ping"] = max(50, row["ping"] - 50)  # أولوية أعلى لأنه مختبر
                rows.append(row)
    print(f"[المصدر 4] المجموع: {len(rows)}")
    return rows


# ─────────────────────────────────────────────────────────────
# دمج وفلتر
# ─────────────────────────────────────────────────────────────
def merge_and_filter(all_rows: list[dict]) -> list[dict]:
    print(f"\n[دمج] المجموع قبل الفلتر: {len(all_rows)}")

    # إزالة المكررين بالـ IP + Protocol
    seen = set()
    unique = []
    for row in all_rows:
        key = f"{row['ip']}_{row['protocol']}"
        if key not in seen:
            seen.add(key)
            unique.append(row)

    print(f"[دمج] بعد إزالة المكررين: {len(unique)}")

    # ترتيب — الأصعب حجباً أولاً، ثم الأقل ping
    unique.sort(key=lambda r: (
        0 if r.get("is_hard_to_block") else 1,
        r["ping"]
    ))

    # أخذ أفضل MAX_SERVERS
    final = unique[:MAX_SERVERS]
    print(f"[دمج] النهائي: {len(final)}")

    # إحصاء حسب المصدر
    from collections import Counter
    source_counts = Counter(r["source"] for r in final)
    for src, count in source_counts.items():
        print(f"  {src}: {count}")

    return final


# ─────────────────────────────────────────────────────────────
# رفع على Supabase
# ─────────────────────────────────────────────────────────────
def upload_to_supabase(servers: list[dict]):
    client = create_client(SUPABASE_URL, SUPABASE_KEY)

    # احذف القديمة
    client.table("servers").delete().neq("ip", "").execute()
    print("\n[Supabase] حذفنا السيرفرات القديمة")

    # ارفع الجديدة
    batch_size = 20
    uploaded = 0
    for i in range(0, len(servers), batch_size):
        batch = servers[i:i + batch_size]
        client.table("servers").insert(batch).execute()
        uploaded += len(batch)
        print(f"[Supabase] رفعنا {uploaded}/{len(servers)}")

    print(f"[Supabase] ✅ اكتمل — {len(servers)} سيرفر")


# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
def main():
    print("=" * 50)
    print("بدأ تحديث السيرفرات — 4 مصادر")
    print("=" * 50)

    all_rows = []
    all_rows += fetch_source_1()
    all_rows += fetch_source_2()
    all_rows += fetch_source_3()
    all_rows += fetch_source_4()

    if not all_rows:
        print("❌ ما لقينا أي سيرفر من أي مصدر")
        return

    final = merge_and_filter(all_rows)

    if not final:
        print("❌ ما في سيرفرات بعد الفلتر")
        return

    upload_to_supabase(final)

    print("=" * 50)
    print(f"✅ خلصنا — {len(final)} سيرفر جاهز في Supabase")
    print("=" * 50)


if __name__ == "__main__":
    main()
