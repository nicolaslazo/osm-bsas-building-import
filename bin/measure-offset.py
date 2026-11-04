#!/usr/bin/env python3
"""Measure the footprints' offset against the city's 2021 orthophoto, per block (PLAN 2.7).

Usage: .venv/bin/python bin/measure-offset.py <schema> <step>
  units     list the measurement units of the schema's city_data (run through 085)
  z17       measure every unit with at least 12 low footprints on z17 tiles
  z18       measure again on z18 tiles every unit z17 did not class as formal
  classify  give every block a class and write fixtures/offset-blocks-<date>.csv, the blocks
            not on the formal vector with the vector each one takes
Each step is resumable; tiles and per-unit tables are kept in data/offset/.

A unit is a block, or, for footprints in an asentamiento informal or without an SMP, a
cluster joined through gaps of at most 8 m. Only low footprints (altura up to 12 m) are used,
to limit relief displacement. The offset of a unit is the translation of its footprint
outlines that maximises the mean image gradient along them; it is classed by the nearest of
three vectors: formal (F), zero (0) or Villa 31 (V), within 0.6 m, else undecided (?).
Blocks at zero or the Villa 31 vector are patches and stay as delivered (decision 2026-10-25).
"""
import csv
import json
import math
import os
import sys
import time
import urllib.request
from collections import Counter
from collections.abc import Callable, Iterable, Sequence

import numpy as np
import psycopg2
from numpy.typing import NDArray
from PIL import Image, ImageDraw
from psycopg2 import extras
from psycopg2.extensions import cursor
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "offset")
URL = ("https://servicios.usig.buenosaires.gob.ar/mapcache/tms/1.0.0/"
       "fotografias_aereas_2021_caba_3857@GoogleMapsCompatible/{z}/{x}/{y}.png")
R = 20037508.342789244
MAX_ALTURA = 12.0
MIN_FOOTPRINTS = 12
SEARCH_M = 15.0
VECTORS = {"F": (-0.41, 1.86), "0": (0.0, 0.0), "V": (1.56, 2.39)}
TOL = 0.6            # classed as a vector within this distance
FAR = 1.5            # an undecided unit farther than this from every vector is unreliable
NEIGHBOUR_M = 50.0   # units with a footprint this close are neighbours
# Blocks far from every vector whose own z18 vector fits the orthophoto (checked 2026-10-31)
OWN_VECTOR = {"b54-126", "b44-2L", "b44-2R"}

Row = dict[str, str]                                   # a row of a per-unit table
Image2D = NDArray[np.float64]
Ring = NDArray[np.float64]                             # points as rows of x, y
ToPx = Callable[[float, float], tuple[float, float]]   # EPSG:3857 metres to image pixels

HEADER = ["unit", "n", "lat", "lon", "east", "north", "peak_z", "cls"]

cur: cursor  # set in __main__
downloaded = 0


# Tiles

def fetch(url: str) -> bytes:
    """The body at url, retried with a growing wait."""
    req = urllib.request.Request(url, headers={"User-Agent": "osm-bsas-building-import offset check"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception:
            time.sleep(3 * (attempt + 1))
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def tile(z: int, x: int, y: int) -> Image2D:
    """Tile x, y (rows counted from the top) as a greyscale array, downloaded once."""
    global downloaded
    path = os.path.join(OUT, f"tiles{z}", f"{x}_{y}.png")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = fetch(URL.format(z=z, x=x, y=2 ** z - 1 - y))
        with open(path + ".part", "wb") as fh:
            fh.write(data)
        os.replace(path + ".part", path)
        downloaded += 1
        time.sleep(0.1)
    return np.asarray(Image.open(path).convert("L"), dtype=float)


def mosaic(z: int, mx0: float, my0: float, mx1: float, my1: float) -> tuple[Image2D, float, ToPx]:
    """The z tiles covering the box (EPSG:3857 metres) as one image, the metres per pixel, and
    the function from EPSG:3857 metres to the image's pixels."""
    res = 2 * R / (256 * 2 ** z)
    tx0, tx1 = int(((mx0 + R) / res) // 256), int(((mx1 + R) / res) // 256)
    ty0, ty1 = int(((R - my1) / res) // 256), int(((R - my0) / res) // 256)
    img = np.block([[tile(z, tx, ty) for tx in range(tx0, tx1 + 1)] for ty in range(ty0, ty1 + 1)])

    def to_px(x: float, y: float) -> tuple[float, float]:
        return (x + R) / res - tx0 * 256, (R - y) / res - ty0 * 256
    return img, res, to_px


# Measurement

def rings(schema: str, fids: list[int]) -> list[Ring]:
    """The rings of the footprints, as arrays of EPSG:3857 points."""
    cur.execute(f"select st_asgeojson((st_dump(st_force2d(st_transform(geom, 3857)))).geom, 15) "
                f"from {schema}.city_data where ogr_fid = any(%s)", (fids,))
    return [np.array(r) for (g,) in cur.fetchall() for r in json.loads(g)["coordinates"]]


def edge_image(img: Image2D) -> Image2D:
    """Gradient magnitude of the smoothed image, scaled to its 99th percentile."""
    g = ndimage.gaussian_filter(img, 1.0)
    edge = np.hypot(ndimage.sobel(g, 1), ndimage.sobel(g, 0))
    return edge / max(np.percentile(edge, 99), 1e-9)


def outline_mask(rs: list[Ring], shape: tuple[int, ...], to_px: ToPx, margin: int) -> NDArray[np.bool_]:
    """The pixels the ring outlines cross, leaving out a margin along the border."""
    mask = Image.new("L", (shape[1], shape[0]))
    draw = ImageDraw.Draw(mask)
    for r in rs:
        draw.line([to_px(x, y) for x, y in r], fill=255, width=1)
    m = np.asarray(mask) > 0
    m[:margin], m[-margin:], m[:, :margin], m[:, -margin:] = False, False, False, False
    return m


def shift_scores(edge: Image2D, mask: NDArray[np.bool_], s: int) -> Image2D:
    """Mean edge strength under the mask moved by every shift of up to s pixels; row dy + s,
    column dx + s."""
    yy, xx = np.nonzero(mask)
    shifts = range(-s, s + 1)
    return np.array([[edge[yy + dy, xx + dx].mean() for dx in shifts] for dy in shifts])


def vertex(a: float, b: float, c: float) -> float:
    """Offset from b of the vertex of the parabola through a, b, c at -1, 0, 1."""
    den = a - 2 * b + c
    return 0.0 if den == 0 else 0.5 * (a - c) / den


def parabolic_peak(score: Image2D) -> tuple[float, float]:
    """Row and column of the score's maximum, to a fraction of a pixel; a maximum on the border
    is not refined."""
    i, j = np.unravel_index(score.argmax(), score.shape)
    n = len(score)
    fy = vertex(*score[i - 1:i + 2, j]) if 0 < i < n - 1 else 0.0
    fx = vertex(*score[i, j - 1:j + 2]) if 0 < j < n - 1 else 0.0
    return float(i) + fy, float(j) + fx


def measure(z: int, rs: list[Ring], lat: float) -> tuple[float, float, float]:
    """(east, north, peak_z): the shift the footprints need, in ground metres, and how far the
    best score stands above the median, in standard deviations."""
    k = 1 / math.cos(math.radians(lat))  # EPSG:3857 metres per ground metre
    pts = np.concatenate(rs)
    pad = (25 + SEARCH_M) * k
    img, res, to_px = mosaic(z, *(pts.min(axis=0) - pad), *(pts.max(axis=0) + pad))
    s = math.ceil(SEARCH_M * k / res)
    score = shift_scores(edge_image(img), outline_mask(rs, img.shape, to_px, s + 1), s)
    i, j = parabolic_peak(score)
    return (j - s) * res / k, -(i - s) * res / k, (score.max() - np.median(score)) / score.std()


def nearest(e: float, n: float) -> tuple[str, float]:
    """The class of the vector nearest to (e, n), and its distance."""
    return min(((c, math.hypot(e - ve, n - vn)) for c, (ve, vn) in VECTORS.items()), key=lambda cd: cd[1])


def classify(e: float, n: float) -> str:
    c, d = nearest(e, n)
    return c if d <= TOL else "?"


# Per-unit tables

def csv_path(schema: str, name: str) -> str:
    return os.path.join(OUT, f"{schema}-{name}.csv")


def read_rows(schema: str, name: str) -> dict[str, Row]:
    """The rows of a per-unit table, by unit."""
    with open(csv_path(schema, name), newline="") as fh:
        return {r["unit"]: r for r in csv.DictReader(fh)}


def write_rows(path: str, header: list[str], rows: Iterable[Sequence[object]]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        w.writerows(rows)


def units(schema: str) -> list[Row]:
    """The schema's units in bands of 0.01° latitude, west to east within a band, so units
    measured one after the other share tiles."""
    return sorted(read_rows(schema, "units").values(), key=lambda u: (round(float(u["lat"]), 2), float(u["lon"])))


def fids(unit: Row) -> list[int]:
    return [int(f) for f in unit["fids"].split()]


# Steps

def step_units(schema: str) -> None:
    cur.execute(f"""
      with f as (select ogr_fid, geom, bkey, asentamiento_informal or smp is null loose
                 from {schema}.city_data where coalesce(altura, 0) <= {MAX_ALTURA}),
      u as (select case when loose then 'c' || st_clusterdbscan(st_transform(geom, 5347), 8, 1) over (partition by loose)
                        else 'b' || bkey end unit, geom, ogr_fid from f)
      select unit, count(*), st_y(st_centroid(st_collect(geom))), st_x(st_centroid(st_collect(geom))), array_agg(ogr_fid)
      from u group by unit""")
    write_rows(csv_path(schema, "units"), ["unit", "n", "lat", "lon", "fids"],
               [[unit, n, f"{lat:.5f}", f"{lon:.5f}", " ".join(map(str, fs))] for unit, n, lat, lon, fs in cur.fetchall()])
    print("units written", flush=True)


def sweep(schema: str, z: int, todo: list[Row]) -> None:
    out = csv_path(schema, f"z{z}")
    done = read_rows(schema, f"z{z}") if os.path.exists(out) else {}
    todo = [u for u in todo if u["unit"] not in done]
    print(len(todo), f"units to measure at z{z}", flush=True)
    with open(out, "a", newline="") as fh:
        w = csv.writer(fh)
        if fh.tell() == 0:
            w.writerow(HEADER)
        for i, u in enumerate(todo):
            try:
                e, n, pz = measure(z, rings(schema, fids(u)), float(u["lat"]))
                w.writerow([u["unit"], u["n"], u["lat"], u["lon"], f"{e:.3f}", f"{n:.3f}", f"{pz:.1f}", classify(e, n)])
            except Exception as ex:
                print("fail", u["unit"], ex, flush=True)
            if i % 200 == 0:
                fh.flush()
                print(i, f"{downloaded} tiles downloaded", flush=True)
    print("done", f"{downloaded} tiles downloaded", flush=True)


def step_z17(schema: str) -> None:
    sweep(schema, 17, [u for u in units(schema) if int(u["n"]) >= MIN_FOOTPRINTS])


def step_z18(schema: str) -> None:
    not_formal = {unit for unit, r in read_rows(schema, "z17").items() if r["cls"] != "F"}
    sweep(schema, 18, [u for u in units(schema) if u["unit"] in not_formal])


def final_class(unit: str, z17: dict[str, Row], z18: dict[str, Row]) -> tuple[str, str]:
    """A unit's class, and how it was reached: F, 0, V, M (its own vector), or ? when the
    measurement settles nothing and the neighbours decide."""
    r = z18.get(unit) or z17.get(unit)
    if r is None:
        return "?", "not measured"
    if unit in OWN_VECTOR:
        return "M", "own vector"
    if r["cls"] != "?":
        return r["cls"], f"z{18 if unit in z18 else 17}"
    c, d = nearest(float(r["east"]), float(r["north"]))
    return (c, "nearest vector") if d <= FAR else ("?", "far from every vector")


def neighbour_class(around: list[str]) -> str:
    """The class of a ? unit from its measured neighbours' classes: left as delivered when every
    one is a patch, else formal."""
    if around and set(around) <= {"0", "V"}:
        return "V" if "V" in around else "0"
    return "F"


def settle_by_neighbours(schema: str, cls: dict[str, str], how: dict[str, str]) -> None:
    """Give every ? unit in offset_unit its neighbours' class. The degree box (wider than
    NEIGHBOUR_M at this latitude) lets the spatial index work."""
    cur.execute(f"""
      with q as (select o.unit, c.geom from offset_unit o join {schema}.city_data c using (ogr_fid) where o.cls = '?')
      select q.unit, array_remove(array_agg(distinct o.cls), null) from q
      left join {schema}.city_data c on st_dwithin(q.geom, c.geom, {NEIGHBOUR_M / 80000})
           and st_dwithin(q.geom::geography, c.geom::geography, {NEIGHBOUR_M})
      left join offset_unit o on o.ogr_fid = c.ogr_fid and o.cls <> '?'
      group by q.unit""")
    for unit, around in cur.fetchall():
        cls[unit] = neighbour_class(around)
        how[unit] += ", neighbours"
    extras.execute_values(cur, "update offset_unit o set cls = v.cls from (values %s) v (unit, cls) where o.unit = v.unit",
                          list(cls.items()), page_size=10000)


def block_classes(schema: str) -> list[tuple[str, str, str, int]]:
    """(block, cls, unit, classes) per block: the class of most of its low footprints, a unit of
    that class, and how many classes its low footprints have."""
    cur.execute(f"""
      with v as (select block, cls, min(unit) unit, count(*) over (partition by block) classes,
                        row_number() over (partition by block order by count(*) desc, cls) rk
                 from {schema}.city_data join offset_unit using (ogr_fid) group by block, cls)
      select block, cls, unit, classes from v where rk = 1 order by block""")
    return cur.fetchall()


def step_classify(schema: str) -> None:
    us = {u["unit"]: u for u in units(schema)}
    z17, z18 = read_rows(schema, "z17"), read_rows(schema, "z18")
    cls: dict[str, str] = {}
    how: dict[str, str] = {}
    for unit in us:
        cls[unit], how[unit] = final_class(unit, z17, z18)
    cur.execute("drop table if exists offset_unit; create temp table offset_unit (ogr_fid int primary key, unit text, cls text)")
    extras.execute_values(cur, "insert into offset_unit values %s",
                          [(f, unit, cls[unit]) for unit, u in us.items() for f in fids(u)], page_size=10000)
    settle_by_neighbours(schema, cls, how)
    write_rows(csv_path(schema, "classes"), ["unit", "n", "lat", "lon", "cls", "how"],
               [[unit, u["n"], u["lat"], u["lon"], cls[unit], how[unit]] for unit, u in us.items()])
    # A block with no low footprints is formal. Patches (0 and V) stay as delivered; an
    # own-vector block moves by its z18 vector.
    blocks = block_classes(schema)
    off = [(block, c, unit) for block, c, unit, _ in blocks if c != "F"]
    cur.execute(f"select cutoff from {schema}.data_date")
    [(cutoff,)] = cur.fetchall()
    fixture = os.path.join(ROOT, "fixtures", f"offset-blocks-{cutoff}.csv")
    rows = []
    for block, c, unit in off:
        e, n = (float(z18[unit]["east"]), float(z18[unit]["north"])) if c == "M" else (0.0, 0.0)
        rows.append([block, f"{e:.2f}", f"{n:.2f}"])
    write_rows(fixture, ["block", "east", "north"], rows)
    mixed = sum(1 for *_, classes in blocks if classes > 1)
    print(f"units by class {dict(Counter(cls.values()))}; blocks off the formal vector {dict(Counter(c for _, c, _ in off))}; "
          f"{mixed} blocks with units of more than one class; wrote {fixture}", flush=True)


STEPS: dict[str, Callable[[str], None]] = {"units": step_units, "z17": step_z17, "z18": step_z18, "classify": step_classify}

if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[2] not in STEPS:
        sys.exit(__doc__)
    cur = psycopg2.connect(host="localhost", port=6543, user="osm", password="password", dbname="osm_db").cursor()
    STEPS[sys.argv[2]](sys.argv[1])
