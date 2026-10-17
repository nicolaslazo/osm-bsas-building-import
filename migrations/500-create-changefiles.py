#!/usr/bin/env python3
"""Write the result sets of one pipeline run (PLAN 3.1, 4.6, 6.3).

Usage:
    python migrations/500-create-changefiles.py SCHEMA [--live data/live-osm-YYYY-MM-DD.osm] [--out DIR]
                                                [--blocks BKEY,BKEY,...]

Reads structures, parts and classification and reshape_tasks from SCHEMA (migrations 103-170) and writes:
    DIR/new/seccion-NN.osm       New, one file per seccion
    DIR/new/nosmp-N.osm          New, one file per no-SMP group that is a block by itself
    DIR/conflicts/BKEY.osm       Conflicts, one file per block (held in round 1)
    DIR/reshape/wID.osc, rID.osc Reshape, one osmChange per task (170: touching groups), named
                                 by the Live building its first group keeps; for a MapRoulette
                                 cooperative challenge
    DIR/reshape-orphans.tsv      old nodes left unused once every Reshape task is uploaded
                                 (checked and deleted by 510 before the next round)
DIR defaults to changesets/SCHEMA and is replaced. --blocks writes only the structures of those
blocks (the pilot).

Geometry goes through ogr2osm: a way per ring-less polygon, a multipolygon relation where holes
remain, nodes shared by rounded coordinate (7 digits, 3.2). A structure of one footprint is a
building=yes way; a larger one is a building=yes outline plus one building:part per footprint
(3.3). ref:cadastre only on building=yes (3.4); no height in asentamientos informales.

Reshape (4.3) keeps each Live building's id, version and tags; height is set to the city's altura,
replacing a Live value, and ref:cadastre is added only where Live has none. Old nodes and member
ways are deleted where they carry no tags and nothing in the Live fetch outside the task uses
them. The fetch (bin/fetch-live.sh) holds every way that uses a building node, so a node shared
with a road or wall is seen and kept. A new node at the exact position (7 digits) of a Live node
that a way uses becomes that node, and no task deletes it (6.3).

Needs the system GDAL Python bindings (ogr2osm cannot build its own):
    uv venv --system-site-packages .venv
    uv pip install --no-deps ogr2osm && uv pip install lxml psycopg2-binary
    .venv/bin/python migrations/500-create-changefiles.py run_YYYYMMDD
"""

import argparse
import glob
import logging
import os
import shutil
import sys
from collections import defaultdict

import ogr2osm
import psycopg2
from lxml import etree
from ogr2osm.osm_geometries import OsmRelation, OsmWay
from ogr2osm.version import __program__
from osgeo import ogr, osr

DSN = "host=localhost port=6543 dbname=osm_db user=osm password=password"
DIGITS = 7
FIELDS = ["building", "building:part", "height", "ref:cadastre", "_sid", "_role"]

ogr.UseExceptions()
logging.getLogger(__program__).setLevel(logging.WARNING)


class BuildingTranslation(ogr2osm.TranslationBase):
    """Tags come ready from SQL; fields starting with _ only link back to the structure."""

    def __init__(self):
        super().__init__()
        self.outlines = {}
        self.output = None

    def filter_tags(self, tags):
        return {k: v for k, v in tags.items() if v and not k.startswith("_")}

    def merge_tags(self, geometry_type, tags_existing_geometry, tags_new_geometry):
        # Nodes and untagged rings are shared; an outline and a part of the same shape stay two ways
        if geometry_type != "node" and (tags_existing_geometry or tags_new_geometry):
            return None
        return super().merge_tags(geometry_type, tags_existing_geometry, tags_new_geometry)

    def process_feature_post(self, osmgeometry, ogrfeature, ogrgeometry):
        if ogrfeature.GetField("_role") == "outline":
            self.outlines[int(ogrfeature.GetField("_sid"))] = osmgeometry

    def process_output(self, osmnodes, osmways, osmrelations):
        self.output = (osmnodes, osmways, osmrelations)


class MemorySource:
    """An in-memory OGR layer in the shape ogr2osm's OsmData.process expects."""

    source_encoding = "utf-8"

    def __init__(self, rows):
        srs = osr.SpatialReference()
        srs.ImportFromEPSG(4326)
        self.ds = ogr.GetDriverByName("Memory").CreateDataSource("")
        self.layer = self.ds.CreateLayer("f", srs, ogr.wkbUnknown)
        for name in FIELDS:
            self.layer.CreateField(ogr.FieldDefn(name, ogr.OFTString))
        defn = self.layer.GetLayerDefn()
        for tags, wkb in rows:
            feature = ogr.Feature(defn)
            for i, name in enumerate(FIELDS):
                if tags.get(name) is not None:
                    feature.SetField(i, str(tags[name]))
            feature.SetGeometry(ogr.CreateGeometryFromWkb(bytes(wkb)))
            self.layer.CreateFeature(feature)

    def get_layer_count(self):
        return 1

    def get_layer(self, index):
        self.layer.ResetReading()
        return self.layer, lambda geometry: None


def build(rows):
    translation = BuildingTranslation()
    osmdata = ogr2osm.OsmData(translation, rounding_digits=DIGITS, significant_digits=DIGITS)
    osmdata.process(MemorySource(rows))
    return translation, osmdata


def fmt_height(h):
    if h is None or h <= 0:
        return None
    return ("%.2f" % h).rstrip("0").rstrip(".")


def outline_tags(sid, ref, height, informal):
    return {"building": "yes", "ref:cadastre": ref,
            "height": None if informal else fmt_height(height), "_sid": sid, "_role": "outline"}


def part_tags(sid, altura):
    return {"building:part": "yes", "height": fmt_height(altura), "_sid": sid, "_role": "part"}


FEATURES_SQL = """
SELECT k.result, s.sid, s.bkey, s.ref_cadastre, s.height, s.asentamiento_informal, NULL::float8,
       ST_AsBinary(s.geom), 0 AS ord
FROM structures s JOIN classification k USING (sid)
WHERE k.result = %(result)s AND (%(blocks)s::text[] IS NULL OR s.bkey = ANY(%(blocks)s))
UNION ALL
SELECT k.result, p.sid, s.bkey, NULL, NULL, NULL, p.altura, ST_AsBinary(p.geom), 1
FROM parts p JOIN structures s USING (sid) JOIN classification k USING (sid)
WHERE k.result = %(result)s AND (%(blocks)s::text[] IS NULL OR s.bkey = ANY(%(blocks)s))
ORDER BY 3, 2, 9
"""


def file_key(result, bkey):
    if result == "C":
        return os.path.join("conflicts", bkey + ".osm")
    if bkey.startswith("nosmp-"):
        return os.path.join("new", bkey + ".osm")
    return os.path.join("new", "seccion-%s.osm" % bkey.split("-")[0].zfill(2))


def write_block_files(conn, out, result, blocks):
    """New or Conflicts: plain JOSM .osm files, one per file key. Rows arrive ordered by block,
    and the blocks of one seccion sort together, so each file is written as soon as it ends."""
    counts = defaultdict(lambda: [0, 0])
    rows, current = [], None

    def flush():
        _, osmdata = build(rows)
        osmdata.output(ogr2osm.OsmDataWriter(os.path.join(out, current), no_upload_false=True,
                                             significant_digits=DIGITS))

    with conn.cursor(name="features_" + result) as cur:
        cur.itersize = 20000
        cur.execute(FEATURES_SQL, {"result": result, "blocks": blocks})
        for res, sid, bkey, ref, height, informal, altura, wkb, ord_ in cur:
            key = file_key(res, bkey)
            if key != current:
                if current is not None:
                    flush()
                if key in counts:
                    raise RuntimeError("%s would be written twice" % key)
                rows, current = [], key
            tags = outline_tags(sid, ref, height, informal) if ord_ == 0 else part_tags(sid, altura)
            rows.append((tags, wkb))
            counts[key][ord_] += 1
    if current is not None:
        flush()
    return counts


def read_live(path):
    """Versions, tags and references of every object in the raw Live fetch (PLAN 6.2)."""
    nodes, ways, rels = {}, {}, {}
    node_ways, way_rels = defaultdict(set), defaultdict(set)
    for _, el in etree.iterparse(path, events=("end",), tag=("node", "way", "relation")):
        oid = int(el.get("id"))
        tags = {t.get("k"): t.get("v") for t in el.iterfind("tag")}
        if el.tag == "node":
            nodes[oid] = (el.get("version"), el.get("lat"), el.get("lon"), tags)
        elif el.tag == "way":
            nds = [int(n.get("ref")) for n in el.iterfind("nd")]
            ways[oid] = (el.get("version"), nds, tags)
            for n in nds:
                node_ways[n].add(oid)
        else:
            members = [(m.get("type"), int(m.get("ref")), m.get("role")) for m in el.iterfind("member")]
            rels[oid] = (el.get("version"), members, tags)
            for t, ref, _ in members:
                if t == "way":
                    way_rels[ref].add(oid)
        el.clear()
    return nodes, ways, rels, node_ways, way_rels


RESHAPE_GROUPS_SQL = """
SELECT g.grp, g.kind, m.id, lb.osm_id, lb.osm_way_id, ls.tagged
FROM live_groups g
JOIN member m USING (grp)
LEFT JOIN live_buildings lb ON lb.ogr_fid = -m.id
LEFT JOIN live_shapes ls ON ls.lid = -m.id
WHERE g.reasons IS NULL AND NOT g.held
"""

RESHAPE_FEATURES_SQL = """
SELECT t.task, k.grp, s.sid, s.ref_cadastre, s.height, s.asentamiento_informal, NULL::float8,
       ST_AsBinary(s.geom), 0
FROM structures s JOIN classification k USING (sid) JOIN reshape_tasks t USING (grp)
WHERE k.result = 'R' AND (%(blocks)s::text[] IS NULL OR s.bkey = ANY(%(blocks)s))
UNION ALL
SELECT t.task, k.grp, p.sid, NULL, NULL, NULL, p.altura, ST_AsBinary(p.geom), 1
FROM parts p JOIN structures s USING (sid) JOIN classification k USING (sid)
JOIN reshape_tasks t USING (grp)
WHERE k.result = 'R' AND (%(blocks)s::text[] IS NULL OR s.bkey = ANY(%(blocks)s))
ORDER BY 1, 2, 3, 9
"""


class Reshape:
    """One osmChange per Reshape task (170): in each group the kept Live building takes its
    structure's shape (4.3)."""

    def __init__(self, live):
        self.nodes, self.ways, self.rels, self.node_ways, self.way_rels = live
        self.stats = defaultdict(int)
        self.all_dropped, self.all_deleted, self.all_reused = set(), set(), set()
        # Live nodes that a way uses, by position; where two share one, the lowest id
        self.at = {}
        for n in sorted(self.node_ways):
            if n in self.nodes:
                self.at.setdefault((coord(float(self.nodes[n][1])), coord(float(self.nodes[n][2]))), n)

    def reuse(self, translation):
        """A new node at the exact position of a Live node becomes that node (6.3), so the task
        shares its walls with the Live buildings beside it. No task deletes a reused node."""
        osmnodes, osmways, osmrels = translation.output
        created = []
        for n in osmnodes:
            live = self.at.get((coord(n.y), coord(n.x)))
            if live is None:
                created.append(n)
            else:
                n.id = live
                self.all_reused.add(live)
        self.stats["nodes reused"] += len(osmnodes) - len(created)
        translation.output = (created, osmways, osmrels)

    def write(self, path, translation, groups):
        osmnodes, osmways, osmrels = translation.output
        modify, delete_ways, delete_rels = [], [], []
        dropped_ways = set()  # Live ways whose old node list goes away
        for kept, others, keep_sid, extra_tags in groups:
            self.replace(translation.outlines[keep_sid], kept, others, extra_tags, osmrels,
                         modify, delete_ways, delete_rels, dropped_ways)
        delete_nodes = sorted({n for w in dropped_ways for n in self.ways[w][1]
                               if n in self.nodes and not self.nodes[n][3]
                               and n not in self.all_reused and self.node_ways[n] <= dropped_ways})

        root = etree.Element("osmChange", version="0.6", generator="osm-bsas-building-import")
        create = etree.SubElement(root, "create")
        modified = {id(o) for _, o, _, _ in modify}
        for n in osmnodes:
            etree.SubElement(create, "node", id=str(n.id), lat=coord(n.y), lon=coord(n.x))
        for w in osmways:
            if id(w) not in modified:
                way_xml(create, w, None, flat(w.tags))
        for r in osmrels:
            rel_xml(create, r, None, flat(r.tags))
        mod = etree.SubElement(root, "modify")
        for kind, obj, version, tags in modify:
            (way_xml if kind == "way" else rel_xml)(mod, obj, version, tags)
        dele = etree.SubElement(root, "delete")
        for r in delete_rels:
            etree.SubElement(dele, "relation", id=str(r), version=self.rels[r][0])
        for w in delete_ways:
            etree.SubElement(dele, "way", id=str(w), version=self.ways[w][0])
        for n in delete_nodes:
            version, lat, lon, _ = self.nodes[n]
            etree.SubElement(dele, "node", id=str(n), version=version, lat=lat, lon=lon)
        etree.ElementTree(root).write(path, encoding="UTF-8", xml_declaration=True, pretty_print=True)
        self.stats["nodes deleted"] += len(delete_nodes)
        self.all_dropped |= dropped_ways
        self.all_deleted.update(delete_nodes)
        self.stats["ways deleted"] += len(delete_ways)
        self.stats["relations deleted"] += len(delete_rels)

    def replace(self, outline, kept, others, extra_tags, osmrels,
                modify, delete_ways, delete_rels, dropped_ways):
        ktype, kid = kept
        if ktype == "w":
            version, _, tags = self.ways[kid]
            tags = merge_live_tags(tags, extra_tags)
            if isinstance(outline, OsmWay):
                outline.id = kid
                modify.append(("way", outline, version, tags))
            else:
                # The outline keeps a hole: the Live way becomes its outer ring and the
                # tags move to the new multipolygon relation
                outer = next(m for m, role in outline.members if role == "outer")
                outer.id = kid
                modify.append(("way", outer, version, {}))
                outline.tags = {"type": ["multipolygon"], **{k: [v] for k, v in tags.items()}}
                self.stats["way became a multipolygon"] += 1
            dropped_ways.add(kid)
        else:
            version, members, tags = self.rels[kid]
            tags = merge_live_tags(tags, extra_tags)
            if isinstance(outline, OsmWay):
                outline.tags = {}
                new_members = [(outline, "outer")]
            else:
                new_members = outline.members
                osmrels.remove(outline)
            rel = OsmRelation({})
            rel.id, rel.members = kid, new_members
            modify.append(("relation", rel, version, tags))
            self.drop_members(members, delete_ways, dropped_ways, kid)
            self.stats["relation kept"] += 1

        for otype, oid in others:  # 1:N: the other Live buildings go
            if otype == "w":
                delete_ways.append(oid)
                dropped_ways.add(oid)
            else:
                delete_rels.append(oid)
                self.drop_members(self.rels[oid][1], delete_ways, dropped_ways, oid)

    def write_orphans(self, path):
        """Nodes no task deletes because another replaced way still uses them: once every Reshape
        task is uploaded, nothing uses them. The cleanup before the next round (510) checks and
        deletes them."""
        orphans = sorted({n for w in self.all_dropped for n in self.ways[w][1]
                          if n in self.nodes and not self.nodes[n][3] and n not in self.all_deleted
                          and n not in self.all_reused and self.node_ways[n] <= self.all_dropped})
        with open(path, "w") as f:
            f.write("node\tversion\tlat\tlon\tways\n")
            for n in orphans:
                version, lat, lon, _ = self.nodes[n]
                f.write("%d\t%s\t%s\t%s\t%s\n" % (n, version, lat, lon,
                                                   ",".join(map(str, sorted(self.node_ways[n])))))
        self.stats["nodes orphaned once every task is uploaded"] = len(orphans)

    def drop_members(self, members, delete_ways, dropped_ways, owner):
        """Member ways of a replaced or deleted relation go when untagged and in no other relation."""
        for t, ref, _ in members:
            if t != "way" or ref not in self.ways:
                continue
            if not self.ways[ref][2] and self.way_rels[ref] <= {owner}:
                delete_ways.append(ref)
                dropped_ways.add(ref)
            else:
                self.stats["member ways kept"] += 1


def merge_live_tags(live, ours):
    """Live tags stay; height takes the city's altura; ref:cadastre is added where Live has none."""
    tags = dict(live)
    if ours["height"]:
        tags["height"] = ours["height"]
    if ours["ref:cadastre"] and "ref:cadastre" not in tags:
        tags["ref:cadastre"] = ours["ref:cadastre"]
    return tags


def coord(v):
    return ("%.*f" % (DIGITS, v)).rstrip("0").rstrip(".")


def flat(tags):
    return {k: ";".join(v for v in vs if v) for k, vs in tags.items()}


def way_xml(parent, way, version, tags):
    el = etree.SubElement(parent, "way", id=str(way.id), **({"version": version} if version else {}))
    for n in way.nodes:
        etree.SubElement(el, "nd", ref=str(n.id))
    for k, v in sorted(tags.items()):
        etree.SubElement(el, "tag", k=k, v=v)


def rel_xml(parent, rel, version, tags):
    el = etree.SubElement(parent, "relation", id=str(rel.id), **({"version": version} if version else {}))
    for m, role in rel.members:
        etree.SubElement(el, "member", type="way", ref=str(m.id), role=role)
    for k, v in sorted(tags.items()):
        etree.SubElement(el, "tag", k=k, v=v)


def write_reshape(conn, out, live_path, blocks):
    reshape = Reshape(read_live(live_path))
    groups = defaultdict(lambda: {"st": [], "live": []})
    with conn.cursor() as cur:
        cur.execute(RESHAPE_GROUPS_SQL)
        for grp, kind, mid, osm_id, osm_way_id, tagged in cur:
            g = groups[grp]
            g["kind"] = kind
            if mid > 0:
                g["st"].append(mid)
            else:
                g["live"].append((-mid, ("r", int(osm_id)) if osm_id else ("w", int(osm_way_id)), tagged))
        cur.execute("SELECT sid, -lid, overlap FROM contacts WHERE link")
        overlap = {(sid, lid): ov for sid, lid, ov in cur}

    # Every task is built and its nodes reused before any is written, so no task deletes a node
    # another task reuses
    pending = []
    with conn.cursor(name="reshape_features") as cur:
        cur.itersize = 20000
        cur.execute(RESHAPE_FEATURES_SQL, {"blocks": blocks})
        rows, extra, grps, current = [], {}, [], None
        for task, grp, sid, ref, height, informal, altura, wkb, ord_ in cur:
            if task != current and current is not None:
                build_task(out, reshape, [groups[g] for g in grps], rows, extra, overlap, pending)
                rows, extra, grps = [], {}, []
            current = task
            if not grps or grps[-1] != grp:
                grps.append(grp)
            if ord_ == 0:
                tags = outline_tags(sid, ref, height, informal)
                extra[sid] = {"ref:cadastre": tags["ref:cadastre"], "height": tags["height"]}
            else:
                tags = part_tags(sid, altura)
            rows.append((tags, wkb))
        if current is not None:
            build_task(out, reshape, [groups[g] for g in grps], rows, extra, overlap, pending)
    for path, translation, task_groups in pending:
        reshape.write(path, translation, task_groups)
    reshape.write_orphans(os.path.join(out, "reshape-orphans.tsv"))
    return len(pending), len(groups), reshape.stats


def choose_kept(g, overlap):
    lives = g["live"]
    if g["kind"] == "1:N":
        tagged = [l for l in lives if l[2]]
        sid = g["st"][0]
        kept = tagged[0] if tagged else max(lives, key=lambda l: overlap.get((sid, -l[0]), 0))
    else:
        kept = lives[0]
    keep_sid = max(g["st"], key=lambda s: overlap.get((s, -kept[0]), 0))
    return kept[1], [l[1] for l in lives if l is not kept], keep_sid


def build_task(out, reshape, task_groups, rows, extra, overlap, pending):
    chosen = [choose_kept(g, overlap) for g in task_groups]
    known = {"w": reshape.ways, "r": reshape.rels}
    if any(o[1] not in known[o[0]] for kept, others, _ in chosen for o in [kept, *others]):
        reshape.stats["tasks missing from the Live fetch"] += 1
        return
    # Each kept outline is built tagged, so no part shares its way; its tags come from Live
    # when the file is written. A group's other structures stay new ways (N:1).
    translation, osmdata = build(rows)
    osmdata.output(ogr2osm.DataWriterBase())
    reshape.reuse(translation)
    reshape.stats["structures"] += sum(len(g["st"]) for g in task_groups)
    reshape.stats["tasks with two or more groups"] += len(task_groups) > 1
    ktype, kid = chosen[0][0]
    path = os.path.join(out, "reshape", "%s%d.osc" % (ktype, kid))
    pending.append((path, translation, [(k, o, s, extra[s]) for k, o, s in chosen]))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("schema")
    parser.add_argument("--live", default=(sorted(glob.glob("data/live-osm-*.osm")) or [None])[-1])
    parser.add_argument("--out")
    parser.add_argument("--blocks", type=lambda s: s.split(","), help="only these blocks, e.g. 87-9A,87-10")
    args = parser.parse_args()
    out = args.out or os.path.join("changesets", args.schema)
    if not args.live:
        sys.exit("No Live fetch found; pass --live")

    shutil.rmtree(out, ignore_errors=True)
    for sub in ("new", "conflicts", "reshape"):
        os.makedirs(os.path.join(out, sub))

    conn = psycopg2.connect(DSN, options="-c search_path=%s,public" % args.schema)
    conn.set_session(readonly=True)

    for result, name in (("N", "New"), ("C", "Conflicts")):
        counts = write_block_files(conn, out, result, args.blocks)
        print("%s: %d files, %d structures, %d parts" % (
            name, len(counts), sum(c[0] for c in counts.values()), sum(c[1] for c in counts.values())))
    written, n_groups, stats = write_reshape(conn, out, args.live, args.blocks)
    print("Reshape: %d task files of %d groups" % (written, n_groups))
    for k, v in sorted(stats.items()):
        print("  %s: %d" % (k, v))

    with conn.cursor() as cur:
        cur.execute("SELECT result, COUNT(*) FROM classification GROUP BY 1 ORDER BY 1")
        print("Classification:", ", ".join("%s %d" % r for r in cur))
    conn.close()


if __name__ == "__main__":
    main()
