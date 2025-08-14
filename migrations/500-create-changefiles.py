#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "itertools",
#     "psycopg[binary]",
#     "shapely",
# ]
# ///

import itertools
import psycopg
import shapely

from collections import defaultdict
from dataclasses import dataclass
from shapely import MultiPolygon, Polygon, wkb
from typing import Generator, Iterator

# Database connection parameters
DB_PARAMS = {
    "host": "localhost",
    "port": 6543,
    "database": "osm_db",
    "user": "osm",
    "password": "password",
}
BUILDINGS_TABLE = "non_intersecting"


class IdGenerator:
    def __init__(self):
        self._node_counter = 0
        self._way_counter = 0
        self._relation_counter = 0

    def next_node(self):
        self._node_counter -= 1
        return self._node_counter

    def next_way(self):
        self._way_counter -= 1
        return self._way_counter

    def next_rel(self):
        self._relation_counter -= 1
        return self._relation_counter


@dataclass
class Feature:
    section: str
    block: str
    smp: str
    height: float
    geom: shapely.Geometry


def query_features(conn) -> Generator[Feature, None, None]:
    """
    Fetch building records from the PostGIS database.
    """

    query = f"""
        SELECT seccion, manzana, smp, altura, ST_AsBinary(geom) AS geom
        FROM {BUILDINGS_TABLE}
        ORDER BY seccion, manzana;
    """
    cur = conn.execute(query)

    for seccion, manzana, smp, altura, geom_wkb in cur:
        # Convert WKB (well known bytes) to Shapely geometry
        geom = wkb.loads(geom_wkb, hex=False)

        yield Feature(section=seccion, block=manzana, smp=smp, height=altura, geom=geom)


def create_osm_elements_for_feature(feature: Feature, id_gen: IdGenerator):
    """
    Convert a Shapely geometry into OSM XML elements (nodes + way or relation).
    Returns (xml_string, element_id, element_type).
    """
    xml_parts = []

    def add_node(lat, lon):
        node_id = id_gen.next_node()
        xml_parts.append(
            f'    <node id="{node_id}" changeset="1" version="1" lat="{lat}" lon="{lon}" />'
        )
        return node_id

    match feature.geom:
        case Polygon():
            # Single polygon => one way
            polygon = feature.geom
            outer_coords = list(polygon.exterior.coords)
            if outer_coords[0] != outer_coords[-1]:
                outer_coords.append(outer_coords[0])
            # Create nodes for outer ring
            node_ids = [add_node(y, x) for (x, y) in outer_coords]
            # Create way
            way_id = id_gen.next_way()
            xml_parts.append(f'    <way id="{way_id}" changeset="1" version="1">')
            for ref in node_ids:
                xml_parts.append(f'      <nd ref="{ref}"/>')
            # Tags for height and building part
            xml_parts.append(f'      <tag k="height" v="{feature.height}"/>')
            xml_parts.append(f'      <tag k="building:part" v="yes"/>')
            xml_parts.append("    </way>")
            return "\n".join(xml_parts), way_id, "way"

        case MultiPolygon():
            # MultiPolygon or polygon with holes => use a multipolygon relation
            rel_id = id_gen.next_rel()
            xml_parts.append(f'    <relation id="{rel_id}" changeset="1" version="1">')
            xml_parts.append('      <tag k="type" v="multipolygon"/>')
            xml_parts.append(f'      <tag k="height" v="{feature.height}"/>')
            xml_parts.append(f'      <tag k="building:part" v="yes"/>')
            # Iterate over each polygon component
            for polygon in feature.geom.geoms:
                # Outer ring as a way
                outer_coords = list(polygon.exterior.coords)
                if outer_coords[0] != outer_coords[-1]:
                    outer_coords.append(outer_coords[0])
                outer_node_ids = [add_node(y, x) for (x, y) in outer_coords]
                outer_way_id = id_gen.next_way()
                # Add as outer member in relation
                xml_parts.append(
                    f'      <member type="way" ref="{outer_way_id}" role="outer"/>'
                )
                # Build outer way XML
                outer_way_xml = [
                    f'    <way id="{outer_way_id}" changeset="1" version="1">'
                ]
                for ref in outer_node_ids:
                    outer_way_xml.append(f'      <nd ref="{ref}"/>')
                outer_way_xml.append("    </way>")
                # Handle inner rings for this polygon
                for interior in polygon.interiors:
                    inner_coords = list(interior.coords)
                    if inner_coords[0] != inner_coords[-1]:
                        inner_coords.append(inner_coords[0])
                    inner_node_ids = [add_node(y, x) for (x, y) in inner_coords]
                    inner_way_id = id_gen.next_way()
                    xml_parts.append(
                        f'      <member type="way" ref="{inner_way_id}" role="inner"/>'
                    )
                    inner_way_xml = [
                        f'    <way id="{inner_way_id}" changeset="1" version="1">'
                    ]
                    for ref in inner_node_ids:
                        inner_way_xml.append(f'      <nd ref="{ref}"/>')
                    inner_way_xml.append("    </way>")
                    # Append the inner way XML to the main list
                    xml_parts.extend(inner_way_xml)
                # Append the outer way XML after inner ways
                xml_parts.extend(outer_way_xml)
            xml_parts.append("    </relation>")
            return "\n".join(xml_parts), rel_id, "relation"

        case _:
            raise ValueError(f"Unsupported geometry type: {type(feature.geom)}")


def create_building_relation(smp, part_members, id_gen):
    """
    Create a type=building relation XML string for the given SMP and its part members.
    part_members is a list of (element_id, element_type) for each part.
    """
    rel_id = id_gen.next_rel()
    lines = [f'    <relation id="{rel_id}" changeset="1" version="1">']
    lines.append('      <tag k="type" v="building"/>')
    lines.append(f'      <tag k="ref:SMP" v="{smp}"/>')
    lines.append('      <tag k="source" v="GCBA Tejido Urbano"/>')
    for elem_id, elem_type in part_members:
        lines.append(f'      <member type="{elem_type}" ref="{elem_id}" role="part"/>')
    lines.append("    </relation>")
    return "\n".join(lines)


def export_buildings_to_osc(features: Iterator[Feature]) -> None:
    # Map (section, block) to list of SMPs in that block
    section_block_map = defaultdict(list)
    for smp, records in buildings_by_smp.items():
        sec = records[0]["seccion"]
        mz = records[0]["manzana"]
        section_block_map[(sec, mz)].append(smp)
    # Group blocks by section
    section_to_blocks = defaultdict(list)
    for (sec, mz), smps in section_block_map.items():
        section_to_blocks[sec].append(mz)
    # Create output files for each group of ~5 blocks in each section
    for sec, blocks in section_to_blocks.items():
        blocks.sort()
        for i in range(0, len(blocks), 5):
            chunk = blocks[i : i + 5]
            if not chunk:
                continue
            start_block = chunk[0]
            end_block = chunk[-1]
            filename = f"sec{sec}_blocks_{start_block}"
            if end_block != start_block:
                filename += f"-{end_block}"
            filename += ".osc"
            # Start building the OsmChange XML content
            lines = ['<?xml version="1.0" encoding="UTF-8"?>']
            lines.append('<osmChange version="0.6" generator="PostGIS-to-OSC Script">')
            lines.append("  <create>")
            id_gen = IdGenerator()  # new ID generator for this file
            # Populate the create section with building parts and relations
            for mz in chunk:
                for smp in section_block_map[(sec, mz)]:
                    records = buildings_by_smp[smp]
                    part_members = []
                    # Create OSM elements for each geometry in this SMP
                    for record in records:
                        geom = record["geometry"]
                        altura = record["altura"]
                        geom_xml, elem_id, elem_type = create_osm_elements_for_geom(
                            geom, altura, id_gen
                        )
                        lines.append(geom_xml)
                        part_members.append((elem_id, elem_type))
                    # Create the building relation for this SMP group
                    building_rel_xml = create_building_relation(
                        smp, part_members, id_gen
                    )
                    lines.append(building_rel_xml)
            lines.append("  </create>")
            lines.append("</osmChange>")
            # Write to file
            with open(filename, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
            print(f"Written {filename}")


if __name__ == "__main__":
    with psycopg.connect(autocommit=True, **DB_PARAMS) as conn:
        features_iter: Generator[Feature, None, None] = query_features(conn)
        grouped_by_section: Generator[Iterator[Feature], None, None] = iter(
            group
            for _, group in itertools.groupby(features_iter, key=lambda f: f.section)
        )
        block_batches = itertools.chain.from_iterable(
            itertools.batched(group, 5) for group in grouped_by_section
        )

        for batch in block_batches:
            export_buildings_to_osc(batch)
