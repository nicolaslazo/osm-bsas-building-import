#!/usr/bin/env python3
"""Check and delete the old nodes Reshape left unused (PLAN 6.3), before the next release round.

Usage:
    python migrations/510-clean-up-reshape-orphans.py changesets/SCHEMA [--osm FILE]

--osm checks against a local .osm file instead of Overpass (tests).

Reads DIR/reshape-orphans.tsv from 500: untagged Live nodes that no Reshape task deletes because
a Live way that another task replaces still used them. Once both tasks are done, nothing uses the
node.
Each node is checked against current OSM through Overpass and sorted:

    orphaned         untagged, unchanged, used by nothing: written for deletion
    task pending     still used, but only by Live ways 500 replaces: their task is not done yet
    unexpected use   used by a way or relation 500 did not replace: the process missed something
    changed          another mapper edited it since the fetch: left alone
    gone             no longer in OSM

Any "unexpected use" means the process does not check out; investigate before uploading.
Writes DIR/reshape-orphans-cleanup.osc (node deletions for the import account, 6.7) and
DIR/reshape-orphans-report.tsv. Uploads nothing. Safe to run again as tasks are completed.
"""

import os
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import Counter

OVERPASS = "https://overpass-api.de/api/interpreter"
CHUNK = 2000


def overpass(ids):
    query = ("[out:xml][timeout:300];node(id:%s)->.n;.n out meta;way(bn.n);out skel;"
             "relation(bn.n);out skel;" % ",".join(map(str, ids)))
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(5):
        req = urllib.request.Request(OVERPASS, data, {"User-Agent": "osm-bsas-building-import/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                return ET.fromstring(resp.read())
        except OSError as e:
            print("overpass attempt %d: %s" % (attempt + 1, e), file=sys.stderr)
            time.sleep(60)
    sys.exit("Overpass failed")


def main():
    args = sys.argv[1:]
    local = None
    if "--osm" in args:
        i = args.index("--osm")
        local = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    base = args[0]
    listed = {}
    with open(os.path.join(base, "reshape-orphans.tsv")) as f:
        next(f)
        for line in f:
            node, version, lat, lon, ways = line.rstrip("\n").split("\t")
            listed[int(node)] = (version, lat, lon, {int(w) for w in ways.split(",")})

    ids = sorted(listed)
    current, users = {}, {n: set() for n in ids}
    if local:
        roots = [ET.parse(local).getroot()]
    else:
        roots = (overpass(ids[i:i + CHUNK]) for i in range(0, len(ids), CHUNK))
    for root in roots:
        for el in root:
            if el.tag == "node" and int(el.get("id")) in users:
                current[int(el.get("id"))] = (el.get("version"), el.find("tag") is not None)
            elif el.tag == "way":
                for nd in el.iter("nd"):
                    n = int(nd.get("ref"))
                    if n in users:
                        users[n].add(("way", int(el.get("id"))))
            elif el.tag == "relation":
                for m in el.iter("member"):
                    n = int(m.get("ref"))
                    if m.get("type") == "node" and n in users:
                        users[n].add(("relation", int(el.get("id"))))

    status, counts = {}, Counter()
    for n in ids:
        version, _, _, replaced = listed[n]
        if n not in current:
            s = "gone"
        elif current[n][0] != version or current[n][1]:
            s = "changed"
        elif not users[n]:
            s = "orphaned"
        elif all(t == "way" and w in replaced for t, w in users[n]):
            s = "task pending"
        else:
            s = "unexpected use"
        status[n] = s
        counts[s] += 1

    with open(os.path.join(base, "reshape-orphans-report.tsv"), "w") as f:
        f.write("node\tstatus\tused_by\n")
        for n in ids:
            f.write("%d\t%s\t%s\n" % (n, status[n], ",".join("%s/%d" % u for u in sorted(users[n]))))

    root = ET.Element("osmChange", version="0.6", generator="osm-bsas-building-import")
    delete = ET.SubElement(root, "delete")
    for n in ids:
        if status[n] == "orphaned":
            version, lat, lon, _ = listed[n]
            ET.SubElement(delete, "node", id=str(n), version=version, lat=lat, lon=lon)
    ET.indent(root)
    ET.ElementTree(root).write(os.path.join(base, "reshape-orphans-cleanup.osc"),
                               encoding="UTF-8", xml_declaration=True)

    for s in ("orphaned", "task pending", "unexpected use", "changed", "gone"):
        print("%-15s %d" % (s, counts[s]))
    if counts["unexpected use"]:
        print("Unexpected use found: see reshape-orphans-report.tsv before uploading anything.")
        sys.exit(2)


if __name__ == "__main__":
    main()
