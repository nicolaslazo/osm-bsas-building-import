#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "psycopg2-binary",
#     "shapely",
# ]
# ///

import os
import psycopg2
from psycopg2.extras import RealDictCursor
from shapely.geometry import MultiPolygon, shape
import json

# Database connection parameters
DB_PARAMS = {
    "host": "localhost",
    "port": 6543,
    "database": "osm_db",
    "user": "osm",
    "password": "password"
}

OUTPUT_DIR = "changesets"
MANZANAS_PER_FILE = 5


def create_changesets(manzana_groups):
    # Get list of manzanas and chunk them
    manzanas = list(manzana_groups.keys())
    chunk_size = MANZANAS_PER_FILE
    chunks = [manzanas[i:i + chunk_size] for i in range(0, len(manzanas), chunk_size)]

    # Create a changeset file for each chunk
    for i, chunk in list(enumerate(chunks))[:3]:
        changeset_file = os.path.join(OUTPUT_DIR, f"changeset_{i+1}.osc")

        # Start XML file with osmChange format
        with open(changeset_file, 'w') as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            f.write('<osmChange version="0.6" generator="building-import-script">\n')
            f.write('  <create>\n')  # All operations are creations

            # Track node IDs (will be negative for new objects)
            node_id = -1
            way_id = -1
            relation_id = -1

            # Process each manzana in this chunk
            for manzana_key in chunk:
                buildings = manzana_groups[manzana_key]

                for building in buildings:
                    smp = building['smp']
                    parts = building['parts']  # Building parts sharing this SMP
                    is_multipart = building['is_multipart']  # Derived from multiple rows

                    if is_multipart:
                        # Create a multipolygon relation for buildings with multiple geometries
                        relation_id -= 1
                        relation_members = []

                        for part in parts:
                            # Create a way for each geometry part
                            geom = part['geom']

                            # Handle both Polygon and MultiPolygon geometries
                            if isinstance(geom, MultiPolygon):
                                # Process each polygon in the multipolygon
                                for poly in geom.geoms:
                                    way_id -= 1
                                    way_nodes = []

                                    # Get coordinates for the exterior ring
                                    coords = list(poly.exterior.coords)

                                    # Create nodes for each coordinate
                                    for x, y in coords[:-1]:  # Exclude last point which is same as first
                                        node_id -= 1
                                        # Convert to lat/lon - OSM uses lat first, lon second
                                        f.write(f'    <node id="{node_id}" lat="{y}" lon="{x}" version="1"/>\n')
                                        way_nodes.append(node_id)

                                    # Create the way
                                    f.write(f'    <way id="{way_id}" version="1">\n')
                                    for node in way_nodes:
                                        f.write(f'      <nd ref="{node}"/>\n')

                                    # Close the polygon by referencing the first node again
                                    f.write(f'      <nd ref="{way_nodes[0]}"/>\n')

                                    # Add tags to way (only building=part)
                                    f.write('      <tag k="building:part" v="yes"/>\n')
                                    f.write('    </way>\n')

                                    relation_members.append(way_id)
                            else:
                                # Process a simple polygon
                                way_id -= 1
                                way_nodes = []

                                # Get coordinates for the exterior ring
                                coords = list(geom.exterior.coords)

                                # Create nodes for each coordinate
                                for x, y in coords[:-1]:  # Exclude last point which is same as first
                                    node_id -= 1
                                    # Convert to lat/lon - OSM uses lat first, lon second
                                    f.write(f'    <node id="{node_id}" lat="{y}" lon="{x}" version="1"/>\n')
                                    way_nodes.append(node_id)

                                # Create the way
                                f.write(f'    <way id="{way_id}" version="1">\n')
                                for node in way_nodes:
                                    f.write(f'      <nd ref="{node}"/>\n')

                                # Close the polygon by referencing the first node again
                                f.write(f'      <nd ref="{way_nodes[0]}"/>\n')

                                # Add tags to way (only building=part)
                                f.write('      <tag k="building:part" v="yes"/>\n')
                                f.write('    </way>\n')

                                relation_members.append(way_id)

                        # Create the multipolygon relation for the entire building
                        f.write(f'    <relation id="{relation_id}" version="1">\n')
                        for member_id in relation_members:
                            f.write(f'      <member type="way" ref="{member_id}" role="outer"/>\n')
                        f.write('      <tag k="type" v="building"/>\n')
                        f.write('      <tag k="building" v="yes"/>\n')
                        f.write(f'      <tag k="smp" v="{smp}"/>\n')
                        # Use height from first part if available
                        if parts[0]['altura'] is not None:
                            f.write(f'      <tag k="height" v="{parts[0]["altura"]}"/>\n')
                        f.write('    </relation>\n')
                    else:
                        # Create a simple way for single-geometry buildings
                        part = parts[0]  # Just one part for single buildings
                        geom = part['geom']

                        # Handle both Polygon and MultiPolygon geometries
                        if isinstance(geom, MultiPolygon):
                            # For multipolygon geometries, create a relation
                            relation_id -= 1
                            relation_members = []

                            for poly in geom.geoms:
                                way_id -= 1
                                way_nodes = []

                                # Get coordinates for the exterior ring
                                coords = list(poly.exterior.coords)

                                # Create nodes for each coordinate
                                for x, y in coords[:-1]:  # Exclude last point which is same as first
                                    node_id -= 1
                                    # Convert to lat/lon - OSM uses lat first, lon second
                                    f.write(f'    <node id="{node_id}" lat="{y}" lon="{x}" version="1"/>\n')
                                    way_nodes.append(node_id)

                                # Create the way
                                f.write(f'    <way id="{way_id}" version="1">\n')
                                for node in way_nodes:
                                    f.write(f'      <nd ref="{node}"/>\n')

                                # Close the polygon by referencing the first node again
                                f.write(f'      <nd ref="{way_nodes[0]}"/>\n')

                                # Add tags to way (only building=part)
                                f.write('      <tag k="building:part" v="yes"/>\n')
                                f.write('    </way>\n')

                                relation_members.append(way_id)

                            # Create the multipolygon relation
                            f.write(f'    <relation id="{relation_id}" version="1">\n')
                            for member_id in relation_members:
                                f.write(f'      <member type="way" ref="{member_id}" role="outer"/>\n')
                            f.write('      <tag k="type" v="multipolygon"/>\n')
                            f.write('      <tag k="building" v="yes"/>\n')
                            f.write(f'      <tag k="smp" v="{smp}"/>\n')
                            if parts[0]['altura'] is not None:
                                f.write(f'      <tag k="height" v="{parts[0]["altura"]}"/>\n')
                            f.write('    </relation>\n')
                        else:
                            # Simple polygon, create a way
                            way_id -= 1
                            way_nodes = []

                            # Get coordinates for the exterior ring
                            coords = list(geom.exterior.coords)

                            # Create nodes for each coordinate
                            for x, y in coords[:-1]:  # Exclude last point which is same as first
                                node_id -= 1
                                # Convert to lat/lon - OSM uses lat first, lon second
                                f.write(f'    <node id="{node_id}" lat="{y}" lon="{x}" version="1"/>\n')
                                way_nodes.append(node_id)

                            # Create the way
                            f.write(f'    <way id="{way_id}" version="1">\n')
                            for node in way_nodes:
                                f.write(f'      <nd ref="{node}"/>\n')

                            # Close the polygon by referencing the first node again
                            f.write(f'      <nd ref="{way_nodes[0]}"/>\n')

                            # Add tags
                            f.write('      <tag k="building" v="yes"/>\n')
                            f.write(f'      <tag k="smp" v="{smp}"/>\n')
                            if part['altura'] is not None:
                                f.write(f'      <tag k="height" v="{part["altura"]}"/>\n')
                            f.write('    </way>\n')

            # Close XML file
            f.write('  </create>\n')
            f.write('</osmChange>\n')


def main():
    # create output directory if it doesn't exist
    os.makedirs("changesets", exist_ok=True)

    # connect to database
    conn = psycopg2.connect(**DB_PARAMS)

    # get all non_intersecting geometries
    query = """
    select id, smp, seccion, manzana, parcela, altura, st_asgeojson(geom) as geom
    from non_intersecting
    where seccion = '13'
    order by seccion desc, manzana desc, parcela desc
    """

    with conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(query)
        rows = cursor.fetchall()

        # group geometries by smp
        # multiple rows with the same smp indicate a multipart building
        smp_groups = {}
        for row in rows:
            smp = row['smp']
            if smp not in smp_groups:
                smp_groups[smp] = []

            geom_json = json.loads(row['geom'])
            geom = shape(geom_json)
            smp_groups[smp].append({
                'id': row['id'],
                'seccion': row['seccion'],
                'manzana': row['manzana'],
                'parcela': row['parcela'],
                'altura': row['altura'],
                'geom': geom
            })

        # group by manzana
        manzana_groups = {}
        for smp, geoms in smp_groups.items():
            key = f"{geoms[0]['seccion']}-{geoms[0]['manzana']}"
            if key not in manzana_groups:
                manzana_groups[key] = []

            # we detect multipart buildings by checking if multiple rows share the same smp
            is_multipart = len(geoms) > 1
            manzana_groups[key].append({
                'smp': smp,
                'parts': geoms,  # list of building parts sharing this smp
                'is_multipart': is_multipart  # derived from multiple rows with same smp
            })

        # create changesets with ~5 manzanas per file
        create_changesets(manzana_groups)

    conn.close()
    print("Generated changesets")


if __name__ == "__main__":
    main()
