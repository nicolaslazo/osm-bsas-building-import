#!/bin/bash
# Usage: bin/fetch-live.sh [output]
#   BBOX=s,w,n,e bin/fetch-live.sh test.osm   fetches a bounding box instead, for tests
# Fetches Live (PLAN 6.2) from Overpass as raw .osm with metadata, default data/live-osm-<today>.osm.
# Every building and building:part inside the CABA boundary, their members and nodes, and,
# without their own nodes, every other way that uses one of those nodes and every relation that
# holds one of those ways. 500 needs those to know which old nodes and ways a Reshape may delete.

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

for attempt in 1 2 3; do
  code=$(curl -sS -m 1000 -A "osm-bsas-building-import/1.0" --data-urlencode "data=${QUERY}" \
    -o "${OUT}.part" -w '%{http_code}' https://overpass-api.de/api/interpreter)
  echo "attempt ${attempt}: http ${code}, $(stat -c %s "${OUT}.part") bytes"
  if [[ "$code" == "200" ]] && tail -c 100 "${OUT}.part" | grep -q "</osm>"; then
    mv "${OUT}.part" "${OUT}"
    echo "wrote ${OUT}"
    exit 0
  fi
  sleep 90
done
echo "fetch failed" >&2
exit 1
