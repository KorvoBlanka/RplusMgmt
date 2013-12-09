
CREATE OR REPLACE FUNCTION public._query_keywords_refresh ()
RETURNS void AS
$body$
BEGIN
    DELETE FROM query_keywords;

    INSERT INTO query_keywords
    SELECT DISTINCT
      t1.ftype, t1.id, lower(regexp_replace(t2.t2, '^\s*(.+?)\s*$', '\1')) AS fval
    FROM (
        SELECT 'ap_scheme' AS ftype, DAS.id, DAS.keywords FROM dict_ap_schemes DAS WHERE DAS.delete_date IS NULL UNION
        SELECT 'balcony' AS ftype, DBL.id, DBL.keywords FROM dict_balconies DBL WHERE DBL.delete_date IS NULL UNION
        SELECT 'bathroom' AS ftype, DBR.id, DBR.keywords FROM dict_bathrooms DBR WHERE DBR.delete_date IS NULL UNION
        SELECT 'condition' AS ftype, DC.id, DC.keywords FROM dict_conditions DC WHERE DC.delete_date IS NULL UNION
        SELECT 'house_type' AS ftype, DHT.id, DHT.keywords FROM dict_house_types DHT WHERE DHT.delete_date IS NULL UNION
        SELECT 'room_scheme' AS ftype, DRS.id, DRS.keywords FROM dict_room_schemes DRS WHERE DRS.delete_date IS NULL UNION
        SELECT 'landmark' AS ftype, L.id, coalesce(L.keywords,L.name) AS keywords FROM landmarks L WHERE L.type IN ('landmark', 'sublandmark') AND L.delete_date IS NULL UNION
        SELECT 'realty_type' AS ftype, RT.id, coalesce(RT.keywords,RT.name) AS keywords FROM realty_types RT UNION
        SELECT 'tag' AS ftype, T.id, coalesce(T.keywords,T.name) AS keywords FROM tags T WHERE T.delete_date IS NULL
    ) t1, regexp_split_to_table(t1.keywords, ',') t2;
    UPDATE query_keywords SET fts = to_tsvector('russian', fval);

    DELETE FROM _query_cache;
    ALTER SEQUENCE _query_cache_id_seq RESTART 1;
END;
$body$
LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY INVOKER
COST 100;

