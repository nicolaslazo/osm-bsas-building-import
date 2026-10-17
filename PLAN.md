# Import Plan — Working List

Ordered by dependency. `[x]` decided, `[ ]` open. Vocabulary per `CONTEXT.md`.

**Scheduling note.** The wiki proposal is posted with the *final* methodology, so
it is the last step (6.6). The Import Guidelines' mandatory 14-day wait is
therefore terminal, not parallel: the earliest possible upload is the day the
plan is finished plus 14 days, plus however long community concerns take to
resolve. Informal discussion can continue in the existing forum thread
(community.openstreetmap.org/t/117029) without starting that clock.

## Phase 1 — Source keys and identity (must land before 090 re-runs)

- [x] **1.1 Normalize SMP component keys.** Strip leading zeros from `seccion`
      and from `manzana`'s numeric prefix, keep letter suffixes (`006A` → `6A`).
      Store the source spelling in a separate column.
      Evidence: `20-014` and `020-014` footprints are 7 m apart — same block,
      two spellings. 19 secciones affected. Without this, 090 cleans half-blocks.
- [x] **1.2 Stop rewriting bad SMPs to `0-0-0`.** Use NULL. Each such footprint
      becomes its own parcel, published with no cadastral tag.
      Affects 20,864 footprints (NULL 20,659 / `"0"` 202 / `Sin parcelario 2017` 3).
- [x] **1.3 Repair the slash-joined SMP.** `65-125-021/65-125-022` (6 footprints)
      splits into its two real SMPs. Currently survives 040 and is silently
      truncated by 050 to `parcela = "021/65"`.
      A second form exists (found 2026-09-12): `60-138-020B/021`, 5 footprints,
      joins two parcelas inside one SMP. It has only two hyphens, so 040's
      hyphen count never sees it. Repaired the same way.
      Decision (2026-09-26): both forms are no SMP (1.2), not split and not
      Outlier SMP. The source has no lot geometry to tell which footprint sits
      on which lot. 040 sets `smp` NULL with `smp_reason = 'slash-joined'`;
      the 11 footprints get no cadastral tag and a block key from 4.6.
      Considered and dropped: split into the two real SMPs (no way to assign
      footprints); Outlier SMP (publishes `65-125-021/65-125-022` as the tag).
- [x] **1.4 Keep `Sin parcelario 2017` as a recorded reason,** not discarded.
- [x] **1.5 Every footprint with an Outlier SMP is a separate building.** Covers
      25 code families plus the 71 ordinary-code parcels above 50 footprints:
      2,072 parcels, 40,556 footprints. The SMP is too inconsistent inside these
      parcels to indicate anything, so each footprint is a parcel by itself and
      goes through the same classification against Live as any other footprint.
      Mappers merge or split them in OSM afterwards. Existing OSM mapping is
      never overwritten automatically.
      Tags: asentamientos informales (`BEM`, 8 parcels, 8,651 footprints) get `building=yes` only —
      no `height`, because asentamiento informal alturas are likely outdated and two are
      impossible (`26-6-BEM1` 830 m, `26-6Y-BEM1` 280 m), and no cadastral tag.
      Every other outlier footprint is tagged like an ordinary one: `height` and
      the cadastral tag (3.4). Asentamiento informal geometry is published even if outdated —
      outdated beats absent.
      Flagged set: parcela is anything but an ordinary number with an optional
      letter suffix (`015`, `006A`, `01LL`, `012Ñ`), or the parcel holds more
      than 50 footprints. Largest families (parcels/footprints): all-zero
      523/11,674, `0FR` 729/9,771, `BEM` 8/8,651, ordinary-code over 50
      71/6,820, `B` 499/1,035, `PLZ` 29/764, `PT` 23/401, `NP` 45/313, then 18
      smaller families under 200 footprints each.
      Considered and dropped: grouping touching `0FR` and `PLZ` footprints into
      Simple 3D clusters routed to Conflicts.
- [x] **1.6 Repair double-encoded `Ñ`.** 29 footprints carry `Ã‘` in `smp` where
      the source meant `Ñ` (UTF-8 read as Windows-1252, then re-encoded), e.g.
      `37-56-012Ã‘`. Decode back. `Ñ` and `LL` are Spanish letters, so `012Ñ`
      and `01LL` are ordinary parcelas, not special codes.
- [x] **1.7 Stop deleting `60-026-029A`.** 040 deletes it as "an empty geom
      field", but all 10 of its footprints have valid geometry in the current
      source (checked 2026-09-13).

## Phase 2 — Geometry tolerances (re-run required after Phase 1)

- [x] **2.1 Set 090's snapping distance to `2e-6`° (~22 cm); keep the gap width
      at `2e-7`° (~2.2 cm).** Both were `0.0000002`° = 2.2 cm, commented "~20cm".
      Snap, measured on the source after 020 (before 070/080, so approximate):
      97% of vertices near a block neighbour already sit within 1 mm of its wall.
      80,538 vertices in 62,712 footprints sit 2.2–22 cm off; 57,825 of those
      64,261 neighbour pairs already share a wall, so the offset is a wall end
      stopping short of or past the neighbour's corner. At 2.2 cm these leave
      stubs and small overlaps where walls meet; at 22 cm they share nodes.
      Real 090 runs (scratch PostGIS 3.6, 2026-09-13, before Phase 1 fixes),
      footprints emptied / moved over 2 m (Hausdorff):
      snap 2.2 cm + gap 2.2 cm: 253 / 259; snap 22 cm + gap 2.2 cm: 253 / 269;
      snap 2.2 cm + gap 22 cm: 729 / 760; both 22 cm: 729 / 760.
      The snap costs almost nothing; the gap width causes the damage. A 22 cm
      gap would fill 736 enclosed gaps (131 m²) for ~476 more emptied and ~491
      more moved footprints. Gap width 0 is rejected by GEOS
      ("CoverageUnion cannot process overlapping inputs").
      Considered and dropped: gap `2e-6`° (22 cm, decided first, reversed after
      the real run); snap `1e-6`° (~11 cm) and `2e-7`° (2.2 cm).
      Rechecked after Phase 1 (2026-09-26), 22 cm against 11 cm snap through
      090–101 on the 1,723 blocks holding a split footprint (2.6), 273,734
      footprints: split after 100 2,272 / 574; emptied 813 / 628; moved over
      2 m 620 / 427; vertices 0–22 cm off a neighbour wall after 100 551 / 39,916
      (392 / 24,354 footprints). Gate 1 passes both. Kept 22 cm: halving the snap
      removes three quarters of the splits but leaves tens of thousands of walls
      that do not share nodes.
      Blocks 3.2 — node sharing only works where 090 made coordinates identical.
- [x] **2.2 Simplify with `ST_CoverageSimplify(geom, 2e-6, true)` (~22 cm, block
      boundary edges included).** 100 changes from `0.000005`; delete 095.
      Measured on 090's output (scratch run, 22 cm gap, so approximate),
      Hausdorff from 090's output / vertices (15.1 M after 090):
      22 cm all edges: 12.0 M, none over 0.5 m, 67 change area >10%;
      22 cm inner edges only: 13.1 M, none over 0.5 m, 47 >10%;
      55 cm all edges (old 100): 11.4 M, 1,288 over 0.5 m, 71 over 1 m, 3,277 >10%
      — small footprints visibly lose notches and corners;
      1.1 m (095): 10.7–12.3 M, 137k–236k over 0.5 m, 4.7k–12.9k over 1 m.
      Every variant keeps every block a valid coverage (`ST_CoverageInvalidEdges`
      empty); before 090, 560,642 footprints have invalid edges.
      Considered and dropped: 55 cm, 1.1 m, inner edges only, no simplification.
- [x] **2.3 Resolve the null-geometry case.** `500` hits `breakpoint()` on rows
      from `non_intersecting` with no geometry. Find which migration produces
      them; fix there, not in the generator.
      Decision: drop them. 090 ends by deleting every footprint whose geometry
      is NULL or EMPTY (this also removes the 19 emptied by 080), so 100 and
      later see none. No Conflicts entry, no reason recorded. The 269
      footprints 090 moves more than 2 m are kept as 090 leaves them.
      Considered and dropped: routing them to Conflicts; fixing the duplicates
      earlier (070/080).
      Source found (scratch PostGIS 3.6 run, 2026-09-13, before Phase 1 fixes):
      090 returns NULL or EMPTY for footprints it collapses, and
      `ST_CoverageSimplify` (100) turns every EMPTY into NULL. 253 collapse at
      2.1's settings (22 cm snap, 2.2 cm gap), as with the original 2.2 cm.
      19 of those were already EMPTY before 090: near-identical footprints of one
      SMP with different altura (e.g. ogr_fid 249388 / 256951, 8.0 m / 8.4 m).
      070 skips them because altura differs; 080's `ST_Contains` is true both
      ways for equal shapes, so each cuts the other away.
      (Breakdown measured at a 22 cm gap, 729 emptied: 382 narrower than 22 cm;
      347 wider, up to 34 m and 1,752 m², of which 235 are ≥99% covered by other
      footprints in the block and 87 less than half covered, 5,051 m².)
- [x] **2.4 Pin `postgis/postgis:17-3.6-alpine` and stop the runner on error.**
      `ST_CoverageClean` (090) needs PostGIS 3.6, but `docker-compose.yml` pins
      `16-3.5-alpine`, which has only `ST_CoverageSimplify` (100). `bin/run-migrations.sql`
      runs `psql -f` without `-v ON_ERROR_STOP=1`, so psql exits 0 when a
      statement fails and the next migration runs — any output built on the
      pinned image skipped 090 without a message. PostgreSQL 16 → 17 needs a
      fresh volume; the data is reloaded from GeoJSON anyway.
      Considered and dropped: the local, unpinned `17-master` image.
- [x] **2.5 Fix 070's grouping.** Footprints merge only when they are connected
      through a chain of footprints of the same parcel and the same altura that
      share a wall; otherwise they stay separate footprints (touching footprints
      of different altura become one structure at publication, 3.3). A shared
      wall is a line: footprints that meet only at a corner point are not
      connected. Altura stays in the key: a chain through a footprint of a
      different altura would still leave the merged result in separate pieces.
      Replace `grouped_shapes` with connected components over `(smp, altura)`;
      the ±2e-6 buffer goes with the move to after 100 below. Outlier
      SMP, asentamiento informal and no-SMP footprints are parcels by themselves (1.2, 1.5), so
      they never merge.
      Decision (2026-09-15, where the merge runs): after 100, not in 070. Only
      090 makes a shared wall's coordinates identical, so before it no exact
      wall test exists: `ST_ClusterDBSCAN(geom, 0, 1)` is `ST_Intersects` and
      joins corner points, and the ±2e-6 buffer turns a corner into a region
      22 cm across. After 100 the test is exact: the intersection of two
      footprints of one parcel and one altura has a linear component longer
      than zero, and a corner is a point. 3.3 already builds structures after
      100 for the same reason, so both grouping steps share one place and one
      test. Order after 100: merge same-parcel same-altura footprints, then
      build structures (3.3), then outline and parts. 070 keeps no grouping;
      080 still cuts nested footprints before 090 and keys on parcel (3.3).
      Row counts stay at the source count from 020 to 100, which simplifies
      Gate 1 (5.1). The multipart check moves with the merge: it runs on the
      merged footprints, which are single-part by construction, because the
      merge only unions footprints joined through walls.
      Considered and dropped: keep the merge in 070 with a minimum shared-wall
      length (about 0.5 m against a median wall of 5.9 m, 3.3). It still needs
      the 22 cm buffer and adds a tolerance with no measurement behind it.
      `CLAUDE.md` still says "Buildings with same SMP but
      multiple geometries become multipolygon relations"; correct it in the
      same commit. The merge step ends with a check: if any footprint is still
      multipart, it raises an error and the run stops (`ON_ERROR_STOP`, 2.4). 080 can
      still split footprints afterwards; that belongs to 3.3.
      Not yet measured: multipart rows left after the fix.
      Found state: it means to merge footprints that touch and
      share SMP and altura, but `grouped_shapes` groups every touching pair by
      `(smp, altura)` alone, so separate clusters in one parcel become one
      MultiPolygon. The source has no multipart footprints; after 070 there
      are 8,091 rows with 18,745 parts, and 7,940 of them have a part more than
      22 cm from the rest. 101 rows are `0-0-0` spanning up to 14.9 km across
      the city (gone with 1.2); 7,990 rows in 6,729 real SMPs remain.
      After 080 the counts are 8,043 real and 110 dummy: 21 rows were split into
      parts by 080's cut-out, not merged by 070.
      Needs real connected components over `(parcel, altura)`, joined by a
      shared wall, on the geometry after 100.
- [x] **2.6 Handle footprints 090 splits.** The 22 cm snap (2.1) collapses any
      part of a footprint narrower than the snap, and `ST_CoverageClean` does
      not keep a polygon's faces connected, so the footprint comes out
      multipart. Two causes:
      - neck: the source footprint narrows below 22 cm (ogr_fid 593006,
        1028590);
      - overlap: `MERGE_MAX_AREA` gives an overlap to the larger footprint,
        and the part of the smaller one beyond it is cut off as a strip
        (ogr_fid 639500).
      Decision (2026-09-26): 090 cleans each split footprint again alone, with
      the same settings. If it splits into at least as many parts alone, the
      cause is a neck: each piece becomes a footprint of its own (the largest
      keeps the ogr_fid, the others get new ones) and they form structures
      by the usual rule (3.3). Otherwise the cause is an overlap, or an overlap
      and a neck together: the footprint stays whole and multipart, is flagged
      `split_by_overlap`, and its structure goes to Conflicts with reason
      "footprint split by an overlap" (4.4). A strip is never published by
      itself. `split_footprints` records every split footprint, its cause and
      its neck pieces.
      Tested on the three examples: necks split 2 / 2 (block / alone), the
      overlap 2 / 1; two neighbours of 639500 split 4 / 1 and 6 / 1.
      Measured on the 2026-09-24 run: 2,140 footprints multipart after 100
      that 080 did not cut. Area lost at the split is about 0. Not yet
      measured: how many are necks.
      Considered and dropped: accept every split, each piece a structure;
      drop strips under a limit (e.g. 1 m²); every split footprint to
      Conflicts; snap 11 cm (2.1).
      Found (2026-09-27): 090 and 100 gave a different result on each run of
      the same input. `ST_CoverageClean` and `ST_CoverageSimplify` depend on
      the order of a block's footprints, and `PARTITION BY bkey` alone leaves
      that order undefined. Six runs of 090's cleaning on one pre-090 table:
      unordered, 255,467 footprints differed between two runs, and the split
      and NULL or EMPTY counts changed (2,743–2,756 and 3,066–3,072);
      ordered by `ogr_fid`, three runs (one from a shuffled table) were
      identical (2,752 and 3,053). 100 unordered: 69,244 footprints
      differed; ordered: identical. This explains the 2,140 against 2,744
      split count: each run drew another order.
      Decision (2026-09-27): 090 and 100 order each block by `ogr_fid`. It is
      unique, including neck pieces, and the same on each import of one
      file. No order is known to give better shapes; the order only has to
      repeat. Considered and dropped: a key from the geometry, which stays
      the same when a new file reorders its records but costs more and can
      tie.

## Phase 3 — Output model

- [x] **3.1 Replace `500`'s hand-written XML with `ogr2osm`.** Reads PostGIS
      directly (`PG:` + `--sql`), emits a plain way for single-ring polygons and
      a `type=multipolygon` relation only when interior rings exist, and
      deduplicates nodes by rounded coordinate so adjacent footprints share
      boundary nodes. Tag mapping goes in a `TranslationBase` subclass.
      Output is `.osm`, which is the correct format for JOSM-reviewed review.
      Fixes faults 1, 2 and 3 by deletion.
      Implemented (2026-09-26): 500 uses ogr2osm as a library, not as a
      command. It reads each result set from PostGIS with one query, builds
      an in-memory OGR layer per file and runs ogr2osm's `OsmData` on it. The
      translation keeps untagged rings shared but never merges two tagged
      ways or relations, so an outline and a base part of the same shape stay
      two objects on the same nodes (3.3). ogr2osm needs the system GDAL
      bindings, so 500 runs in a venv made with `--system-site-packages`,
      not with `uv run` (usage in the script's header).
      Reshape is written by 500 itself as osmChange (6.3), from ogr2osm's
      objects: the kept Live object takes the new geometry and keeps its id,
      version and tags. Provisional choices made in the rewrite, to confirm:
      - Decision (2026-09-27, height): a kept Live building takes the
        structure's `height`, replacing any Live value. Of the 409 kept Live
        buildings with a height on the 2026-09-24 fetch, 202 agree within
        0.5 m and 210 differ by more; the altura is photogrammetry-derived.
        Asentamientos informales have no altura, so a Live height stays.
        Considered and dropped: keeping an existing Live height.
      - `ref:cadastre` is added to a kept Live building only where it has
        none; an existing value is never replaced (the 47 on the 2026-09-24
        fetch all equal ours).
      - Decision (2026-09-27, old nodes): the old nodes of a replaced or
        deleted Live way are deleted in the task when they have no tags and no
        other way or relation in the Live fetch uses them; tagged nodes
        (entrances, addresses) stay. The fetch holds every way that uses a
        building node (6.2), so a node shared with a wall or a landuse area is
        kept. A node shared by two replaced Live ways is kept by both tasks and
        is unused once both are uploaded; 500 lists these in
        `reshape-orphans.tsv` and 510 deletes them before the next round,
        after checking each against current OSM. 510 is also the check that
        the process worked: a listed node used by anything 500 did not
        replace means the fetch or the tasks missed something.
        Measured (2026-09-27, 2026-09-24 fetch, before the fetch change):
        93,709 old nodes; 71,430 deleted in tasks, 625 kept for tags, 16,288
        orphaned once every task is uploaded. Simulated locally (every
        Reshape file applied to the fetch, then 510 against the result): all
        16,288 are orphaned and no other old untagged node is; no deletion
        would be refused. 568 tagged old nodes are left on their own
        (entrances, addresses, `source`). 510 against OSM that day found
        748 of the 16,288 used by 343 ways the fetch lacked: landuse 169,
        `addr:interpolation` 38, walls and fences 29, `place=city_block` 7,
        and school, park and parking areas. The same share (4.6%) of the
        71,430 would have been refused at upload (412); the fetch change
        removes this.
        Considered and dropped: moving the old nodes onto the new shape (a
        shared node moves the neighbour's wall too); deleting no node (about
        93,000 untagged nodes left in OSM).
      - A kept Live multipolygon relation keeps its id and takes the new
        rings as new member ways; its old member ways are deleted when they
        have no tags and no other relation in the fetch uses them.
      - A kept Live way whose new outline keeps a hole becomes the outer ring
        of a new multipolygon relation, which takes the tags.
      - A 1:N task file is named after the kept Live building.
      Run (2026-09-26, schema `run_20260926`, sources of 2026-09-24): the
      migrations take 13 minutes, 500 about 5. Gate 2: New 371,767, Reshape
      22,083, Conflicts 36,504 structures. Files: New 1,030 (94 secciones
      and 936 no-SMP groups, 724 MB), Conflicts 4,984 (82 MB), Reshape
      18,395 tasks (105 MB). Reshape deletes 71,430 old nodes, 2,048 ways and
      9 relations; 213 kept Live buildings are relations; 1,120 kept Live ways
      become the outer ring of a new relation. Checked on every file: no
      reference to a missing object, no duplicate node, no deleted node still
      used in the file, every kept outline within 1 cm of its structure, every
      kept Live building with its version and all its tags. Only multipart
      outlines and parts are those split by an overlap (2.6), all Conflicts.
- [x] **3.2 Set `--rounding-digits`** consistently with 2.1.
      Decision: `--rounding-digits 7`, OSM's stored precision (~1.1 cm).
      Rounding moves a point at most ~0.55 cm, below 090's 2.2 cm gap width,
      so the clean coverage survives; shared walls already have identical
      points after 090, so they still dedupe into shared nodes.
      Considered and dropped: 6 digits (moves points up to ~5.5 cm, wider than
      the gap width, so neighbours can overlap after rounding).
- [x] **3.3 Structures: nested and side-by-side different-height footprints.**
      080 subtracts a taller nested
      footprint from the shorter one, creating donuts. Alternative: Simple 3D
      without relations — enclosing footprint as `building=yes`, taller nested
      ones as overlapping `building:part=yes` ways. Keeps every object a simple
      closed way, so Replace Geometry stays loop-for-loop.
      Decision: Simple 3D with full parts, for every structure. A structure is
      the footprints of one parcel connected through shared walls (a line, not
      a corner point), directly or through a chain, whatever their altura. A
      nested footprint shares the wall of its hole, so it belongs to the
      structure around it. A lower wing or balcony beside a taller section is
      the same edifice, not a second building. A structure of one footprint is
      a plain `building=yes` way. For a structure of two or more footprints:
      - outline: `building=yes`, the union of the structure, `height` = highest
        altura in it, `ref:cadastre` (3.4);
      - each footprint: `building:part=yes`, its own altura. An enclosing
        footprint's part covers its nested footprints (the base part); where
        the structure is only an enclosing footprint and its nested ones, that
        part has the outline's shape and nodes.
      The parts fill the outline. All plain closed ways, no holes from nesting;
      an outline that surrounds a courtyard keeps that hole (3.5). The wiki
      allows parts to overlap and says the outline "should be filled with
      `building:part=*` areas". Structures are built after 100, where shared
      walls have identical coordinates (2.1).
      Example: SMP `05-035-027` (map layer "2.5 Same parcel, touching,
      different altura", case 4): 6 footprints, alturas 8.4–19.6 m, published
      as one outline (19.6 m) and 6 parts.
      Measured side by side on the scratch run after 090 (before Phase 1
      fixes, nesting approximated from the source, so approximate): 934,219
      touching different-altura footprint pairs in 244,906 parcels (998,458
      footprints). Altura difference < 0.5 m: 0.2%; 0.5–1 m: 0.4%; 1–3 m: 65%
      (mostly one storey, 2.8 m); 3–10 m: 21%; ≥ 10 m: 14%. Median wall 5.9 m.
      92% of pairs lie in a chain of 3+ footprints.
      080 stays before 090/100, because coverage cleaning needs non-overlapping
      input (`MERGE_MAX_AREA` would otherwise absorb the nested footprints).
      After 100, outline and base part = `ST_Union` of the cut enclosing
      footprint and its nested footprints. This restores holes and also notches,
      where a nested footprint touches the edge from inside, with exact shared
      nodes. 080 must key on parcel, not raw `smp` (Outlier SMP footprints are
      parcels by themselves, 1.5) and must record which footprint it cut from
      which. Expected cost: JOSM may warn that the outline and its parts
      occupy the same position, now on ~245k structures, not only the ~10k
      nested ones.
      Measured on the scratch run after 080 (matched by block, so approximate):
      12,327 footprints have holes (source: 3,375); 10,255 have a hole holding
      another footprint (12,060 holes, 16,677 nested footprints); 2,318 have
      empty holes (3.5).
      Built by 104 into `parts` (sid, ogr_fid, altura, base, geom), one row
      per footprint of every structure of two or more footprints. 090 moves
      `nested_geoms` onto neck pieces (2.6). 104 reports structures whose
      parts do not fill the outline; it does not stop the run.
      Dry run on the 2026-09-24 run (2026-09-26): 1,029,006 parts in 251,477
      structures, 4,066 base parts, 1,821 multipart parts (the 2,140 splits
      of 2.6, before 2.6 existed). 1,695 structures differ from their outline
      by over 0.01 m² (742 m² in all, at most 3.4 m²). Every difference checked is
      gaps under 1 m² enclosed between footprints: the outline fills them
      (3.5), no part covers them, and no part reaches outside the outline.
      Accepted: a 3D renderer shows a gap under 1 m² in such a structure.
      Considered and dropped: minimal S3DB (outline not filled, so 3D
      renderers lose the lower portion); keeping 080's cut-outs (~10k
      multipolygon relations, two buildings for one structure); side-by-side
      different-altura footprints as separate buildings (one edifice published
      as up to one building per altura, e.g. 6 for `05-035-027`); merging
      footprints whose altura differs only slightly (no source says which
      altura is right, so e.g. 10.4 m / 10.6 m stay two parts); corner-point
      contact as a connection.
- [x] **3.4 Cadastral tag key.** `smp=` (code) vs `ref:cadastre=` (wikitext) vs
      an authority-namespaced key. Whichever wins, update the other document in
      the same commit.
      Decision: `ref:cadastre=<SMP>` (plain value, e.g. `87-006A-015`). Wiki
      status de facto, "a unique alphanumeric ID that identifies an apartment,
      building, parcel, plot or lot in the database of a Cadastre agency";
      taginfo 2026-09-13: 32,231 uses worldwide, 47 in Argentina. `smp` has 0
      uses; `ref:catastro` 1,597 and `catastro:ref` 968 worldwide, 0 in
      Argentina. `import.wikitext` already says `ref:cadastre`; the ogr2osm
      translation (3.1) and `CLAUDE.md` change.
      Carried by every `building=yes` way (outline or one-footprint structure) only,
      never by `building:part` ways (3.3). No tag on asentamientos informales or no-SMP footprints
      (1.2, 1.5).
      Decision (2026-09-26, spelling): the value is the SMP as the source spells
      it (`40-075-003B`), after 1.6's Ñ repair, not the normalized key
      (`40-75-003B`, 1.1). The two differ on 272,207 structures of the
      2026-09-24 run; the 47 Live buildings that carry the tag use the source
      spelling. 103 writes it to `structures.ref_cadastre`. Where a parcel's
      footprints spell it differently (one parcel: `095-064A-001` /
      `95-064A-001`), the most common spelling wins.
      Considered and dropped: `smp`; an authority-namespaced key; tagging parts;
      the normalized key as the value.
- [x] **3.5 The 3,375 source footprints with interior rings** (0.24%). Route to
      Conflicts, emit relations for them only, or fill them in.
      Decision: fill every interior ring smaller than 1 m² (`ST_Area` on
      geography); every other hole stays and is published as a
      `type=multipolygon` relation (3.1). This runs as the last geometry step,
      after 100 and after 3.3's outline rebuild, so it measures the final holes.
      Holes that hold a footprint are not affected: 3.3's `ST_Union` already
      fills them. Where an enclosing footprint keeps a hole, its base part has
      the same shape, so it is a relation too.
      Measured on the scratch run after 080 (holes with no footprint of their
      block inside; before 090/100, so approximate): 2,318 footprints with
      2,671 empty holes; 102 have a hole under 1 m², most of them slivers
      narrower than 50 cm; 84 have only such holes and become plain ways;
      2,234 stay relations. Largest hole: 26,347 m² (block 27-141A, the
      Monumental stadium pitch). Map layer "Empty holes · after 080 (3.5)".
      Considered and dropped: relations for all holes (keeps sub-m² slivers
      that are artefacts, not courtyards); routing holed footprints to
      Conflicts; filling every hole (erases real courtyards and patios).

## Phase 4 — Classification

- [x] **4.1 Decide how much to precompute.** The JOSM conflation plugin already
      matches Reference against Subject layers using centroid / standard /
      Hausdorff distance plus Levenshtein tag similarity, and can replace
      Subject geometry with Reference geometry, reviewed match by match. It
      wants to classify interactively; you want the classification precomputed
      and published. Both are defensible; they cannot both be the source of truth.
      Blocks 4.2 and 4.3.
      Decision: the pipeline classifies. Run against Live at publish time, it
      puts every structure (4.2) into one result set: New (no OSM building overlaps it, 4.5),
      Reshape (one unambiguous match, 4.3) or Conflicts (with a reason, 4.4).
      Thresholds are calibrated on the Baseline beforehand. The JOSM conflation
      plugin is a review aid inside a result set, never the classifier. The
      forum post (6.6) reports counts per result set.
      Considered and dropped: pipeline splits off New only and the reviewer
      conflates everything else (all overlaps become hand work, reviewers can
      disagree); JOSM classifies everything (no counts, no Conflicts, 4.2–4.5
      moot).
- [x] **4.2 Classify and publish per structure.** A structure (3.3: a
      one-footprint `building=yes` way, or an outline with its parts) is
      classified as one shape and is never split across two result sets.
      Footprints of one parcel that share no wall are separate structures and
      may go to different result sets. 88% of parcels hold more than one
      footprint (mean 4.42), so this is consequential, not a formality.
      Exceptions, each footprint a structure of one: NULL SMP (1.2) and every
      Outlier SMP (1.5).
      Considered and dropped: classify per footprint, publish per parcel (the
      first decision). After 2.5 and 3.3 a parcel can hold unrelated
      buildings, and one disagreeing footprint held the whole parcel in
      Conflicts for a release round.
- [x] **4.3 Define the Reshape predicate.** Fanout 1:1 plus an IoU threshold
      plus a displacement bound. Calibrate on the baseline and check the IoU
      distribution is actually bimodal — if it is not, "unambiguous" is a cutoff
      you chose, not a property of the data, and the proposal should say so.
      Since 3.3: a structure of two or more footprints is one outline plus parts.
      Decision (which shapes): only `building=yes` ways (outlines and
      one-footprint structures) are compared against Live; building parts are
      never classified and follow their outline. A Reshape outline replaces the
      OSM building's geometry and its parts are added. If Live already has
      `building:part` ways inside the outline, the structure goes to Conflicts
      ("Live has parts", 4.4).
      Considered and dropped: matching every part against Live (Live seldom has
      parts here, so nearly all multi-footprint structures would become Conflicts);
      outline only with no check for Live parts (duplicates existing parts).
      Thresholds (IoU, displacement): none, see "Decision (cutoff)" below.
      Measured on the Baseline (scratch run after 090, before 100 and 3.3;
      outlines approximated by filling holes; footprints inside another
      footprint skipped as parts, 13,785). Significant overlap = at least 1 m²
      and 5% of the smaller shape. Areas on geography; Hausdorff in EPSG:5347.
      - Footprints compared: 1,164,968. No OSM contact (New): 1,048,146 (90%).
        1:1: 2,576. In a 1:N, N:1 or N:M tangle: 114,246.
      - Baseline buildings: 41,746, of which 2,745 lie outside Argentina
        (Costa Rica, Peru, Colombia, Brazil). In CABA: 39,001. 1:1: 2,576.
        Tangled: 31,844. No footprint (OSM-only): 4,581, about 1,900 of them
        in Villa 1-11-14 (Bajo Flores), 50 m or more from any footprint.
      - Tangled footprints concentrate by seccion: 06 (80%), 04 (67%),
        14 (60%), 07 (59%).
      - Footprint centroids sit about 0.55 m south of their 1:1 OSM building
        (median, IoU ≥ 0.6); about 0 east–west.
      - 1:1 IoU is not bimodal: counts rise steadily to a peak at 0.7–0.8,
        then fall (per 0.05 bin from 0.5: 160, 160, 192, 202, 234, 234, 200,
        181, 138, 54). "Unambiguous" is therefore a chosen cutoff; the forum
        post must say so.
      - OSM building vs the union of its footprints (pure N:1, 10,303 OSM
        buildings): median IoU 0.56–0.64 whatever the footprint count; only
        15% reach 0.8. Merging footprints does not make OSM shapes match.
      - 1:1 displacement: centroid median 2.15 m, p95 11.6 m; Hausdorff
        median 3.9 m, p95 24.3 m. At IoU ≥ 0.8: centroid p90 ≤ 2.5 m,
        Hausdorff p90 ≤ 5.1 m.
      - 1:1 footprints passing: IoU ≥ 0.6 & Hausdorff ≤ 10 m: 1,377;
        ≥ 0.7 & ≤ 8 m: 998; ≥ 0.8 & ≤ 5 m: 537; ≥ 0.8 & ≤ 3 m: 476;
        ≥ 0.9 & ≤ 3 m: 182. Per footprint; not remeasured per structure (4.2).
      - N:M at the 5% rule: 3,693 chains, 74,913 footprints, 23,547 OSM
        buildings; largest chain 1,954 footprints / 1,613 OSM. Chains form
        because OSM and the city divide buildings at different walls: of
        27,817 footprints touching more than one OSM building, the second
        overlap is a median 18% of the footprint, and 5,291 have no OSM
        building holding half of them.
      Decision (linking): a footprint and an OSM building are linked only when
      their overlap is at least 1 m² and more than 50% of the smaller shape
      ("link by majority"). Groups are connected components of links. This
      breaks most N:M chains into 1:1 and N:1 groups. Remaining 1:N and N:M
      groups go to Conflicts (1:N amended below: merged when at most one OSM
      building has tags).
      Considered and dropped: linking at 5% (N:M chains of up to 1,954
      footprints, all Conflicts); majority of the footprint only (misses
      small OSM buildings inside a large footprint, which would become New
      and be added on top of them).
      Measured with majority linking (Baseline, per group):
      - 1:1: 9,605 groups, median IoU 0.53, Hausdorff 4.3 m. N:1: 18,267 OSM
        buildings / 78,199 footprints, median IoU 0.64, Hausdorff 4.2 m.
        1:N: 749 groups (749 footprints, 2,009 OSM). N:M: 953 groups (3,401
        footprints, 3,021 OSM).
      - Groups passing (1:1 / N:1): IoU ≥ 0.9 & ≤ 3 m: 253 / 248;
        ≥ 0.8 & ≤ 5 m: 966 / 2,099; ≥ 0.7 & ≤ 8 m: 2,167 / 5,996;
        ≥ 0.6 & ≤ 10 m: 3,631 / 10,325; failing all: 5,974 / 7,942.
      - 25,725 footprints in 1:1/N:1 groups (14,818 groups) also overlap a
        neighbouring OSM building they are not linked to: median 6.7 m²,
        p90 31.3 m².
      - Footprints touching OSM but linked to nothing: 28,680 (largest
        overlap < 5 m²: 10,615; < 10% of the footprint: 3,694; 10–30%:
        7,514; 30–50%: 6,857). OSM buildings touched but linked to nothing:
        1,597.
      Decision (cutoff; narrowed by the neighbour, 1:N and N:1 decisions
      below): every 1:1 and N:1 group is Reshape, with no IoU or
      displacement cutoff. The city footprints are photogrammetry-derived and
      more accurate than hand-drawn OSM shapes, so a poor overlap means OSM is
      wrong, not that the match is. This includes groups where a small OSM
      building sits inside a much larger footprint. The forum post states the
      rule (majority link, fanout only) instead of a threshold.
      Considered and dropped: IoU ≥ 0.8 & Hausdorff ≤ 5 m (966 1:1 / 2,099
      N:1); IoU ≥ 0.6 & ≤ 10 m (3,631 / 10,325); both route the rest to
      Conflicts as low-overlap matches.
      Measured after this decision (Baseline; contact = overlap ≥ 1 m²):
      - Footprints touching OSM but linked to nothing (28,680): 26,138 touch
        only OSM buildings that are Reshape, so the overlap disappears once
        those are replaced; 2,542 touch an OSM building that stays (1,109 an
        unlinked one, median 13.4 m²; 1,433 one in Conflicts, median 7.6 m²).
      - Reshape footprints also touching a neighbouring OSM building (25,725):
        22,514 neighbours are Reshape too, so the overlap disappears; 3,211
        neighbours stay (median 8.0 m², p90 38.2 m², 1,129 under 5 m²).
      Every count above is per footprint, measured before 3.3 grouped
      side-by-side footprints into structures.
      Measured per structure (Baseline, 2026-09-13; structures built on the
      scratch run after 090, before Phase 1 fixes and 100; SMP and altura
      rebuilt from `tejido.geojson`; outlines keep holes ≥ 1 m², where the
      per-footprint run filled all holes; nested footprints included):
      - 1,199,682 footprint pieces (multipart rows split) form 424,114
        structures: 172,657 of one piece, 76,760 of 2, 127,042 of 3–5,
        47,113 of 6–20, 542 of more than 20. 22,433 same-parcel pairs meet
        only at a corner and are not joined.
      - No contact: 371,675. Contact under 1 m² only: 1,539.
        1:1: 19,382 groups (per footprint 9,605), median IoU 0.57.
        N:1: 4,210 OSM buildings / 14,860 structures (18,267 / 78,199),
        median IoU 0.67. 1:N: 2,795 groups / 7,341 OSM (749 / 2,009): one
        outline now holds most of several small OSM buildings. N:M: 420
        groups / 1,267 structures / 1,403 OSM (953 / 3,401 / 3,021).
        OSM buildings to Reshape: 23,592 (27,872); in 1:N or N:M: 8,744
        (5,030).
      - Unlinked touching structures: 12,596 (per footprint 28,680, of which
        10,615 had a largest overlap under 5 m² and the percentage buckets
        above cover the rest). 10,330 touch only Reshape OSM buildings;
        1,254 touch an unlinked OSM building (median 24.4 m²); 1,012 touch
        one in 1:N or N:M (median 10.9 m²).
      - Reshape structures also overlapping a neighbouring OSM building:
        12,567; 8,916 only neighbours that are Reshape too; 3,651 at least one
        neighbour that stays (5,274 pairs, median 12.1 m², p90 58.9 m²,
        1,341 under 5 m²).
      - "B overlaps X" footprints (26,121): 10,632 now in the same structure
        as their linked neighbour (7,145 of those structures Reshape, 3,487
        in 1:N or N:M); 14,359 are on another parcel and stay unlinked;
        1,130 are linked on their own.
      - N:1 detail: N = 2 in 2,587 groups, 3–5 in 1,153, 6–20 in 417, over
        20 in 53. 472 groups lie in one parcel; 3,738 span several. 1,766 of
        the 4,210 OSM buildings (42%) carry tags beyond `building=yes`: name
        843, addr:street 679, building:levels 598, height 323, amenity 241,
        shop 193; `building` values other than yes: 1,177.
      Artefacts: scratch DB tables `st_*`, scratchpad scripts `m43s-*`.
      Decision (unlinked touching): a structure that overlaps a Live building
      by at least 1 m² (any overlap since 4.5) but has no link goes to Conflicts ("overlaps an OSM
      building without a link", 4.4). It is never New as-is, because it would
      overlap that building. In round 1 all 12,596 are held (6.3). The 10,330
      that touch only Reshape OSM buildings touch nothing once round 1 is
      processed, so round 2 classifies them as New with no manual work;
      784 of them touch a group held by the neighbour rule below, so 9,546
      become New (`m43s-12-q1-held.py`). The
      2,266 that touch an OSM building that stays (unlinked, or in 1:N or
      N:M) stay in Conflicts in round 2 and a person decides each one.
      Considered and dropped: publishing them as New in round 1 (adds
      overlapping buildings to OSM).
      Decision (neighbour that stays): if any structure of a 1:1 or N:1 group
      overlaps by at least 1 m² (any overlap since 4.5) an OSM building it is not linked to and that
      stays (unlinked, in Conflicts, or in a held group), the whole group goes
      to Conflicts ("overlaps an OSM building that stays", 4.4). Holding is
      repeated until nothing changes, because a held group's OSM building
      stays too. Rule for every result set except Conflicts: it never adds an
      overlap with an OSM building to OSM. No tolerance: the median overlap
      (12.1 m²) is not a rounding artefact.
      Measured (Baseline, per structure, `m43s-11-hold.py`): of 23,592
      Reshape groups, 5,568 are held (24%; 7,287 structures; 4,598 1:1, 970
      N:1): 3,440 by their own overlap, 2,128 by the chain, 17 iterations.
      Held groups wait for round 2, where a person fixes the structure and
      the OSM building together.
      Considered and dropped: Reshape anyway (JOSM crossing-buildings
      warnings inside Reshape, and the reviewer edits the neighbour by hand);
      a tolerance (under 5 m²: 4,295 held; 10 m²: 3,196; 20 m²: 1,978), which
      adds a threshold where 4.3 chose none.
      Decision (1:N): a 1:N group where at most one OSM building has tags
      beyond `building=yes` (any other key, or another `building` value) is
      Reshape by merge. The structure replaces the geometry of that tagged
      building, or, if none has tags, of the one with the largest overlap; it
      keeps its id, history and tags. The other OSM buildings of the group
      are deleted. A 1:N group with two or more tagged OSM buildings goes to
      Conflicts, because their tags can clash. The neighbour rule above still
      applies to merged groups.
      Measured (Baseline, per structure, `m43s-13`–`m43s-15`): 2,795 1:N
      groups, 7,341 OSM buildings; N = 2: 1,914, 3–5: 788, more: 93. 88% of
      those OSM buildings touch another of the same group. In 1,351 groups
      every OSM building covers only its own footprints (1,326 of them with
      more than one altura): OSM drew sections of one edifice as buildings.
      Median IoU, structure vs union of its OSM buildings: 0.62. Tagged OSM
      buildings per group: none 1,975, one 215, two or more 605. Merged:
      2,190 groups (78%).
      Recount with merged 1:N as Reshape (`m43s-16-recount.py`; supersedes
      the held and round-2 counts above): Reshape 25,782 groups (1:1 19,382,
      N:1 4,210, 1:N 2,190), 36,432 structures, 29,376 OSM buildings. The
      neighbour rule holds 5,395 groups (20.9%; 2,799 by their own overlap,
      2,596 by the chain; 1,101 of them 1:N), 6,810 structures. Unlinked
      touching structures: 10,840 touch only Reshape OSM buildings, 760 of
      those touch a held group, so 10,080 become New in round 2 and 2,516
      stay in Conflicts.
      Considered and dropped: all 1:N to Conflicts (2,795 structures by hand
      for mostly untagged rough copies); merge every 1:N and copy all tags
      (needs a rule to pick between clashing values).
      Decision (N:1): the structure with the largest overlap keeps the OSM
      way (id, history, tags); the group's other structures are added as new
      ways, and no tags are copied to them. If the OSM building has tags
      beyond `building=yes` and its structures lie on more than one parcel,
      the group goes to Conflicts: its `name`, `addr:*` or `shop` can describe
      a different lot than the one that keeps the way.
      Measured (Baseline, per structure, `m43s-16`, `m43s-17`): 4,210 N:1
      groups; OSM building untagged / one parcel 302, untagged / several
      1,699, tagged / one parcel 170, tagged / several 2,039 (Conflicts). The
      largest structure holds a median 62% of the group's overlap, at least
      half in 82% of groups.
      Considered and dropped: tags on the kept way for every N:1 group (tags
      can land on the wrong lot); copying tags to every structure
      (duplicates `name`, `amenity` and `addr:*` onto neighbouring lots).
      Recount with both decisions (`m43s-18-recount.py`; supersedes the
      recount above): Reshape 23,743 groups (1:1 19,382, N:1 2,171, 1:N
      2,190), 27,521 structures, 27,337 OSM buildings. The neighbour rule
      holds 5,691 groups (24.0%; 3,036 by their own overlap, 2,655 by the
      chain), 6,596 structures. Unlinked touching structures: 9,076 touch
      only Reshape OSM buildings, 781 of those touch a held group, so 8,295
      become New in round 2 and 4,301 stay in Conflicts.
      Artefacts: scratch DB tables `baseline`, `cal_fp`, `cal_pairs`,
      `cal_fan`, `cal_group`, `cal_link`, `cal_star`.
- [x] **4.4 Enumerate the Conflicts subtypes.** `1:N` with two or more
      tagged OSM buildings, `N:1` with a tagged OSM building over several
      parcels, `N:M`
      tangle, invalid geometry, Live has parts (4.3), overlaps an OSM
      building without a link (4.3), overlaps an OSM building that stays
      (4.3). Every feature
      carries its reason. (has-hole dropped by 3.5: holes are filled or
      published as relations. `N:1` merge and low-IoU near-match dropped by
      4.3: every 1:1 group and every N:1 group without that tag risk is
      Reshape.)
      Decision (2026-09-13): these seven subtypes are the list. It is not
      closed: a new cause found later is added as a new subtype.
      Added (2026-09-26): footprint split by an overlap (2.6). It is decided
      before any Live check, and it holds the structure's whole link group.
      Decision (reasons, 2026-09-13): reasons are not published. No tag, no
      side file. The pipeline's database keeps every reason that applies to
      each structure; a question about a rejection is answered with a query.
      Considered and dropped: a `fixme` tag on each Conflicts structure
      (JOSM reports `fixme` only at the "Other" level, hidden by default in
      the validator and at upload, so it can reach OSM unseen); a `.geojson`
      file of reasons next to each Conflicts file (no tooling yet).
      Implemented (2026-09-27): `classification.reasons` and
      `live_groups.reasons` are text arrays holding every reason that applies,
      NULL for New and Reshape. The neighbour rule (140) also marks groups
      already in Conflicts, so "overlaps an OSM building that stays" is
      recorded beside their other reasons. On run_20260926 no result changed:
      of 36,504 Conflicts structures, 32,299 have one reason, 3,823 two and
      382 three.
      Decision (OSM-only, 2026-09-13): dropped. The import covers only
      buildings the dataset has. An OSM building with no structure beneath it
      is not classified, not listed, not counted and never changed.
      Considered and dropped: OSM-only as a Conflicts subtype in each block's
      Conflicts file; one city-wide list linked from the forum post.
- [x] **4.5 Fix 110's SMP-level exclusion** to match 4.2 (currently `smp NOT IN`,
      which drops a whole parcel on any contact).
      Decision (2026-09-13): replace 110, do not patch it. A classification
      step writes one result set and one reason per structure (4.2–4.4); 500
      reads it. The new step must not use `NOT IN` over a nullable SMP and
      must not count a shared wall with no overlap as contact.
      Found (2026-09-13):
      - 110 only removes. It has no Link, Reshape or Conflicts, so 4.1–4.4
        replace it; a patch to the exclusion is not enough.
      - After 1.2, `smp` can be NULL. If one NULL-SMP footprint touches Live,
        the `NOT IN` list holds NULL, the test is never true, and the view is
        empty: 500 writes nothing. On the Baseline 4,046 no-SMP structures
        touch an OSM building.
      - `ST_Intersects` counts a shared wall or corner with no overlap as
        contact. 4.3 counts overlap of at least 1 m².
      - Overlaps under 1 m² are not decided by 4.3 (`m45-1-under1.py`):
        1,539 structures touch Live only under 1 m² (median largest overlap
        0.36 m²; under 0.1 m²: 383), 527 of them a building that stays; 434
        structures in published Reshape groups (424 groups of 18,052) overlap
        a building that stays by under 1 m².
      - 090's snap (2.1) does not remove these: `ST_CoverageClean` runs on
        `city_data` per block and never sees OSM. 3.5's 1 m² is for holes.
      - Width of the 6,170 overlaps under 1 m² (largest inscribed circle,
        EPSG:5347, `m45-2-width.sql`): median 16 cm wide, 2.3 m long; under
        2 cm 438, 2–10 cm 1,559, 10–22 cm 1,978, 22–50 cm 1,624, over 50 cm
        571. Per structure (`m45-3-width-sets.py`): of the 1,539, 939 have
        every such overlap under 22 cm wide; of the 527 touching a building
        that stays, 304; of the 424 Reshape groups, 304 (120 have one 22 cm
        or wider).
      Decision (contact): any overlap between a structure and a Live building
      is contact, whatever its area. It applies to "overlaps an OSM building
      without a link" and "overlaps an OSM building that stays" (4.3). A
      shared wall or corner with no overlap is not contact. Overlap is
      measured after both shapes are rounded to the output grid (3.2), so a
      difference that exists only below that precision is not an overlap. A
      link still needs at least 1 m² and a majority (4.3). This follows the
      4.3 rule: no result set except Conflicts adds an overlap to OSM.
      Recount (Baseline, `m45-4-recount.py`; before, `m43s-18`): held Reshape
      groups 6,569 of 23,743, 27.7% (5,691, 24.0%); published in round 1
      17,174 (18,052). Unlinked touching structures 14,135 (12,596): 9,151
      become New in round 2 (8,295), 4,984 stay in Conflicts (4,301).
      Considered and dropped: overlaps under 1 m² do not count (adds about
      2,000 overlaps to OSM); snap structure walls within 22 cm onto Live
      buildings that stay (saves about 530 Conflicts). Snaps occur only among
      city footprints: the pipeline never changes city geometry to match OSM,
      a less accurate dataset.
- [x] **4.6 Decide the review unit** — block or footprint. Now unblocked: venue
      is files first. Shared nodes make a block the natural unit.
      Found (2026-09-13; scratch, before Phase 1 fixes and 100,
      `m46-1-blocks.sql`, `m46-2-noblock.sql`, `m46-3-noblock-knn.sql`):
      - 11,610 blocks. Structures per block: median 34, p90 55. Vertices per
        block: median 1,209, p90 2,252, p99 3,538. Largest real blocks:
        `26-006Y` 2,165 structures (24,005 vertices), `26-006Z` 1,884,
        `26-001Z` 1,435.
      - Footprints with no SMP (1.2) have no block: 12,611 footprint pieces
        (all one-footprint structures), spread 19 km across the city. 090
        and 100 partition by `(seccion, manzana)`, so they are cleaned as one
        partition, never with the footprints beside them.
      - 405 of them lie within 22 cm (090's snap) of footprints of exactly one
        real block (none of two or more); 343 overlap such a footprint by more
        than 0.01 m². These overlaps are inside the city data and survive 090.
      - Distance to the nearest real-block footprint: 0 m 395, up to 5 m 282,
        5–20 m 663, 20–50 m 1,905, over 50 m 9,366 (median 105 m, max
        441 m). By nearest seccion: 78 5,012, 3 3,613, 15 1,600.
      - Also affects 4.4: OSM-only buildings and features with two reasons
        need a place in the review unit.
      Decision (no-SMP footprints, 2026-09-13): no-SMP footprints connected
      through gaps of at most 22 cm (090's snap, `2e-6`°) form a group. A
      group with any footprint within 22 cm of a real block's footprint
      joins that block whole, so it is cleaned with its neighbours and the
      343 overlaps go. A group that reaches no block is a block by itself.
      090 and 100 partition by this block key, not by `(seccion, manzana)`.
      A group that reaches two blocks does not occur on the Baseline; if one
      appears, the run stops (5.2 check).
      Measured (`m46-4-noblock-clusters.sql`): 1,257 groups; one footprint
      520, 2–10 487, 11–100 234, 101–1,000 16, none larger. Largest: 783
      footprints (8,148 vertices, 599 m across) at -34.6735, -58.4891; the
      next ones are near -34.585, -58.378. 71 groups reach a block (37 of
      them with 1,234 footprints farther than 22 cm, which join with their
      group); none reaches two. 10,972 footprints stay in groups of their own.
      Considered and dropped: nearest block at any distance (splits one
      group over several block files); one partition for all no-SMP
      footprints (the current state).
      Decision (files, 2026-09-13): one file per result set per group of
      blocks. A New or Reshape file holds 5 blocks; a Conflicts file holds 1
      block. A block with no feature in a result set adds nothing to that
      result set's files. Blocks go into files in key order, 5 consecutive
      blocks of one seccion (as 500's `MANZANAS_PER_FILE = 5` does today,
      but never across secciones); no-SMP groups that are blocks by themselves
      are files of their own, in the same way.
      Considered and dropped: 1 block per file for every result set.
      Conflicts files carry no reasons (4.4).
      Decision (2026-09-15, New files): one New file per seccion, not 5 blocks.
      Conflicts stays at 1 block. New is 371,675 of the 424,114 structures
      (88%), which no reviewer opens block by block, and the import account
      uploads it itself (6.3), so the file only needs to open in JOSM and to
      give the upload a restart point.
      Decision (2026-09-24, Reshape files): superseded. Reshape moves to a
      MapRoulette cooperative challenge, one task per Live building, not to
      block files (6.3).
      Measured on the source (`s61-seccion.py`, scanned line by line, no DB):
      94 secciones, 1,386,616 footprints, 15,710,638 vertices, plus 20,870
      footprints with no SMP. Vertices per seccion: median 161,435, p90
      282,816, max 379,579 (seccion 15, 2.4% of the city). The 15.7 M agrees
      with 2.2's 15.1 M after 090, so the scan is sound.
      Scaled to the output (12.0 M vertices after 100, at most 1.45 M ways, New
      = 88%), the largest New file holds about 34,000 ways and 254,000 nodes
      before 3.1's dedup, about 288,000 elements and 35 MB; the median one about
      13,000 ways, 109,000 nodes, 122,000 elements and 15 MB. A seccion holds
      about 123 blocks. No-SMP groups keep their own files (above).
      Duplicate nodes across file borders do not occur: a block is bounded by
      streets, so buildings of different blocks share no wall, and 090 and 100
      already partition by block.

## Phase 5 — Verification

- [x] **5.1 Choose the hard gates.** Two gates proposed: one after the city-side
      migrations (runnable today), one after classification (publish time only).
      Decision (2026-09-13): two hard gates. A failed check stops the run and
      no file is written.
      - Gate 1, after 100 and the merge that follows it (2.5; no Live needed):
        every block is a valid coverage
        (`ST_CoverageInvalidEdges` empty); no NULL or EMPTY geometry; no
        multipart footprint except those 080 cut (`nested_geoms` container)
        and those split by an overlap (2.6); footprint counts reconcile per
        migration. Counts hold at the source count from 020 to 100 except at
        090, which drops NULL and EMPTY geometry (2.3) and adds neck pieces
        (2.6); they fall at the merge (2.5).
      - Gate 2, after classification, before 500: every structure is in
        exactly one result set; no New structure overlaps a Live building;
        no structure is split across files.
      Every other check in 5.2 and 5.3 writes a report and does not stop the
      run. Stops already decided elsewhere stay: psql `ON_ERROR_STOP` (2.4),
      the merge's multipart check (2.5), a no-SMP group reaching two blocks
      (4.6).
      Considered and dropped: report only, with no gate.
      Implemented (2026-09-27, count reconciliation): a ledger table,
      `footprint_counts`. The import writes the GeoJSON feature count
      (`ogrinfo`) and the imported count; 020, 030, 090 (neck pieces added,
      NULL or EMPTY dropped, the latter counted from `cleaned_away`) and 101
      each append what they removed and added and the count after them
      (`log_footprints`, 005). Gate 1 stops the run when a row is not the
      row before it less its removals plus its additions, or when the count
      now differs from the last row. Migrations that only update rows
      cannot change the count; a change between two rows fails at the next
      one. Test on the 09-24 inputs: 1,386,616 source features, 11,713
      removed by 020, 30 by 030, 2,557 neck pieces added and 3,063 dropped
      by 090, 164,774 merged away by 101, 1,209,593 at Gate 1. One
      footprint deleted before Gate 1 stopped the run.
- [ ] **5.2 Build the city-side integrity suite.** Count reconciliation per
      migration; coverage validity (`ST_CoverageInvalidEdges`); validity and
      emptiness; Hausdorff displacement and area drift; vertex counts and
      degenerate rings; re-slivering after simplification; self-overlap within
      and across blocks; hole sanity; CABA bbox containment; altura
      distribution; SMP conformance; SMP spatial coherence; key-normalization
      consistency; block-partition integrity; idempotency of a second run.
- [ ] **5.3 Build the live-side suite.** Match-fanout histogram; IoU
      distribution; centroid displacement and area ratio; tag richness on
      Reshape candidates; footprints already carrying the cadastral tag
      (idempotency against OSM itself across batches);
      baseline-vs-live drift.
      Found (2026-09-13): in round 2 (6.3) every round-1 structure is a Live
      building, and no rule recognised it. A one-footprint structure links
      1:1 to its own upload and becomes a Reshape that changes nothing; each
      of the 251,457 structures with parts (of 424,114) meets its own parts
      ("Live has parts", 4.4) and goes to Conflicts.
      Decision (2026-09-13, already imported): before classification, a
      structure already in Live is skipped with no change. Match by
      `ref:cadastre` first; when the tag cannot decide, match by the same
      shape at the 7-digit output grid (3.2). The tag cannot decide for the
      20,547 structures with no tag (12,406 no SMP, 8,141 asentamiento informal) or for the
      163,885 structures that share their SMP with another structure (61,343
      SMPs); there the tag only narrows the Live buildings to compare.
      Considered: shape only.
      Decision (2026-09-13, tag match with a different shape): skipped. The
      tag identifies the building; a mapper's edit after upload stays, and a
      pipeline fix between rounds creates no changes. Considered and dropped:
      apply 4.3, which would replace the mapper's edit with our shape.
      The Baseline has no `ref:cadastre` or `smp` column, so a tag match can
      only be our own upload.
      Deferred (2026-09-15): how a structure is recognised where the tag
      cannot decide stays open until round 1 is published. Two candidates: the
      same shape at the 7-digit grid (above), or a geometric test with no tag
      at all. A geometric test must be symmetric: the link rule measures the
      overlap against the smaller shape (4.3), where a small structure inside a
      large OSM building is 100%, so the test would be IoU >= 0.9. Against the
      Baseline only 253 of 9,605 1:1 groups and 248 N:1 groups reach IoU >= 0.9
      with a Hausdorff distance of 3 m or less, so such a test costs about 500
      Reshape groups in round 1. A geometric test alone also cancels the tag
      decision above: a mapper who moves a wall 3 m drops under 0.9 and gets our
      shape back. A union of both tests would cover the 20,547 structures with
      no tag as well. Decide with the round-1 result in hand.
      Decision (2026-09-27, where the tag cannot decide): the import account.
      Round 1 now runs in two steps (6.3), so the decision is needed between
      the New upload and the Reshape run, not after round 1. A Live building
      whose last editor is the import account is our upload, unedited since;
      the structure it links to (4.3) is already in Live. The fetch holds each
      object's last uid and changeset (`out meta`), so no tag and no shape
      test is needed. A building a mapper edits between the upload and the
      fetch is not recognised this way; the tag rule still skips it where the
      SMP names one structure. Considered and dropped: the same shape at the
      7-digit grid, and IoU >= 0.9 (above); the list of way ids the upload
      returns, which also recognises edited buildings but needs the upload
      script to keep it. To count the edited ones, 125 reports the structures
      left with a Live building of IoU >= 0.9; the run before the upload gives
      the count to compare.
      Found (2026-09-27): the tag is not only our own upload. In the Live
      fetch of 2026-09-27, 47 buildings carry `ref:cadastre=45-098-0000` and
      `source=GCBA - BA Data`, imported by hand by ignaciolep in July 2026 from
      the same dataset. They are skipped by the tag rule, as decided above.
      Implemented (2026-09-27): 125 builds `already_in_live` (sid and which
      rule) and removes those structures from `structure_shapes` and
      `contacts`, so 130-160 never see them; their Live buildings stay, as
      OSM buildings that stay. `bin/import-datasets.sh` keeps each Live
      building's uid and stores the import account's uid from `IMPORT_UID`
      (unset before the account uploads anything). Gate 2 adds the skipped
      structures to its count. Tested on `run_20260927` (no import account
      yet, rolled back): 47 structures skipped by the tag rule, all 1:1
      Reshape before; 513 structures left with a Live building of IoU >= 0.9.
      Where several structures share an SMP, a Live building with the tag
      must also link to the structure.

## Phase 6 — Publication

- [x] **6.1 Freeze the baseline.** Move `data/live-osm-data.geojson` to
      `fixtures/live-osm-2025-10-05.geojson`. Never derive a result set from it.
      Done (2026-09-27): moved; `*.geojson` keeps it out of git.
- [x] **6.2 Script the live fetch** with `out meta;` as raw `.osm`. A hand-run
      Overpass export at the last moment is the step most likely to differ from
      what you calibrated against.
      The query must also fetch `building:part` ways and relations (4.3's
      "Live has parts" check). The Baseline query did not: of its 41,747
      features, all carry `building`; none is a part only.
      The query must be bounded to the CABA boundary, not a bbox or name
      search: the Baseline holds 2,745 buildings outside Argentina.
      Script (2026-09-27): `bin/fetch-live.sh`. Besides buildings and parts,
      their members and nodes, it fetches (without their nodes) every way
      that uses one of those nodes and every relation that holds one of those
      ways, so 500 knows what else uses an old node or way (3.1). `BBOX=`
      fetches a small area for tests. The import filter keeps only buildings
      and parts, so `live_buildings` does not change. Run on the whole city
      on 2026-09-27 (`data/live-osm-2026-09-27.osm`, `run_20260927`); the
      2026-09-24 fetch used the old query.
      Import (2026-09-26): `bin/osmconf-buildings.ini` keeps every tag and the
      version of each Live building (`[multipolygons]`: `osm_version=yes`,
      empty `ignore`). GDAL's default list dropped `source`, `note`, `fixme`
      and others: 1,779 Live buildings on the 2026-09-24 fetch carry one of
      the first three, 212 of them with nothing else beside `building=yes`,
      which 4.3 then treated as untagged. Reshape needs the version.
- [x] **6.3 Publish New and Conflicts as files; Reshape as a MapRoulette
      cooperative challenge.** New and Conflicts files linked from the OSM
      Argentina forum thread (4.6: 1 seccion per New file since 2026-09-15,
      1 block per Conflicts file). Reshape has no block file since 2026-09-24;
      it is one MapRoulette task per cluster of neighbouring Reshape groups
      (since 2026-09-27; before, one per Live building).
      Decision (2026-09-15, who uploads New): the import account (6.7), in one
      scripted run over the 94 seccion files, after the admins consent (6.6).
      A changeset holds at most 10,000 elements, so New is about 840 changesets
      (about 8 M elements: 1.27 M ways and 6-8 M nodes), not one. One account,
      one date range and one comment on every changeset keep the revert a
      single query (6.8).
      Decision (2026-09-24, Reshape venue): a MapRoulette cooperative change
      challenge, one task per Live building (23,592 tasks, 4.3's Reshape
      groups). The task unit was changed on 2026-09-27: see the decision on
      duplicate nodes between Reshape tasks below. A cooperative change task carries a JOSM `.osm` or `.osc` file
      that MapRoulette loads into the mapper's editor as work in progress on
      top of OSM; the mapper checks it, adjusts it if needed, and uploads it
      from their own account, the same as any other edit.
      Decision (2026-09-24, whose account uploads Reshape): the mapper's own
      personal OSM account, not a dedicated import account. Each task is one
      Live building that a person individually reviewed and, where needed,
      adjusted in JOSM before upload; that is an ordinary edit, not a
      mechanical import, so the Guidelines' dedicated-account requirement
      (aimed at edits nobody reviewed one at a time) does not apply to it. 6.7
      stays the import account for New alone.
      Only JOSM opens cooperative tasks (Rapid is not available for them).
      500 must emit the change file with each Live way's id and version, which
      6.2's `out meta` already fetches; `mr-cli`'s default splitting makes one
      task per top-level modification, and a Reshape group's replaced Live way
      is one such modification, so no `--bijective` grouping is needed
      (superseded on 2026-09-27: a task now holds a cluster of groups and
      needs `--bijective`). Round 2
      waits until volunteers process round 1's 23,592 tasks, unlike New, which
      moves at the import account's own pace.
      Considered and dropped: 5-block JOSM files uploaded by the import
      account, as 4.6 first decided. Reshape changes buildings other mappers
      drew, so per-building review and MapRoulette's task tracking (no two
      mappers finishing the same building) outweigh keeping the revert to one
      account for this result set.
      Considered and dropped (2026-09-24): New as a MapRoulette cooperative
      change challenge. A change task carries a JOSM `.osm` or `.osc` file that
      MapRoulette loads into the mapper's editor on top of OSM, where the
      mapper checks it, adjusts it and uploads it. But only JOSM opens these
      tasks (Rapid is not available for cooperative challenges), the upload
      goes from each mapper's own account, so the revert is no longer one
      query and each mapper needs an import account, and `mr-cli` makes one
      task per top-level way by default (about 1.27 M) or one per file with
      `--bijective` (up to 11,610 block tasks). Round 2 would also wait for
      volunteers to process 371,675 structures.
      Release rounds: each round fetches Live (6.2), runs the whole pipeline
      and classifies. Round 1 publishes New and Reshape and holds Conflicts.
      When round 1 is processed, round 2 fetches Live again, reruns, and
      publishes all three result sets. Footprints held only because they
      touched an OSM building that round 1 replaced no longer touch anything
      in round 2. A round-2 structure that shares a wall with a building
      published in round 1 must reuse that building's Live nodes; 3.1 only
      deduplicates nodes inside one output, so otherwise JOSM warns about
      duplicate nodes.
      Decision (2026-09-27, duplicate nodes between Reshape and New): round 1
      runs in two steps. First the import account uploads New. Then Live is
      fetched again, the pipeline runs again, and 500 writes the Reshape
      tasks from that fetch. Where a Reshape structure has a node at the
      exact position of a Live node (7 decimals, the precision OSM stores),
      the task uses that node and creates none. A New building beside a
      Reshape building then shares its wall nodes, and no cleanup is needed.
      Consequences: skipping already-imported structures (5.3) is needed
      before the Reshape step of round 1, not only before round 2, because
      the second run sees every New building in Live; node reuse, planned
      above for round 2, is needed in round 1. Duplicate nodes between two
      Reshape tasks are not fixed by this.
      Considered and dropped: one sentence in the forum post, leaving the
      duplicates to mappers; a cleanup changeset after each round; moving a
      New structure that touches a Reshape group into its task.
      Implemented (2026-09-27, node reuse): 500 builds every Reshape task
      first, then writes them. A new node at the exact position of a Live
      node that a way uses (7 digits; the lowest id where two Live nodes share
      a position) becomes that node, and no task deletes or lists as orphan
      a node any task reuses. Standalone Live nodes (POIs) are never reused.
      Measured on `run_20260927` (before any upload): 288 nodes reused, none
      tagged, none shared by two files, none deleted by any task; 206 of them
      on Live building ways, the rest on untagged multipolygon member ways.
      Old nodes deleted: 80,972 (287 fewer than without reuse); 510: 884
      pending, 0 unexpected uses.
      Decision (2026-09-27, duplicate nodes between Reshape tasks): Reshape
      groups that neighbour each other form one task, and one file. Inside a
      file ogr2osm merges nodes at one position, so the shared walls get one
      set of nodes. A task cannot reach past its block. Cost: larger tasks,
      which a reviewer accepts or rejects whole, and more upload conflicts. A
      task is no longer one top-level modification, so `mr-cli` needs one
      task per file (`--bijective`).
      Decision (2026-09-27, neighbours): two Reshape groups are neighbours
      when a structure of one shares a node position with a structure of the
      other, the case that makes duplicate nodes. Neighbours of neighbours
      join the same task. Considered and dropped: also joining groups whose
      Live buildings share an old node. It would keep more of those nodes
      off the orphan list (510), but makes larger tasks; where the new
      structures also touch, the task already deletes the shared node.
      Implemented (2026-09-27): 170 builds `reshape_tasks` with `cc_run` over
      Reshape structures that touch in one block; 500 builds each task with
      one ogr2osm run and one file, named by the Live building its first
      group keeps, and deletes an old node when every way that uses it is
      replaced in that task. Measured (`run_20260927`, Live fetched
      2026-09-27): 18,389 Reshape groups (19,919 Live buildings, 22,078
      structures) in 10,628 tasks; 8,153 tasks hold one group, 2,475 hold two
      or more, 46 hold 20 or more, and the largest holds 38 groups (39
      structures, block 89-60). The next two largest (33 and 31 groups) are
      in the same seccion. Old nodes left for 510: 884; 510 found 0
      unexpected uses.
- [x] **6.4 Update the artifact and `CONTEXT.md`** to match the settled model.
      The artifact still says conflation is out of scope.
      Done (2026-09-27): the catch-up page ("Buenos Aires Building Import")
      rewritten from `run_20260927`: inputs, terms, the 005-510 steps with
      both gates, the three result sets and rounds, state, open items.
      `CONTEXT.md` names where the Baseline lives.
- [ ] **6.5 Commit and push.** 3 local commits plus the working tree are
      unpushed. `095-aggressive-simplification.sqlx` and the `breakpoint()` go
      away as part of 2.2 and 2.3.
- [ ] **6.6 Post `import.wikitext` to the Community Forum** with `import` tags,
      describing the final methodology. Starts the mandatory 14-day wait and the
      formal request for local community buy-in. Nothing uploads before it
      elapses and concerns are resolved.
      Before posting, correct two false promises in the draft: it offers
      `building:levels=*` from "número de pisos", but `altos` is zero throughout
      and no source data exists; and it promises `ref:cadastre=*` while the code
      emits `smp=` (3.4 decided `ref:cadastre`, so only the code changes). Also
      describe the Simple 3D outline + parts model (3.3).
      Done (2026-09-27): `import.wikitext` rewritten to the settled model: no
      `building:levels`, `ref:cadastre` on outlines only, outline + parts,
      asentamientos informales and Outlier SMPs, preparation steps, the
      link rule and the three result sets with the Conflicts subtypes, the
      two-step round 1 with node reuse, skipping already-imported
      structures, MapRoulette Reshape tasks of neighbouring groups, the
      import account, a timeline, and the counts of `run_20260927`. The
      revert procedure is described too (6.8).
- [x] **6.7 Register the dedicated import account.** Required by the
      Guidelines. Independent of everything else — can be done at any point.
      Done: OSM wiki account `Proyecto_Edificacion_CABA`
      (https://wiki.openstreetmap.org/wiki/User:Proyecto_Edificacion_CABA);
      `import.wikitext` names it.
- [x] **6.8 Write the revert procedure.** The Guidelines require knowing how to
      revert before the first upload.
      Decision (2026-09-27): every import changeset carries the hashtag
      `#tejido-urbano-caba` in its comment: New from the import account, and
      Reshape through the comment the MapRoulette challenge proposes.
      Done (2026-09-27): `import.wikitext`, "Cuenta de importación y
      reversión": list the changesets (the import account for New, the
      hashtag for Reshape; OSMCha filters both), revert them with osm-revert
      or the JOSM Reverter plugin, resolve conflicts with later edits by hand
      in JOSM, announce the revert in the forum thread.
- [ ] **6.9 Tag every changeset with `source=*`.** Decision (2026-09-24): not a
      tag on footprints. OSM's modern practice puts `source=*` on the
      changeset, not on individual objects (wiki Key:source: "should
      typically be added... to the changeset... not as a tag on any mapped
      piece of information"); the Import Guidelines agree ("information about
      the source will be listed on the import account and changesets"). Value:
      `Buenos Aires - Tejido Urbano (data.buenosaires.gob.ar, <date>)`.
      Decision (date): read automatically at each download, not frozen once.
      The portal shows two dates for the dataset — Fecha de publicación
      (2021-05-10, fixed) and Fecha de actualización (2026-07-01 when
      checked, moves) — and `bin/download-dataset.sh` fetches a plain CDN URL
      with no version in it, so two downloads months apart can silently
      differ. `<date>` is the actualización date true at the moment that
      round's copy is downloaded, read from the portal and stamped into the
      changeset tag by the script, not typed by hand.
      Still open: unlike the OSM baseline (6.1), the city dataset itself is
      never frozen — nothing records which snapshot a given run used, or
      keeps two runs from silently using different source data. A city-side
      freeze, parallel to 6.1, is undecided.
      Applies to both upload routes: New's import-account changesets (6.3)
      and Reshape's per-task MapRoulette changesets, pre-filled the same way
      the changeset comment already is (6.3's citation of the cooperative
      tutorial).
      Found (2026-09-27): the actualización date is the package's
      `metadata_modified` (CKAN API), which moves with metadata edits alone.
      The GeoJSON resource says `last_modified` 2021-05-10, the CDN answers
      `Last-Modified: Mon, 10 May 2021`, the description says "contiene datos
      hasta el 2021" and `updateFrequency` is `historico`. The 2025-07-17 and
      2026-09-24 downloads are byte-identical. The data is a 2021 snapshot:
      buildings built or demolished since are not in it.
      Implemented (2026-09-27): `<date>` is the file's `Last-Modified`.
      `bin/download-dataset.sh` writes `data/tejido-<download date>.geojson`
      and beside it `.source` with the tag; `bin/import-datasets.sh` refuses a
      Tejido with no `.source` and stores the tag in `changeset_source`.
      `data/tejido-2026-09-24.source` written by hand (2021-05-10) and
      `run_20260927.changeset_source` filled. The city-side freeze above is
      settled by the same means: each run names its dated file, and the
      `.source` date shows whether the city changed the data. Still to do:
      the upload script for New and the MapRoulette challenge's source field
      read `changeset_source`; neither exists yet.
      Decision (2026-09-27): the local copy `data/tejido-2026-09-24.geojson`
      serves every round; the dataset is not expected to change in the short
      term. Its `.source` holds the tag; a fresh download is needed only if
      the city publishes new data.
      Decision (2026-09-27, data older than Live): no rule for buildings
      built or demolished since 2021. A structure demolished since then and
      absent from Live is New; slightly outdated data is better than none.
      The wiki states the date of the data.
