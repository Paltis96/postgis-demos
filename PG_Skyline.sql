CREATE OR REPLACE FUNCTION pg_skyline(
          x1 numeric
        , y1 numeric
        , inlevel integer DEFAULT 1
        , radius integer DEFAULT 1000
        , CASEaccuracy integer DEFAULT 300
    ) 
    RETURNS SETOF json
    LANGUAGE 'plpgsql' 
    COST 100 
    VOLATILE PARALLEL SAFE 
    ROWS 1 AS 
    $BODY$ 
    BEGIN RETURN QUERY
    SELECT json_build_object(
            'type'
            , 'FeatureCollection'
            , 'features'
            , json_agg(ST_AsGeoJSON(res.*)::json)
        )
    FROM (
            SELECT ST_Transform(
                    ST_MakePolygon(
                        ST_LineFromMultiPoint(
                            ST_Collect(
                                ST_EndPoint(
                                    ST_GeometryN(
                                        ST_Difference(g.geom, b.geom),
                                        1
                                    )
                                )
                            )
                        )
                    ),
                    4326
                ) AS geom
            FROM (
                    SELECT ST_MakeLine(
                            ST_Transform(
                                ST_SetSRID(ST_MakePoint(x1, y1), 4326), 32636),
                            (gline.gdump).geom
                        ) AS geom
                    FROM (
                            SELECT ST_DumpPoints(
                                    ST_Buffer(
                                        ST_Transform(ST_SetSRID(ST_MakePoint(x1, y1), 4326), 32636),
                                        radius,
                                        accuracy
                                    )
                                ) as gdump
                        ) AS gline
                ) AS g,
                (
                    SELECT ST_Union(geom) as geom
                    FROM source_data.buildings_kyiv AS bkiev
                    WHERE ST_Intersects(
                            ST_Buffer(
                                ST_Transform(ST_SetSRID(ST_MakePoint(x1, y1), 4326), 32636),
                                radius,
                                10
                            ),
                            bkiev.geom
                        )
                        AND floors::int >= inlevel
                ) AS b
        ) AS res;
END;
$BODY$;