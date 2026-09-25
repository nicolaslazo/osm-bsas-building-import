# Buenos Aires Building Import

Reconciles the City of Buenos Aires's official building dataset against OpenStreetMap and
publishes the differences as sets a human can review and commit. This glossary exists because
several words in this domain — "building", "outlier", "part", "changeset" — arrive already
overloaded, from the source dataset, from OSM, and from cadastral practice.

## Language

### City-side units

**Footprint**:
One row of `city_data`: a single photogrammetry-derived polygon with one `altura`. The unit
migrations count. Classification runs on structures, not footprints.
_Avoid_: building, polygon, geom, shape

**Parcel**:
All footprints sharing one SMP — the built content of a single cadastral lot. A footprint with
no SMP, or with an Outlier SMP, is a parcel by itself. Its footprints form one or more
structures; footprints of one parcel that share no wall may go to different result sets.
_Avoid_: parcela (that is the third SMP component only), building, lot, SMP group

**Structure**:
The footprints of one parcel joined through shared walls, directly or through a chain, whatever
their altura. A wall is a shared line; footprints that meet only at a corner point are not
joined. One edifice: a lower wing or balcony beside a taller section is the same structure. A
structure of one footprint is published as a `building=yes` way; a larger one as a
`building=yes` outline over all of it plus one building part per footprint. The unit of
classification and publication: a structure is never split across two result sets.
_Avoid_: building (the OSM object), complex, group, cluster

**Block**:
A `(seccion, manzana)` pair. The partition for every coverage operation, and the grouping unit
for review in the Conflicts files; a New file holds one seccion, and Reshape is reviewed one
Live building at a time on MapRoulette, not by block. Footprints with no SMP have no pair: those connected through gaps of at most 22 cm
form a group; a group within 22 cm of a block's footprint joins that block, and any other
group is a block by itself.
_Avoid_: manzana (ambiguous with the middle SMP component alone), city block, cuadra

**SMP**:
A cadastral reference formatted `seccion-manzana-parcela` (e.g. `87-006A-015`). Components may
contain letters; that is normal, not a defect. Published as `ref:cadastre` on every
`building=yes` way, never on a building part.
_Avoid_: cadastral code, ID, ref

**Outlier SMP**:
An SMP whose parcel does not describe one ordinary lot: its parcela is not an ordinary number
with an optional letter suffix (`BEM1`, `0FRA`, `PLZ1`, `0000`, `B201`, …), or its parcel holds
more than 50 footprints. Too inconsistent to group anything: each of its footprints is a
separate building and a parcel by itself.
_Avoid_: special code, bad SMP (a missing or malformed SMP, which becomes NULL)

**Asentamiento informal**:
An informal settlement, coded with parcela `BEM*`. Each of its footprints is a separate
building and a parcel by itself, published with no cadastral tag and no height.
_Avoid_: BEM parcel, slum, villa

### OSM-side

**Baseline**:
The frozen `2025-10-05` OSM export. Used only to calibrate classification thresholds. No result
set is ever derived from it.
_Avoid_: live data, live_buildings, current OSM, snapshot

**Live**:
The metadata-bearing OSM fetch taken immediately before publication. The only snapshot a result
set may be derived from.
_Avoid_: fresh data, new OSM, production data

### Result sets

**Result set**:
One published bundle of proposed changes, reviewable and committable on its own. Not every
result set is a changefile.
_Avoid_: changeset (an OSM changeset is a server-side grouping of edits with its own ID),
changefile (that is the `.osc` file format specifically), output

**New**:
Structures that overlap no Live building, published to be added as they are. Any overlap
counts, whatever its area; a wall or corner shared with a Live building, with no overlap, does
not. The pipeline decides this before publication, not the reviewer.
_Avoid_: additions, create, missing buildings

**Link**:
A structure (its `building=yes` way) and a Live building whose overlap is at least 1 m² and
more than half of the smaller of the two. Linked shapes form groups: 1:1, N:1 (many
structures, one Live building), 1:N and N:M.
_Avoid_: match (reserved for the JOSM conflation plugin's own matching), overlap, touch

**Reshape**:
Structures in 1:1 or N:1 link groups, published to replace each Live building's geometry
with its structures while its tags and history stay. A 1:N group where at most one Live
building has tags beyond `building=yes` is Reshape by merge: the structure replaces that
building's geometry (or the one with the largest overlap) and the group's other Live buildings
are deleted. In an N:1 group the structure with the largest overlap keeps the Live building's
way and tags; an N:1 group whose Live building has tags and whose structures lie on several
parcels goes to Conflicts. A group whose structures overlap an OSM building that stays goes to
Conflicts instead. No overlap or distance cutoff applies: the
footprints are taken as more accurate than the OSM shape. The pipeline
decides this before publication; the JOSM conflation plugin only helps review it.
_Avoid_: update, replace, conflate, merge

**Conflicts**:
Structures whose overlap against Live is too ambiguous to classify automatically, each with
reason subtypes kept in the pipeline's database. Reasons are never published. OSM buildings with no structure beneath them are out of scope: never
classified, listed or changed.
_Avoid_: outliers (reserved for Outlier SMP), rejects, errors, leftovers

**Release round**:
One pass of fetch Live, run the pipeline, publish. Round 1 publishes New and Reshape and holds
Conflicts; once it is processed, round 2 reruns against a fresh Live and publishes all three
result sets. Before classification, each round skips every structure already in Live: matched
by `ref:cadastre` whatever its shape, or geometrically where the tag cannot decide (which
geometric test is settled after round 1).
_Avoid_: batch (ambiguous with result set and with per-block files), iteration, phase

### Attributes

**Altura**:
The source dataset's only vertical measurement, in metres, mapped to OSM `height` everywhere
except in asentamientos informales. The dataset
carries no storey count — `altos` is present but zero throughout — so `building:levels` has no
source behind it.
_Avoid_: height (use for the OSM tag only), elevation, levels, pisos

**Building part**:
Reserved for its OSM Simple 3D Buildings meaning: a vertically distinct portion of one
structure. Footprints of one parcel with the same altura that share a wall, directly or through
a chain of such footprints, are first merged into one footprint. In a structure of two or more
footprints, each footprint is published as a building part with its own altura, side by side
or nested; an enclosing footprint's part (the base part) covers the footprints nested in it.
Footprints of one parcel that share no wall are separate structures, never parts of one.
_Avoid_: using "part" for a footprint of a one-footprint structure, or for footprints of
different structures
