#!/usr/bin/env python3
"""Freeleech ratio farmer.

Polls the Torznab indexers declared in the cross-seed secret (C411 via
Prowlarr, YggReborn API), keeps only freeleech items
(downloadvolumefactor == 0) within size/category limits, injects them into
qBittorrent under the "freeleech" category and removes them once seeded.

Runs as the cross-seed user (already VPN-routed + kill-switched).
"""

import email.utils
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

CREDENTIALS_DIR = os.environ.get("CREDENTIALS_DIRECTORY", "")
SECRET = os.environ.get("FARMER_SECRET", os.path.join(CREDENTIALS_DIR, "crossSeedSecret"))

MAX_ADDS = int(os.environ.get("FARMER_MAX_ADDS", "5"))
MIN_SEEDERS = int(os.environ.get("FARMER_MIN_SEEDERS", "1"))
MIN_LEECHERS = int(os.environ.get("FARMER_MIN_LEECHERS", "0"))
MAX_SIZE = int(os.environ.get("FARMER_MAX_SIZE_GB", "20")) * 1024**3
MAX_TOTAL = int(os.environ.get("FARMER_MAX_TOTAL_GB", "100")) * 1024**3
MIN_FREE = int(os.environ.get("FARMER_MIN_FREE_GB", "200")) * 1024**3
CLEAN_RATIO = float(os.environ.get("FARMER_CLEAN_RATIO", "2.0"))
CLEAN_DAYS = float(os.environ.get("FARMER_CLEAN_DAYS", "14"))
# Weight of the freshness term relative to scarcity in swarm_score(), and the
# age at which freshness has decayed to half. See swarm_score() for why they are
# added rather than multiplied.
FRESH_WEIGHT = float(os.environ.get("FARMER_FRESH_WEIGHT", "2.0"))
FRESH_HALFLIFE_H = float(os.environ.get("FARMER_FRESH_HALFLIFE_H", "6"))
CATEGORY = "freeleech"
SAVE_PATH = os.environ.get("FARMER_SAVE_PATH", "/mnt/storage/medias/downloads/freeleech")
# Allowed Torznab category prefixes: 2xxx Movies, 3xxx Audio, 5xxx TV, 7xxx Books.
ALLOWED_PREFIXES = tuple(os.environ.get("FARMER_CAT_PREFIXES", "2,3,5,7").split(","))

NS = {
    "t": "http://torznab.com/schemas/2015/feed",
    "n": "http://www.newznab.com/DTD/2010/feeds/attributes/",
}


def log(msg):
    print(f"[freeleech-farmer] {msg}", flush=True)


def load_config():
    with open(SECRET, encoding="utf-8") as fh:
        cfg = json.load(fh)
    client = cfg["torrentClients"][0]
    _, url = client.split(":", 1)  # "qbittorrent:http://user:pass@host:port"
    parsed = urllib.parse.urlparse(url)
    base = f"{parsed.scheme}://{parsed.hostname}:{parsed.port}"
    user = urllib.parse.unquote(parsed.username or "")
    password = urllib.parse.unquote(parsed.password or "")
    return cfg.get("torznab", []), base, user, password


def qbt_login(base, user, password):
    data = urllib.parse.urlencode({"username": user, "password": password}).encode()
    req = urllib.request.Request(
        base + "/api/v2/auth/login", data=data, headers={"Referer": base}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        cookie = resp.headers.get("Set-Cookie", "")
    return cookie.split(";")[0] if cookie else ""


def qbt(base, sid, path, params=None):
    data = urllib.parse.urlencode(params).encode() if params else None
    req = urllib.request.Request(base + path, data=data, headers={"Cookie": sid})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode()


def qbt_add_file(base, sid, torrent_bytes, filename, params):
    """Upload a .torrent to qBittorrent (multipart)."""
    boundary = "----freeleech" + os.urandom(8).hex()
    body = b""
    for key, value in params.items():
        body += (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'
        ).encode()
    body += (
        f'--{boundary}\r\nContent-Disposition: form-data; name="torrents"; '
        f'filename="{filename}"\r\nContent-Type: application/x-bittorrent\r\n\r\n'
    ).encode() + torrent_bytes + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        base + "/api/v2/torrents/add",
        data=body,
        headers={
            "Cookie": sid,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode()


def http_get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "freeleech-farmer/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def parse_items(xml_bytes):
    root = ET.fromstring(xml_bytes)
    items = []
    for item in root.iter("item"):
        attrs = {}
        cats = []
        for attr in item.findall("t:attr", NS):
            name, value = attr.get("name"), attr.get("value")
            if name == "category":
                cats.append(value or "")
            else:
                attrs[name] = value
        enclosure = item.find("enclosure")
        seeders = int(attrs.get("seeders") or 0)
        items.append(
            {
                "title": item.findtext("title") or "",
                "link": enclosure.get("url") if enclosure is not None else None,
                "size": size_of(item, attrs, enclosure),
                "seeders": seeders,
                "leechers": leechers_of(attrs, seeders),
                "published": published_of(item),
                "hash": (attrs.get("infohash") or "").lower(),
                "cats": cats,
                "freeleech": attrs.get("downloadvolumefactor") == "0",
            }
        )
    return items


def size_of(item, attrs, enclosure):
    """Torrent size in bytes, from wherever the indexer actually put it.

    Prowlarr does NOT emit a `torznab:attr name="size"`: it puts the size in the
    `<size>` element and in `enclosure length`. Reading only the attr — as this
    did — therefore yielded 0 for **every** item, and the `size == 0` guard in
    main() then rejected the entire freeleech feed. The farmer had been
    structurally unable to add anything.
    """
    for candidate in (
        attrs.get("size"),
        item.findtext("size"),
        enclosure.get("length") if enclosure is not None else None,
    ):
        try:
            value = int(candidate)
        except (TypeError, ValueError):
            continue
        if value > 0:
            return value
    return 0


def leechers_of(attrs, seeders):
    """Leecher count, working around the Torznab `peers` convention.

    In Torznab, `peers` is the *total* swarm size: seeders + leechers. Verified
    on both indexers in use — C411 reports 22S/44P, 98S/203P, and YggReborn
    reports 9S/9P, 12S/12P (i.e. no leechers at all).

    This used to read `attrs.get("peers") or attrs.get("leechers")`, which took
    `peers` first and called it `leechers`: it claimed 44 leechers where there
    were 22, and 9 where there were none. Combined with a sort on `-leechers`,
    the farmer was ranking by total swarm size — actively preferring the most
    crowded swarms, which is the exact opposite of what earns ratio.
    """
    if attrs.get("leechers") is not None:
        return max(0, int(attrs["leechers"]))
    if attrs.get("peers") is not None:
        return max(0, int(attrs["peers"]) - seeders)
    return 0


def published_of(item):
    """Item publication time as a Unix timestamp, or None if unusable."""
    raw = item.findtext("pubDate")
    if not raw:
        return None
    try:
        return email.utils.parsedate_to_datetime(raw).timestamp()
    except (TypeError, ValueError):
        return None


def swarm_score(item, now):
    """Rank candidates by how much upload they can plausibly earn.

    Two independent sources of ratio, added rather than multiplied so that
    either one alone is enough to rank an item highly:

    - *scarcity*: leechers per seeder. Being one of 2 seeders facing 20 leechers
      earns upload; being the 98th seeder facing 105 leechers earns almost none.
      This is why the raw leecher count is the wrong key — it ignores the
      competition.
    - *freshness*: most of a torrent's lifetime upload happens in its first
      hours, while peers still need pieces few others have. A brand-new release
      legitimately shows 0 seeders and 0 leechers, so scarcity alone would rank
      it last; the additive freshness term is what keeps it in the running.
    """
    scarcity = item["leechers"] / (item["seeders"] + 1)
    published = item.get("published")
    if published is None:
        freshness = 0.0
    else:
        age_hours = max(0.0, (now - published) / 3600)
        freshness = 1.0 / (1.0 + age_hours / FRESH_HALFLIFE_H)
    return scarcity + FRESH_WEIGHT * freshness


def free_space(path):
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize


def main():
    torznab, qbt_url, qbt_user, qbt_pw = load_config()
    sid = qbt_login(qbt_url, qbt_user, qbt_pw)
    if not sid:
        log("ERROR: qBittorrent login failed")
        sys.exit(1)

    try:
        qbt(qbt_url, sid, "/api/v2/torrents/createCategory",
            {"category": CATEGORY, "savePath": SAVE_PATH})
    except Exception:
        pass  # category already exists

    info = json.loads(qbt(qbt_url, sid, "/api/v2/torrents/info", {"category": CATEGORY}))
    have = {t["hash"].lower() for t in info}
    total = sum(t.get("size", 0) for t in info)

    now = time.time()
    for torrent in info:
        ratio = torrent.get("ratio", 0) or 0
        days = (now - torrent.get("added_on", now)) / 86400
        if ratio >= CLEAN_RATIO or days >= CLEAN_DAYS:
            log(f"cleanup: {torrent['name'][:60]} (ratio={ratio:.2f}, {days:.1f}d)")
            qbt(qbt_url, sid, "/api/v2/torrents/delete",
                {"hashes": torrent["hash"], "deleteFiles": "true"})
            have.discard(torrent["hash"].lower())
            total -= torrent.get("size", 0)

    if free_space("/mnt/storage") < MIN_FREE:
        log(f"only {free_space('/mnt/storage') / 1024**3:.0f} GiB free, skipping")
        return

    candidates = []
    seen = set()
    for base in torznab:
        sep = "&" if "?" in base else "?"
        try:
            items = parse_items(http_get(f"{base}{sep}t=search&limit=100"))
        except Exception as exc:  # noqa: BLE001
            log(f"ERROR fetching {base.split('?')[0]}: {exc}")
            continue
        for item in items:
            if not item["freeleech"] or not item["link"] or not item["hash"]:
                continue
            if item["hash"] in have or item["hash"] in seen:
                continue
            if item["size"] > MAX_SIZE or item["size"] == 0:
                continue
            if item["seeders"] < MIN_SEEDERS or item["leechers"] < MIN_LEECHERS:
                continue
            if not any(c.startswith(ALLOWED_PREFIXES) for c in item["cats"]):
                continue
            seen.add(item["hash"])
            candidates.append(item)

    # Upload potential first: scarcity + freshness (see swarm_score).
    candidates.sort(key=lambda i: -swarm_score(i, now))

    added = 0
    for item in candidates:
        if added >= MAX_ADDS or total >= MAX_TOTAL:
            break
        # YggReborn serves .torrent via www -> 302 to api with an
        # HTML-escaped (&amp;) Location that qBittorrent cannot follow, and
        # its parallel fetch gets rate-limited. Fetch it ourselves and
        # upload the file instead.
        link = item["link"].replace("://www.yggreborn.org/", "://api.yggreborn.org/")
        try:
            blob = http_get(link)
            if not blob.startswith(b"d"):
                raise ValueError("not a bencoded torrent")
            qbt_add_file(
                qbt_url, sid, blob, f"{item['hash']}.torrent",
                {"category": CATEGORY, "tags": "freeleech", "savepath": SAVE_PATH},
            )
            time.sleep(1)
        except urllib.error.HTTPError as exc:
            if exc.code == 409:  # already in qBittorrent
                log(f"already in client: {item['title'][:60]}")
                have.add(item["hash"])
                continue
            log(f"ERROR adding {item['title'][:50]}: {exc}")
            continue
        except Exception as exc:  # noqa: BLE001
            log(f"ERROR adding {item['title'][:50]}: {exc}")
            continue
        age = "?" if item.get("published") is None else f"{(now - item['published']) / 3600:.0f}h"
        log(
            f"added: {item['title'][:70]} ({item['size'] / 1024**3:.2f} GiB, "
            f"{item['seeders']}S/{item['leechers']}L, {age}, "
            f"score={swarm_score(item, now):.2f})"
        )
        have.add(item["hash"])
        total += item["size"]
        added += 1

    log(f"done: {added} added, {len(have)} freeleech torrents, {total / 1024**3:.1f} GiB")


if __name__ == "__main__":
    main()
