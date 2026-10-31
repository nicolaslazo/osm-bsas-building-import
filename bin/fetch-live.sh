#!/bin/bash
# Usage: bin/fetch-live.sh [output]
#   BBOX=s,w,n,e bin/fetch-live.sh test.osm   fetches a bounding box instead, for tests
# Fetches Live (PLAN 6.2) from Overpass as raw .osm with metadata, default data/live-osm-<today>.osm.
# Every building and building:part inside the CABA boundary, their members and nodes, and,
# without their own nodes, every other way that uses one of those nodes and every relation that
# holds one of those ways. 500 needs those to know which old nodes and ways a Reshape may delete.
# Writes beside it <output minus .osm>.cutoff: the type and id of every way and relation tagged
# building=* at the data date (PLAN 4.9), read from the newest data/tejido-*.source unless
# CUTOFF=YYYY-MM-DD is given.

set -e

PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
OUT="${1:-${PROJECT_ROOT}/data/live-osm-$(date +%F).osm}"
if [[ -n "$BBOX" ]]; then
  AREA="" ; IN="(${BBOX})"
else
  AREA="area(id:3601224652)->.a;" ; IN="(area.a)"
fi

QUERY="[out:xml][timeout:900];
${AREA}
(
  way[\"building\"]${IN};
  relation[\"building\"]${IN};
  way[\"building:part\"]${IN};
  relation[\"building:part\"]${IN};
)->.b;
(.b; .b >;)->.all;
way.all->.w;
node.all->.n;
(
  .all;
  way(bn.n);
  relation(bw.w);
);
out meta;"

if [[ -z "$CUTOFF" ]]; then
  SOURCE_FILE=$(ls "${PROJECT_ROOT}"/data/tejido-*.source | sort | tail -1)
  CUTOFF=$(sed -n 's/.*, \([0-9-]*\))$/\1/p' "$SOURCE_FILE")
fi
# Overpass applies no area filter to dated queries, so the cutoff query takes a box around
# the city; ids outside it match no Live building
CUT_IN="(${BBOX:--34.71,-58.54,-34.52,-58.33})"
CUTOFF_QUERY="[out:csv(::type,::id;false)][timeout:900][date:\"${CUTOFF}T00:00:00Z\"];
(
  way[\"building\"]${CUT_IN};
  relation[\"building\"]${CUT_IN};
);
out ids;"

# fetch <query> <output> <test of a complete answer>
fetch() {
  for attempt in 1 2 3; do
    code=$(curl -sS -m 1000 -A "osm-bsas-building-import/1.0" --data-urlencode "data=$1" \
      -o "$2.part" -w '%{http_code}' https://overpass-api.de/api/interpreter)
    echo "attempt ${attempt}: http ${code}, $(stat -c %s "$2.part") bytes"
    if [[ "$code" == "200" ]] && $3 "$2.part"; then
      mv "$2.part" "$2"
      echo "wrote $2"
      return 0
    fi
    sleep 90
  done
  echo "fetch failed: $2" >&2
  exit 1
}
osm_complete() { tail -c 100 "$1" | grep -q "</osm>"; }
ids_complete() { [[ -s "$1" ]] && ! grep -qv -E '^(way|relation)	[0-9]+$' "$1"; }

fetch "$QUERY" "$OUT" osm_complete
echo "cutoff ${CUTOFF}"
fetch "$CUTOFF_QUERY" "${OUT%.osm}.cutoff" ids_complete
