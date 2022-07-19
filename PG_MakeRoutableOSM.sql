INSERT INTO ways(
      way_id
	, tag_id
	, osm_source
	, osm_target
    , source
    , target
    , name
    , length_m
    , cost_s
    , reverse_cost_s
    , dir
    , the_geom
    )
-- Split ways.
WITH splited_line as (
    SELECT 
    	  way_id
        , nodes ->> 0 as osm_source
        , nodes ->> -1 as osm_target
        , tags
        , CASE
            WHEN sp_points.split_geom IS NOT NULL 
            THEN ST_Split(highway.geom, sp_points.split_geom)
            ELSE highway.geom
          END AS geom
    FROM osm_highway as highway
        CROSS JOIN LATERAL (
            SELECT ST_Union(
                    ST_Points(ST_Intersection(highway.geom, sp_line.geom))
                ) as split_geom
            FROM osm_highway AS sp_line
            WHERE tags->>'highway' in (
                    SELECT tag_value
                    FROM ways_configuration
                )
                and (
                    tags->>'bridge' IS NULL
                    AND tags->>'tunnel' IS NULL
                )
                and (
                    highway.way_id != sp_line.way_id
                    AND ST_Intersects(highway.geom, (sp_line.geom))
                )
        ) sp_points
    WHERE tags->>'highway' in (
            SELECT tag_value
            FROM ways_configuration
        )
        AND ST_length(geography(ST_Transform(geom, 4326)))::real IS NOT NULL
),
ways AS (
    SELECT 
          way_id
        , osm_source
        , osm_target
		, tags->>'highway' AS tag_value
        , tags->>'name' AS name
        , CASE
            WHEN tags->>'oneway' in ('yes', 'true', '1')
            OR tags->>'junction' in ('roundabout')
            OR tags->>'highway' in ('motorway') THEN 1
            WHEN tags->>'oneway' in ('no', 'false', '0') THEN 0
            WHEN tags->>'oneway' = 'reversible' THEN 3
            WHEN tags->>'oneway' = '-1' THEN -1
            ELSE 0
          END as one_way
        , (ST_Dump(geom)).geom
    FROM splited_line
),
ways_with_cost AS(
    SELECT
          way_id
		, osm_source
		, osm_target
        , tag_id
        , name
        , ST_length(geography(ST_Transform(geom, 4326)))::real as length_m
        , CASE
	        WHEN maxspeed = 0
	        THEN -1
            WHEN one_way = -1
            THEN - ST_length(geography(ST_Transform(geom, 4326))) / (maxspeed::float * 5.0 / 18.0)
            ELSE ST_length(geography(ST_Transform(geom, 4326))) / (maxspeed::float * 5.0 / 18.0)
          END AS cost_s
        , CASE
	        WHEN maxspeed = 0
	        THEN -1
            WHEN one_way = 1
            THEN - ST_length(geography(ST_Transform(geom, 4326))) / (maxspeed::float * 5.0 / 18.0)
            ELSE ST_length(geography(ST_Transform(geom, 4326))) / (maxspeed::float * 5.0 / 18.0)
          END AS reverse_cost_s
        , geom
    FROM ways w
        LEFT JOIN ways_configuration USING (tag_value)
)
SELECT
      way_id
	, tag_id
	, osm_source::bigint
	, osm_target::bigint
    , NULL::int as source
    , NULL::int as target
    , name
    , length_m
    , cost_s
    , reverse_cost_s
    , CASE
        WHEN (
            cost_s > 0
            and reverse_cost_s > 0
        ) THEN 'B' -- both ways                 
        WHEN (
            cost_s > 0
            and reverse_cost_s < 0
        ) THEN 'FT' -- direction of the highwaySTRING
        WHEN (
            cost_s < 0
            and reverse_cost_s > 0
        ) THEN 'TF' -- reverse direction of the highwayTRING
        ELSE ''
      END AS dir
    , geom AS the_geom
FROM ways_with_cost;
