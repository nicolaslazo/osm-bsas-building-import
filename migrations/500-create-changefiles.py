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

from dataclasses import dataclass
from shapely import MultiPolygon, Polygon, wkb
from typing import Iterable, Literal, NewType


XMLString = NewType("XMLString", str)


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
    """
    Represents a geometry belonging to a building with its corresponding properties.
    """

    section: str
    block: str
    smp: str
    height: float
    geom: shapely.Geometry


@dataclass
class OsmElement:
    """
    Represents an OSM element (way or relation) with its XML representation.
    """

    id: int
    type: Literal["way", "relation"]
    xml: str


def query_features(conn) -> Iterable[Feature]:
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


def create_osm_element(feature: Feature, id_gen: IdGenerator) -> OsmElement:
    """
    Create an OSM element (way or relation) from a building feature.

    Arguments:
        feature: The building feature containing geometry and properties.
        id_gen: An instance of IdGenerator to generate unique IDs for OSM elements.

    Returns:
        An OsmElement containing the XML representation of the OSM element.
    """

    xml_parts = []

    def add_node(lon, lat):
        node_id = id_gen.next_node()
        xml_parts.append(
            f'    <node id="{node_id}" changeset="1" version="1" lat="{lat}" lon="{lon}" />'
        )
        return node_id

    match feature.geom:
        case Polygon():
            coords = list(feature.geom.exterior.coords)

            # Polygons are usually closed,
            # but ensure the first and last points are the same
            if coords[0] != coords[-1]:
                coords.append(coords[0])

            node_ids = [add_node(lon, lat) for (lon, lat) in coords]
            way_id = id_gen.next_way()

            xml_parts.extend(
                [f'    <way id="{way_id}" changeset="1" version="1">']
                + [f'      <nd ref="{ref}"/>' for ref in node_ids]
                + [
                    f'      <tag k="height" v="{feature.height}"/>',
                    f'      <tag k="building:part" v="yes"/>',
                    "    </way>",
                ]
            )

            return OsmElement(xml="\n".join(xml_parts), id=way_id, type="way")

        case MultiPolygon():
            rel_id = id_gen.next_rel()

            xml_parts += [
                f'    <relation id="{rel_id}" changeset="1" version="1">'
                + '      <tag k="type" v="multipolygon"/>'
                + f'      <tag k="height" v="{feature.height}"/>'
                + '      <tag k="building:part" v="yes"/>'
            ]

            for polygon in feature.geom.geoms:
                outer_coords = list(polygon.exterior.coords)

                if outer_coords[0] != outer_coords[-1]:
                    outer_coords.append(outer_coords[0])

                outer_node_ids = [add_node(lon, lat) for (lon, lat) in outer_coords]
                outer_way_id = id_gen.next_way()

                xml_parts.append(
                    f'      <member type="way" ref="{outer_way_id}" role="outer"/>'
                )

                outer_way_xml = (
                    [f'    <way id="{outer_way_id}" changeset="1" version="1">']
                    + [f'      <nd ref="{ref}"/>' for ref in outer_node_ids]
                    + ["    </way>"]
                )

                for interior in polygon.interiors:
                    inner_coords = list(interior.coords)

                    if inner_coords[0] != inner_coords[-1]:
                        inner_coords.append(inner_coords[0])

                    inner_node_ids = [add_node(lon, lat) for (lon, lat) in inner_coords]
                    inner_way_id = id_gen.next_way()
                    xml_parts.append(
                        f'      <member type="way" ref="{inner_way_id}" role="inner"/>'
                    )

                    inner_way_xml = (
                        [f'    <way id="{inner_way_id}" changeset="1" version="1">']
                        + [f'      <nd ref="{ref}"/>' for ref in inner_node_ids]
                        + ["    </way>"]
                    )

                    xml_parts.extend(inner_way_xml)
                xml_parts.extend(outer_way_xml)
            xml_parts.append("    </relation>")

            return OsmElement(xml="\n".join(xml_parts), id=rel_id, type="relation")

        case _:
            raise ValueError(f"Unsupported geometry type: {type(feature.geom)}")


def create_building_relation(
    smp: str, geom_members: Iterable[tuple[int, str]], id_gen: IdGenerator
) -> XMLString:
    """
    Create an OSM relation for a building from its parts.

    Arguments:
        smp: The SMP identifier for the building. Used for the `ref:SMP` tag.
        geom_members: An iterable of tuples containing element IDs and their types.
        id_gen: An instance of IdGenerator to generate unique IDs for the relation.

    Returns:
        A string containing the XML representation of the OSM relation.
    """

    rel_id = id_gen.next_rel()

    lines = (
        [
            f'    <relation id="{rel_id}" changeset="1" version="1">',
            '      <tag k="type" v="building"/>',
            f'      <tag k="ref:SMP" v="{smp}"/>',
            '      <tag k="source" v="GCBA Tejido Urbano"/>',
        ]
        + [
            f'      <member type="{elem_type}" ref="{elem_id}" role="part"/>'
            for elem_id, elem_type in geom_members
        ]
        + ["    </relation>"]
    )

    return XMLString("\n".join(lines))


def export_block_batch(features: Iterable[Feature]) -> None:
    """
    Export a batch of building features to an OSM Change (.osc) file.

    Arguments:
        features: An iterator of Feature objects representing building geometries.
                  Assumes all items belong to the same section and are ordered by block.
    """

    id_gen = IdGenerator()
    feature_list = list(features)

    block_ids = {str(f.block) for f in feature_list}
    filename = f"seccion-{feature_list[0].section}-blocks-{"-".join(block_ids)}.osc"

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<osmChange version="0.6" generator="PostGIS-to-OSC Script">',
        "  <create>",
    ]

    grouped_by_smp = itertools.groupby(feature_list, key=lambda f: f.smp)

    for smp, parcel_features in grouped_by_smp:
        part_members = []

        for record in parcel_features:
            element = create_osm_element(record, id_gen)
            lines.append(element.xml)
            part_members.append((element.id, element.type))  # TODO: I don't like constructing raw tuples here

        building_rel_xml = create_building_relation(smp, part_members, id_gen)
        lines.append(building_rel_xml)

    lines.append("  </create>")
    lines.append("</osmChange>")

    with open(filename, "w") as f:
        f.write("\n".join(lines))

    print(f"Written {filename}")


if __name__ == "__main__":
    with psycopg.connect(autocommit=True, **DB_PARAMS) as conn:
        features_iter: Iterable[Feature] = query_features(conn)
        grouped_by_section: Iterable[Iterable[Feature]] = iter(
            group
            for _, group in itertools.groupby(features_iter, key=lambda f: f.section)
        )
        block_batches: Iterable[Iterable[Feature]] = itertools.chain.from_iterable(
            itertools.batched(group, 5) for group in grouped_by_section
        )

        for batch in block_batches:
            export_block_batch(batch)
