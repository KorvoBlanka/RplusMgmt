--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: postgis; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA postgis;


--
-- Name: plperl; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plperl WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plperl; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plperl IS 'PL/Perl procedural language';


--
-- Name: plperlu; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plperlu WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plperlu; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plperlu IS 'PL/PerlU untrusted procedural language';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA postgis;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


SET search_path = public, pg_catalog;

--
-- Name: _address_objects_build_metadata(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION _address_objects_build_metadata() RETURNS void
    LANGUAGE plperlu
    AS $_X$
use strict;

use JSON;
use Encode qw(encode_utf8 decode_utf8);

my $plan = spi_prepare(q{UPDATE address_objects SET expanded_name = $1, metadata = $2, fts = NULL, fts2 = NULL WHERE id = $3}, 'TEXT', 'JSON', 'INTEGER');

my $sth = spi_query("SELECT id, name, short_type, lower(full_type) full_type, level, parent_guid FROM address_objects");
while (my $row = spi_fetchrow($sth)) {
  my $guid = delete $row->{'parent_guid'};
  my @addr_parts = ($row);
  while ($guid) {
    my $rv2 = spi_exec_query("SELECT id, name, short_type, lower(full_type) full_type, level, parent_guid FROM address_objects AO WHERE AO.guid = '$guid' AND AO.curr_status = 0", 1);
    if ($rv2->{'processed'}) {
      $guid = delete $rv2->{'rows'}[0]->{'parent_guid'};
      push @addr_parts, $rv2->{'rows'}[0];
    } else {
      $guid = undef;
    }
  }

  my $metadata = {addr_parts => \@addr_parts};

  my $expanded_name = '';
  for (@addr_parts) {
    $expanded_name .= ', ' if $expanded_name;
    $expanded_name .= $_->{'name'}.' '.$_->{'short_type'};
  }

  spi_exec_prepared($plan, $expanded_name, decode_utf8(encode_json($metadata)), $row->{'id'});
}

spi_freeplan($plan);

spi_exec_query(q{
  UPDATE address_objects SET fts2 = to_tsvector('russian',
    CASE WHEN short_type = 'ул' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'пгт' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'проезд' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'п' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'пр-кт' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'кв-л' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'рп' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'пер' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'б-р' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'г' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'ш' THEN name||' '||short_type||' '||full_type
         WHEN short_type = 'с' THEN name||' '||short_type||' '||full_type
         ELSE NULL
    END
  )
});
spi_exec_query(q{
  UPDATE address_objects SET fts = to_tsvector('russian', name), fts3 = to_tsvector('simple', name||' '||short_type||' '||full_type) WHERE fts2 IS NOT NULL
});
$_X$;


--
-- Name: _get_realty_fts(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION _get_realty_fts(integer) RETURNS tsvector
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  x_fts_rec RECORD;
BEGIN

  SELECT INTO x_fts_rec
    -- GEO
    /*
    coalesce((
      SELECT string_agg(L.keywords,' ')
      FROM landmarks L
      WHERE 
        L.type IN ('landmark','sublandmark') AND
        /*ST_Covers(L.geodata::geography, R.geocoords::geography) = true*/
        L.geodata::geography && R.geocoords::geography AND
        L.delete_date IS NULL
    ),'') AS geo,
    */

    -- Title
    coalesce(RT.keywords,'')||' '||coalesce(ROT.keywords,'') AS title,

    -- Addr
    coalesce(AO.keywords,AO.name||' '||AO.full_type||' '||AO.short_type,'') AS addr,

    -- Text (desc/body)
    coalesce(DAS.keywords,'')||' '||coalesce(DBL.keywords,'')||' '||coalesce(DBR.keywords,'')||' '||coalesce(DC.keywords,'')||' '||coalesce(DHT.keywords,'')||' '||coalesce(DRS.keywords,'')||' '||
    coalesce(R.description,'')
    AS text
  FROM realty R
  LEFT JOIN realty_types RT ON (RT.code = R.type_code)
  LEFT JOIN realty_offer_types ROT ON (ROT.code = R.offer_type_code)
  LEFT JOIN address_objects AO ON (AO.id = R.address_object_id)
  LEFT JOIN dict_ap_schemes DAS ON (DAS.id = R.ap_scheme_id AND DAS.delete_date IS NULL)
  LEFT JOIN dict_balconies DBL ON (DBL.id = R.balcony_id AND DBL.delete_date IS NULL)
  LEFT JOIN dict_bathrooms DBR ON (DBR.id = R.bathroom_id AND DBR.delete_date IS NULL)
  LEFT JOIN dict_conditions DC ON (DC.id = R.condition_id AND DC.delete_date IS NULL)
  LEFT JOIN dict_house_types DHT ON (DHT.id = R.house_type_id AND DHT.delete_date IS NULL)
  LEFT JOIN dict_room_schemes DRS ON (DRS.id = R.room_scheme_id AND DRS.delete_date IS NULL)
  WHERE R.id = $1;

  /*
  IF (x_fts_rec.text IS NULL OR x_fts_text = '') THEN
    RETURN NULL;
  END IF;
  */

  RETURN
    -- setweight(to_tsvector('russian', x_fts_rec.geo), 'A') ||
    setweight(to_tsvector('russian', x_fts_rec.title), 'B') ||
    setweight(to_tsvector('russian', x_fts_rec.addr), 'C') ||
    setweight(strip(to_tsvector('russian', x_fts_rec.text)),'D')
    -- strip(to_tsvector('russian', x_fts_rec.title)||to_tsvector('russian', x_fts_rec.addr)||to_tsvector('russian',x_fts_rec.text))
  ;

END;
$_$;


--
-- Name: _query_keywords_refresh(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION _query_keywords_refresh() RETURNS void
    LANGUAGE plpgsql
    AS $_$
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
$_$;


--
-- Name: clients_additional_phones_chk(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION clients_additional_phones_chk() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
  x_phone_num VARCHAR;
BEGIN
  FOREACH x_phone_num IN ARRAY NEW.additional_phones LOOP
    IF NOT (x_phone_num ~ '^\d{10}$') THEN
      RAISE EXCEPTION 'Invalid phone number: %', phone_num;
      RETURN NULL;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$_$;


--
-- Name: realty_before_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION realty_before_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Заполним price
  NEW.price = COALESCE(NEW.agency_price, NEW.owner_price);

  RETURN NEW;
END;
$$;


--
-- Name: realty_before_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION realty_before_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Изменение состояния
  IF OLD.state_code != NEW.state_code THEN
    -- Обновим дату изменения состояния
    NEW.state_change_date = now();
  END IF;

  NEW.price = COALESCE(NEW.agency_price, NEW.owner_price);
  -- Изменение цены
  IF COALESCE(OLD.price, 0) != COALESCE(NEW.price, 0) THEN
      NEW.price_change_date = now();
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: realty_owner_phones_chk(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION realty_owner_phones_chk() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
  x_phone_num VARCHAR;
BEGIN
  FOREACH x_phone_num IN ARRAY NEW.owner_phones LOOP
    IF NOT (x_phone_num ~ '^\d{10}$') THEN
      RAISE EXCEPTION 'Invalid phone number: %', phone_num;
      RETURN NULL;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$_$;


--
-- Name: realty_update_fts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION realty_update_fts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  --UPDATE realty SET fts = _get_realty_fts(NEW.id) WHERE id = NEW.id;
  UPDATE realty SET fts = to_tsvector('russian', description) WHERE id = NEW.id;

  RETURN NEW;
END;
$$;


--
-- Name: realty_update_geo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION realty_update_geo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL) THEN
    UPDATE realty SET geocoords = ST_GeographyFromText('SRID=4326;POINT('||NEW.longitude||' '||NEW.latitude||')') WHERE id = NEW.id;
    UPDATE realty R SET landmarks = COALESCE((SELECT array_agg(L.id) FROM landmarks L WHERE L.delete_date IS NULL AND ST_Covers(L.geodata::geography, R.geocoords)), '{}') WHERE id = NEW.id;
  ELSE
    UPDATE realty SET geocoords = NULL, landmarks = '{}' WHERE id = NEW.id;
  END IF;
  
  RETURN NULL;
END;
$$;


--
-- Name: sms_messages_update_status_change_date(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION sms_messages_update_status_change_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.status_change_date = now();
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: _query_cache; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE _query_cache (
    id integer NOT NULL,
    query character varying NOT NULL,
    add_date timestamp(0) with time zone DEFAULT now() NOT NULL,
    params json NOT NULL
);


--
-- Name: COLUMN _query_cache.query; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN _query_cache.query IS 'Запрос';


--
-- Name: COLUMN _query_cache.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN _query_cache.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN _query_cache.params; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN _query_cache.params IS 'Распознанные параметры';


--
-- Name: _query_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE _query_cache_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: _query_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE _query_cache_id_seq OWNED BY _query_cache.id;


--
-- Name: _runtime_params; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE _runtime_params (
    key character varying NOT NULL,
    value json DEFAULT '{}'::json NOT NULL,
    ts timestamp with time zone
);


--
-- Name: COLUMN _runtime_params.key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN _runtime_params.key IS 'Имя параметра (ключ)';


--
-- Name: COLUMN _runtime_params.value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN _runtime_params.value IS 'Значение';


--
-- Name: COLUMN _runtime_params.ts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN _runtime_params.ts IS 'Некоторое значение времени';


--
-- Name: address_objects; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE address_objects (
    id integer NOT NULL,
    guid character varying(36) NOT NULL,
    aoid character varying(36) NOT NULL,
    region_code character varying(2) NOT NULL,
    postal_code character varying(6),
    name character varying(120) NOT NULL,
    official_name character varying(120) NOT NULL,
    short_type character varying(10) NOT NULL,
    full_type character varying(50) NOT NULL,
    level integer NOT NULL,
    parent_guid character varying(36),
    prev_aoid character varying(36),
    next_aoid character varying(36),
    code character varying(17),
    plain_code character varying(15),
    act_status integer NOT NULL,
    curr_status integer NOT NULL,
    start_date date NOT NULL,
    update_date date NOT NULL,
    end_date date,
    expanded_name character varying(255),
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    fts tsvector,
    fts2 tsvector,
    fts3 tsvector
);
ALTER TABLE ONLY address_objects ALTER COLUMN postal_code SET STATISTICS 0;


--
-- Name: TABLE address_objects; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE address_objects IS 'Справочник адресов в формате ФИАС';


--
-- Name: COLUMN address_objects.guid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.guid IS 'Глобальный уникальный идентификатор адресного объекта';


--
-- Name: COLUMN address_objects.aoid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.aoid IS 'Уникальный идентификатор записи (ФИАС)';


--
-- Name: COLUMN address_objects.region_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.region_code IS 'Код региона';


--
-- Name: COLUMN address_objects.postal_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.postal_code IS 'Почтовый индекс';


--
-- Name: COLUMN address_objects.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.name IS 'Формализованное наименование';


--
-- Name: COLUMN address_objects.official_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.official_name IS 'Официальное наименование';


--
-- Name: COLUMN address_objects.short_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.short_type IS 'Краткое наименование типа объекта';


--
-- Name: COLUMN address_objects.full_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.full_type IS 'Полное наименование типа объекта';


--
-- Name: COLUMN address_objects.level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.level IS 'Уровень адресного объекта';


--
-- Name: COLUMN address_objects.parent_guid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.parent_guid IS 'Идентификатор объекта родительского объекта';


--
-- Name: COLUMN address_objects.prev_aoid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.prev_aoid IS 'Идентификатор записи связывания с предыдушей исторической записью (ФИАС)';


--
-- Name: COLUMN address_objects.next_aoid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.next_aoid IS 'Идентификатор записи связывания с последующей исторической записью (ФИАС)';


--
-- Name: COLUMN address_objects.code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.code IS 'Код адресного объекта одной строкой с признаком актуальности из КЛАДР 4.0';


--
-- Name: COLUMN address_objects.plain_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.plain_code IS 'Код адресного объекта из КЛАДР 4.0 одной строкой без признака актуальности (последних двух цифр)';


--
-- Name: COLUMN address_objects.act_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.act_status IS 'Статус актуальности адресного объекта ФИАС';


--
-- Name: COLUMN address_objects.curr_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.curr_status IS 'Статус актуальности КЛАДР 4 (последние две цифры в коде)';


--
-- Name: COLUMN address_objects.start_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.start_date IS 'Начало действия записи';


--
-- Name: COLUMN address_objects.update_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.update_date IS 'Дата  внесения (обновления) записи';


--
-- Name: COLUMN address_objects.end_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.end_date IS 'Окончание действия записи';


--
-- Name: COLUMN address_objects.expanded_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.expanded_name IS 'Развернутое имя объекта';


--
-- Name: COLUMN address_objects.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.keywords IS 'Ключевые слова';


--
-- Name: COLUMN address_objects.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.metadata IS 'Метаданные';


--
-- Name: COLUMN address_objects.fts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.fts IS 'Данные для полнотекстового поиска (только имя)';


--
-- Name: COLUMN address_objects.fts2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.fts2 IS 'Данные для полнотекстового поиска (имя + тип)';


--
-- Name: COLUMN address_objects.fts3; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN address_objects.fts3 IS 'Данные для полнотекстового поиска (simple конфигурация)';


--
-- Name: address_objects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE address_objects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: address_objects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE address_objects_id_seq OWNED BY address_objects.id;


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE clients (
    id integer NOT NULL,
    name character varying(64),
    login character varying(24),
    password character varying(32),
    phone_num character varying(10) NOT NULL,
    email character varying(64),
    additional_phones character varying(10)[] DEFAULT '{}'::character varying[] NOT NULL,
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    last_signin_date timestamp with time zone,
    description text,
    CONSTRAINT clients_delete_date_chk CHECK ((delete_date >= add_date)),
    CONSTRAINT clients_email_chk CHECK (((email)::text ~ '^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$'::text)),
    CONSTRAINT clients_phone_num_chk CHECK (((phone_num)::text ~ '^\d{10}$'::text))
);


--
-- Name: TABLE clients; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE clients IS 'Клиенты';


--
-- Name: COLUMN clients.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.name IS 'Имя';


--
-- Name: COLUMN clients.login; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.login IS 'Логин';


--
-- Name: COLUMN clients.password; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.password IS 'Пароль';


--
-- Name: COLUMN clients.phone_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.phone_num IS 'Основной номер телефона';


--
-- Name: COLUMN clients.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.email IS 'Email';


--
-- Name: COLUMN clients.additional_phones; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.additional_phones IS 'Дополнительные телефоны';


--
-- Name: COLUMN clients.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.metadata IS 'Метаданные';


--
-- Name: COLUMN clients.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN clients.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.delete_date IS 'Дата/время удаления';


--
-- Name: COLUMN clients.last_signin_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.last_signin_date IS 'Дата/время последнего входа';


--
-- Name: COLUMN clients.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN clients.description IS 'Дополнительная информация по клиенту';


--
-- Name: clients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE clients_id_seq OWNED BY clients.id;


--
-- Name: dict_ap_schemes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dict_ap_schemes (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE dict_ap_schemes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE dict_ap_schemes IS 'Справочник планировок квартир';


--
-- Name: COLUMN dict_ap_schemes.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_ap_schemes.name IS 'Название';


--
-- Name: COLUMN dict_ap_schemes.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_ap_schemes.keywords IS 'Ключевые слова';


--
-- Name: COLUMN dict_ap_schemes.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_ap_schemes.metadata IS 'Метаданные';


--
-- Name: COLUMN dict_ap_schemes.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_ap_schemes.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN dict_ap_schemes.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_ap_schemes.delete_date IS 'Дата/время удаления';


--
-- Name: dict_ap_schemes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dict_ap_schemes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dict_ap_schemes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dict_ap_schemes_id_seq OWNED BY dict_ap_schemes.id;


--
-- Name: dict_balconies; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dict_balconies (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE dict_balconies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE dict_balconies IS 'Справочник описаний балконов и лоджий';


--
-- Name: COLUMN dict_balconies.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_balconies.name IS 'Название';


--
-- Name: COLUMN dict_balconies.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_balconies.keywords IS 'Ключевые слова';


--
-- Name: COLUMN dict_balconies.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_balconies.metadata IS 'Метаданные';


--
-- Name: COLUMN dict_balconies.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_balconies.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN dict_balconies.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_balconies.delete_date IS 'Дата/время удаления';


--
-- Name: dict_balconies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dict_balconies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dict_balconies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dict_balconies_id_seq OWNED BY dict_balconies.id;


--
-- Name: dict_bathrooms; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dict_bathrooms (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE dict_bathrooms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE dict_bathrooms IS 'Справочник описаний санузлов';


--
-- Name: COLUMN dict_bathrooms.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_bathrooms.name IS 'Название';


--
-- Name: COLUMN dict_bathrooms.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_bathrooms.keywords IS 'Ключевые слова';


--
-- Name: COLUMN dict_bathrooms.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_bathrooms.metadata IS 'Метаданные';


--
-- Name: COLUMN dict_bathrooms.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_bathrooms.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN dict_bathrooms.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_bathrooms.delete_date IS 'Дата/время удаления';


--
-- Name: dict_bathrooms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dict_bathrooms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dict_bathrooms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dict_bathrooms_id_seq OWNED BY dict_bathrooms.id;


--
-- Name: dict_conditions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dict_conditions (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE dict_conditions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE dict_conditions IS 'Справочник состояний';


--
-- Name: COLUMN dict_conditions.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_conditions.name IS 'Название';


--
-- Name: COLUMN dict_conditions.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_conditions.keywords IS 'Ключевые слова';


--
-- Name: COLUMN dict_conditions.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_conditions.metadata IS 'Метаданные';


--
-- Name: COLUMN dict_conditions.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_conditions.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN dict_conditions.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_conditions.delete_date IS 'Дата/время удаления';


--
-- Name: dict_conditions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dict_conditions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dict_conditions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dict_conditions_id_seq OWNED BY dict_conditions.id;


--
-- Name: dict_house_types; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dict_house_types (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE dict_house_types; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE dict_house_types IS 'Справочник типов домов (кирпичный, панельный и т.д.)';


--
-- Name: COLUMN dict_house_types.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_house_types.name IS 'Название';


--
-- Name: COLUMN dict_house_types.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_house_types.keywords IS 'Ключевые слова';


--
-- Name: COLUMN dict_house_types.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_house_types.metadata IS 'Метаданные';


--
-- Name: COLUMN dict_house_types.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_house_types.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN dict_house_types.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_house_types.delete_date IS 'Дата/время удаления';


--
-- Name: dict_house_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dict_house_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dict_house_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dict_house_types_id_seq OWNED BY dict_house_types.id;


--
-- Name: dict_room_schemes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dict_room_schemes (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE dict_room_schemes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE dict_room_schemes IS 'Справочник планировок комнат';


--
-- Name: COLUMN dict_room_schemes.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_room_schemes.name IS 'Название';


--
-- Name: COLUMN dict_room_schemes.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_room_schemes.keywords IS 'Ключевые слова';


--
-- Name: COLUMN dict_room_schemes.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_room_schemes.metadata IS 'Метаданные';


--
-- Name: COLUMN dict_room_schemes.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_room_schemes.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN dict_room_schemes.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN dict_room_schemes.delete_date IS 'Дата/время удаления';


--
-- Name: dict_room_schemes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dict_room_schemes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dict_room_schemes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dict_room_schemes_id_seq OWNED BY dict_room_schemes.id;


--
-- Name: landmarks; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE landmarks (
    id integer NOT NULL,
    type character varying(16) NOT NULL,
    name character varying(64) NOT NULL,
    keywords character varying(128),
    geodata postgis.geometry(MultiPolygon,4326),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    change_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    geojson json NOT NULL,
    center json NOT NULL,
    zoom integer NOT NULL,
    grp character varying(64),
    grp_pos integer,
    CONSTRAINT landmarks_change_date_chk CHECK ((change_date >= add_date)),
    CONSTRAINT landmarks_delete_date_chk CHECK ((delete_date >= add_date)),
    CONSTRAINT landmarks_geodata_chk CHECK (postgis.st_isvalid(geodata))
);


--
-- Name: COLUMN landmarks.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.type IS 'Тип (landmark, sublandmark, etc)';


--
-- Name: COLUMN landmarks.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.name IS 'Название';


--
-- Name: COLUMN landmarks.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.keywords IS 'Ключевые слова для поиска';


--
-- Name: COLUMN landmarks.geodata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.geodata IS 'PostGIS данные';


--
-- Name: COLUMN landmarks.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.metadata IS 'Метаданные';


--
-- Name: COLUMN landmarks.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN landmarks.change_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.change_date IS 'Дата/время последнего изменения';


--
-- Name: COLUMN landmarks.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.delete_date IS 'Дата/время удаления';


--
-- Name: COLUMN landmarks.geojson; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.geojson IS 'GeoJSON данные';


--
-- Name: COLUMN landmarks.center; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.center IS 'Leaflet LatLng объект';


--
-- Name: COLUMN landmarks.zoom; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.zoom IS 'Zoom карты во время сохранения';


--
-- Name: COLUMN landmarks.grp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.grp IS 'Группа, к которой принадлежит ориентир';


--
-- Name: COLUMN landmarks.grp_pos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN landmarks.grp_pos IS 'Позиция внутри группы (NULL - макс)';


--
-- Name: landmarks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE landmarks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: landmarks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE landmarks_id_seq OWNED BY landmarks.id;


--
-- Name: media; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE media (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    code character varying(32) NOT NULL,
    type character varying(8) NOT NULL,
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    CONSTRAINT media_type_chk CHECK (((type)::text = ANY (ARRAY[('import'::character varying)::text, ('export'::character varying)::text])))
);


--
-- Name: TABLE media; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE media IS 'Справочник СМИ';


--
-- Name: COLUMN media.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media.name IS 'Наименование СМИ (газеты, сайта и пр.)';


--
-- Name: COLUMN media.code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media.code IS 'Уникальный код для данного типа';


--
-- Name: COLUMN media.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media.type IS 'Тип: import/export';


--
-- Name: COLUMN media.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media.metadata IS 'Метаданные';


--
-- Name: COLUMN media.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN media.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media.delete_date IS 'Дата/время удаления';


--
-- Name: media_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE media_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE media_id_seq OWNED BY media.id;


--
-- Name: media_import_history; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE media_import_history (
    id integer NOT NULL,
    media_id integer NOT NULL,
    media_num character varying(16),
    media_text text NOT NULL,
    realty_id integer NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE media_import_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE media_import_history IS 'История импорта объектов недвижимости из СМИ';


--
-- Name: COLUMN media_import_history.media_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media_import_history.media_id IS 'Источник СМИ';


--
-- Name: COLUMN media_import_history.media_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media_import_history.media_num IS 'Номер, в котором вышло объявление';


--
-- Name: COLUMN media_import_history.media_text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media_import_history.media_text IS 'Тест объявления';


--
-- Name: COLUMN media_import_history.realty_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media_import_history.realty_id IS 'Связанный объект недвижимости';


--
-- Name: COLUMN media_import_history.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN media_import_history.add_date IS 'Дата/время добавления (импорта)';


--
-- Name: media_import_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE media_import_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: media_import_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE media_import_history_id_seq OWNED BY media_import_history.id;


--
-- Name: mediator_companies; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE mediator_companies (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE mediator_companies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE mediator_companies IS 'Справочник компаний посредников';


--
-- Name: COLUMN mediator_companies.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediator_companies.name IS 'Название';


--
-- Name: COLUMN mediator_companies.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediator_companies.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN mediator_companies.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediator_companies.delete_date IS 'Дата/время удаления';


--
-- Name: mediator_companies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE mediator_companies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mediator_companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE mediator_companies_id_seq OWNED BY mediator_companies.id;


--
-- Name: mediators; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE mediators (
    id integer NOT NULL,
    company_id integer NOT NULL,
    name character varying(64),
    phone_num character varying(10) NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    CONSTRAINT mediators_phone_num_chk CHECK (((phone_num)::text ~ '^\d{10}$'::text))
);


--
-- Name: TABLE mediators; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE mediators IS 'Справочник посредников';


--
-- Name: COLUMN mediators.company_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediators.company_id IS 'Компания';


--
-- Name: COLUMN mediators.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediators.name IS 'Кому принадлежит номер (Агент/Офис/и т.д.)';


--
-- Name: COLUMN mediators.phone_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediators.phone_num IS 'Номер телефона';


--
-- Name: COLUMN mediators.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediators.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN mediators.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN mediators.delete_date IS 'Дата/время удаления';


--
-- Name: mediators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE mediators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mediators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE mediators_id_seq OWNED BY mediators.id;


--
-- Name: photos; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE photos (
    id integer NOT NULL,
    realty_id integer NOT NULL,
    filename character varying(64) NOT NULL,
    thumbnail_filename character varying(96) NOT NULL,
    is_main boolean DEFAULT false NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE photos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE photos IS 'Фотографии недвижимости';


--
-- Name: COLUMN photos.realty_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN photos.realty_id IS 'Объект недвижимости';


--
-- Name: COLUMN photos.filename; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN photos.filename IS 'Имя файла с оригинальной фотографией';


--
-- Name: COLUMN photos.thumbnail_filename; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN photos.thumbnail_filename IS 'Имя файла с миниатюрой';


--
-- Name: COLUMN photos.is_main; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN photos.is_main IS 'Фотография обложки или нет';


--
-- Name: COLUMN photos.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN photos.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN photos.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN photos.delete_date IS 'Дата/время удаления';


--
-- Name: photos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE photos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: photos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE photos_id_seq OWNED BY photos.id;


--
-- Name: query_keywords; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE query_keywords (
    ftype character varying(32) NOT NULL,
    fkey integer NOT NULL,
    fval character varying NOT NULL,
    fts tsvector
);


--
-- Name: COLUMN query_keywords.ftype; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN query_keywords.ftype IS 'Тип внешнего поля';


--
-- Name: COLUMN query_keywords.fkey; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN query_keywords.fkey IS 'Внешний ключ';


--
-- Name: COLUMN query_keywords.fval; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN query_keywords.fval IS 'Значение';


--
-- Name: COLUMN query_keywords.fts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN query_keywords.fts IS 'Данные для полнотекстового поиска';


--
-- Name: realty; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE realty (
    id integer NOT NULL,
    type_code character varying(32) NOT NULL,
    offer_type_code character varying(16) NOT NULL,
    state_code character varying(25) DEFAULT 'raw'::character varying NOT NULL,
    state_change_date timestamp with time zone DEFAULT now() NOT NULL,
    address_object_id integer,
    house_num character varying(10),
    house_type_id integer,
    ap_num integer,
    ap_scheme_id integer,
    rooms_count integer,
    rooms_offer_count integer,
    room_scheme_id integer,
    floor integer,
    floors_count integer,
    levels_count integer,
    condition_id integer,
    balcony_id integer,
    bathroom_id integer,
    square_total real,
    square_living real,
    square_kitchen real,
    square_land real,
    square_land_type character varying(7),
    description text,
    source_media_id integer,
    source_media_text text,
    creator_id integer,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    change_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    owner_id integer,
    owner_phones character varying(10)[] NOT NULL,
    owner_info text,
    owner_price real,
    work_info text,
    agent_id integer,
    agency_price real,
    price real,
    price_change_date timestamp with time zone,
    buyer_id integer,
    final_price real,
    latitude numeric,
    longitude numeric,
    geocoords postgis.geography(Point,4326),
    sublandmark_id integer,
    landmarks integer[] DEFAULT '{}'::integer[] NOT NULL,
    tags integer[] DEFAULT '{}'::integer[] NOT NULL,
    export_media character varying(16)[] DEFAULT '{}'::integer[] NOT NULL,
    metadata json DEFAULT '{}'::json NOT NULL,
    fts tsvector,
    CONSTRAINT realty_agency_price_chk CHECK ((agency_price > (0)::double precision)),
    CONSTRAINT realty_floor_chk CHECK ((((floors_count > 0) AND (floors_count <= 100)) AND (floor <= floors_count))),
    CONSTRAINT realty_levels_count_chk CHECK ((levels_count > 0)),
    CONSTRAINT realty_owner_phones_length_chk CHECK ((array_length(owner_phones, 1) > 0)),
    CONSTRAINT realty_owner_price_chk CHECK ((owner_price > (0)::double precision)),
    CONSTRAINT realty_rooms_count_chk CHECK ((rooms_count > 0)),
    CONSTRAINT realty_rooms_offer_count_chk CHECK ((rooms_offer_count > 0)),
    CONSTRAINT realty_square_kitchen_chk CHECK ((square_kitchen > (0)::double precision)),
    CONSTRAINT realty_square_land_chk CHECK ((square_land > (0)::double precision)),
    CONSTRAINT realty_square_land_type_chk CHECK (((square_land_type)::text = ANY (ARRAY[('ar'::character varying)::text, ('hectare'::character varying)::text]))),
    CONSTRAINT realty_square_living_chk CHECK ((square_living > (0)::double precision)),
    CONSTRAINT realty_square_total_chk CHECK ((square_total > (0)::double precision)),
    CONSTRAINT realty_squares_chk CHECK (((square_living <= square_total) AND (square_kitchen <= square_total)))
);


--
-- Name: TABLE realty; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE realty IS 'Объекты недвижимости';


--
-- Name: COLUMN realty.type_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.type_code IS 'Тип недвижимости';


--
-- Name: COLUMN realty.offer_type_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.offer_type_code IS 'Тип предложения';


--
-- Name: COLUMN realty.state_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.state_code IS 'Состояние объекта';


--
-- Name: COLUMN realty.state_change_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.state_change_date IS 'Дата/время последней смены состояния объекта';


--
-- Name: COLUMN realty.address_object_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.address_object_id IS 'Адресный объект';


--
-- Name: COLUMN realty.house_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.house_num IS 'Номер дома';


--
-- Name: COLUMN realty.house_type_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.house_type_id IS 'Тип дома';


--
-- Name: COLUMN realty.ap_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.ap_num IS 'Номер квартиры';


--
-- Name: COLUMN realty.ap_scheme_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.ap_scheme_id IS 'Планировка квартиры';


--
-- Name: COLUMN realty.rooms_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.rooms_count IS 'Количество комнат';


--
-- Name: COLUMN realty.rooms_offer_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.rooms_offer_count IS 'Количество предлагаемых комнат';


--
-- Name: COLUMN realty.room_scheme_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.room_scheme_id IS 'Планировка комнат';


--
-- Name: COLUMN realty.floor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.floor IS 'Этаж';


--
-- Name: COLUMN realty.floors_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.floors_count IS 'Количество этажей';


--
-- Name: COLUMN realty.levels_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.levels_count IS 'Этажность квартиры (для элитного жилья)';


--
-- Name: COLUMN realty.condition_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.condition_id IS 'Состояние';


--
-- Name: COLUMN realty.balcony_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.balcony_id IS 'Описание балкона(ов)';


--
-- Name: COLUMN realty.bathroom_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.bathroom_id IS 'Описание санузла(ов)';


--
-- Name: COLUMN realty.square_total; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.square_total IS 'Общая площадь';


--
-- Name: COLUMN realty.square_living; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.square_living IS 'Жилая площадь';


--
-- Name: COLUMN realty.square_kitchen; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.square_kitchen IS 'Площадь кухни';


--
-- Name: COLUMN realty.square_land; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.square_land IS 'Площадь земельного участка';


--
-- Name: COLUMN realty.square_land_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.square_land_type IS 'Тип площади земельного участка:
  ar - сотка
  hectare - гектар';


--
-- Name: COLUMN realty.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.description IS 'Дополнительное описание';


--
-- Name: COLUMN realty.source_media_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.source_media_id IS 'Источник СМИ, из которого вытянуто объявление';


--
-- Name: COLUMN realty.source_media_text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.source_media_text IS 'Исходный текст объявления';


--
-- Name: COLUMN realty.creator_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.creator_id IS 'Пользователь, зарегистрировавший недвижимость (null - система)';


--
-- Name: COLUMN realty.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN realty.change_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.change_date IS 'Дата/время изменения';


--
-- Name: COLUMN realty.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.delete_date IS 'Дата/время удаления';


--
-- Name: COLUMN realty.owner_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.owner_id IS 'Собственник';


--
-- Name: COLUMN realty.owner_phones; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.owner_phones IS 'Контактные телефоны собственника данного объекта недвижимости';


--
-- Name: COLUMN realty.owner_info; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.owner_info IS 'Доп. информация от собственника (контакты, удобное время звонка, и т.д.)';


--
-- Name: COLUMN realty.owner_price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.owner_price IS 'Цена собственника';


--
-- Name: COLUMN realty.work_info; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.work_info IS 'Доп. информация по продаже недвижимости';


--
-- Name: COLUMN realty.agent_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.agent_id IS 'Агент, за которым закреплен данный объект недвижимости';


--
-- Name: COLUMN realty.agency_price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.agency_price IS 'Цена агентства';


--
-- Name: COLUMN realty.price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.price IS 'COALESCE(agency_price, owner_price)';


--
-- Name: COLUMN realty.price_change_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.price_change_date IS 'Дата/время последнего изменения цены';


--
-- Name: COLUMN realty.buyer_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.buyer_id IS 'Покупатель';


--
-- Name: COLUMN realty.final_price; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.final_price IS 'Цена продажи по факту';


--
-- Name: COLUMN realty.latitude; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.latitude IS 'Широта';


--
-- Name: COLUMN realty.longitude; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.longitude IS 'Долгота';


--
-- Name: COLUMN realty.geocoords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.geocoords IS 'Географические координаты';


--
-- Name: COLUMN realty.sublandmark_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.sublandmark_id IS 'Подориентир';


--
-- Name: COLUMN realty.landmarks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.landmarks IS 'Ориентиры, в которые попадает объект';


--
-- Name: COLUMN realty.tags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.tags IS 'Теги';


--
-- Name: COLUMN realty.export_media; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.export_media IS 'В какие источники экспортировать недвижимость (объявления)';


--
-- Name: COLUMN realty.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.metadata IS 'Метаданные';


--
-- Name: COLUMN realty.fts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty.fts IS 'tsvector описания';


--
-- Name: CONSTRAINT realty_floor_chk ON realty; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT realty_floor_chk ON realty IS 'Максимум 100 этажей';


--
-- Name: CONSTRAINT realty_square_land_type_chk ON realty; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT realty_square_land_type_chk ON realty IS 'square_land_type IN (''ar'', ''hectare'')';


--
-- Name: realty_categories; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE realty_categories (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    code character varying(16) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL
);


--
-- Name: TABLE realty_categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE realty_categories IS 'Справочник категорий недвижимости';


--
-- Name: COLUMN realty_categories.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_categories.name IS 'Название';


--
-- Name: COLUMN realty_categories.code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_categories.code IS 'Уникальный код';


--
-- Name: COLUMN realty_categories.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_categories.metadata IS 'Метаданные';


--
-- Name: realty_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE realty_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: realty_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE realty_id_seq OWNED BY realty.id;


--
-- Name: realty_offer_types; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE realty_offer_types (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    code character varying(16) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL
);


--
-- Name: TABLE realty_offer_types; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE realty_offer_types IS 'Справочник типов предложений по недвижимости';


--
-- Name: COLUMN realty_offer_types.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_offer_types.name IS 'Название';


--
-- Name: COLUMN realty_offer_types.code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_offer_types.code IS 'Код';


--
-- Name: COLUMN realty_offer_types.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_offer_types.keywords IS 'Ключевые слова';


--
-- Name: COLUMN realty_offer_types.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_offer_types.metadata IS 'Метаданные';


--
-- Name: realty_states; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE realty_states (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    code character varying(16) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL
);


--
-- Name: COLUMN realty_states.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_states.name IS 'Название';


--
-- Name: COLUMN realty_states.code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_states.code IS 'Код';


--
-- Name: COLUMN realty_states.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_states.keywords IS 'Ключевые слова';


--
-- Name: COLUMN realty_states.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_states.metadata IS 'Метаданные';


--
-- Name: realty_types; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE realty_types (
    id integer NOT NULL,
    category_code character varying NOT NULL,
    name character varying(32) NOT NULL,
    code character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL
);


--
-- Name: TABLE realty_types; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE realty_types IS 'Справочник типов недвижимости по категориям';


--
-- Name: COLUMN realty_types.category_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_types.category_code IS 'Категория';


--
-- Name: COLUMN realty_types.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_types.name IS 'Название';


--
-- Name: COLUMN realty_types.code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_types.code IS 'Код';


--
-- Name: COLUMN realty_types.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_types.keywords IS 'Ключевые слова';


--
-- Name: COLUMN realty_types.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN realty_types.metadata IS 'Метаданные';


--
-- Name: sms_messages; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE sms_messages (
    id integer NOT NULL,
    phone_num character varying(10) NOT NULL,
    text text NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    status character varying(10) DEFAULT 'queued'::character varying NOT NULL,
    status_change_date timestamp with time zone DEFAULT now() NOT NULL,
    attempts_count integer DEFAULT 0 NOT NULL,
    last_error_msg character varying(512),
    metadata json DEFAULT '{}'::json NOT NULL,
    CONSTRAINT sms_messages_phone_num_chk CHECK (((phone_num)::text ~ '^9\d{9}$'::text)),
    CONSTRAINT sms_messages_status_chk CHECK (((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('sent'::character varying)::text, ('delivered'::character varying)::text, ('error'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: TABLE sms_messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE sms_messages IS 'Отправленные СМС сообщения';


--
-- Name: COLUMN sms_messages.phone_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.phone_num IS 'Номер телефона';


--
-- Name: COLUMN sms_messages.text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.text IS 'Текст СМС сообщения';


--
-- Name: COLUMN sms_messages.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.add_date IS 'Дата/время добавления сообщения';


--
-- Name: COLUMN sms_messages.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.status IS 'Статус сообщения:
  queued - отправка запланирована
  sent - отправлено
  delivered - доставлено
  error - ошибка
  cancelled - отменено';


--
-- Name: COLUMN sms_messages.status_change_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.status_change_date IS 'Дата/время последнего обновления статуса сообщения';


--
-- Name: COLUMN sms_messages.attempts_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.attempts_count IS 'Количество попыток отправки';


--
-- Name: COLUMN sms_messages.last_error_msg; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.last_error_msg IS 'Последнее сообщение об ошибке';


--
-- Name: COLUMN sms_messages.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN sms_messages.metadata IS 'Метаданные';


--
-- Name: CONSTRAINT sms_messages_status_chk ON sms_messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT sms_messages_status_chk ON sms_messages IS 'status IN (''queued'', ''sent'', ''delivered'', ''error'', ''cancelled'')';


--
-- Name: sms_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE sms_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sms_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE sms_messages_id_seq OWNED BY sms_messages.id;


--
-- Name: subscription_realty; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE subscription_realty (
    id integer NOT NULL,
    subscription_id integer NOT NULL,
    realty_id integer NOT NULL,
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: TABLE subscription_realty; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE subscription_realty IS 'Подобранная недвижимость по подписке';


--
-- Name: COLUMN subscription_realty.subscription_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscription_realty.subscription_id IS 'Подписка';


--
-- Name: COLUMN subscription_realty.realty_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscription_realty.realty_id IS 'Объект недвижимости';


--
-- Name: COLUMN subscription_realty.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscription_realty.metadata IS 'Метаданные';


--
-- Name: COLUMN subscription_realty.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscription_realty.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN subscription_realty.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscription_realty.delete_date IS 'Дата/время удаления';


--
-- Name: subscription_realty_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE subscription_realty_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_realty_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE subscription_realty_id_seq OWNED BY subscription_realty.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE subscriptions (
    id integer NOT NULL,
    client_id integer NOT NULL,
    user_id integer,
    queries character varying(256)[] NOT NULL,
    offer_type_code character varying(16) NOT NULL,
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    end_date timestamp with time zone,
    delete_date timestamp with time zone,
    last_check_date timestamp with time zone,
    realty_limit integer DEFAULT 0 NOT NULL,
    send_owner_phone boolean DEFAULT false NOT NULL,
    CONSTRAINT subscriptions_delete_date_chk CHECK ((delete_date >= add_date)),
    CONSTRAINT subscriptions_end_date_chk CHECK ((end_date >= add_date))
);


--
-- Name: TABLE subscriptions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE subscriptions IS 'Подписки';


--
-- Name: COLUMN subscriptions.client_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.client_id IS 'Клиент';


--
-- Name: COLUMN subscriptions.user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.user_id IS 'Пользователь, подписавший клиента';


--
-- Name: COLUMN subscriptions.queries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.queries IS 'Запросы';


--
-- Name: COLUMN subscriptions.offer_type_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.offer_type_code IS 'Тип запроса (продажа/аренда)';


--
-- Name: COLUMN subscriptions.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.metadata IS 'Метаданные';


--
-- Name: COLUMN subscriptions.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN subscriptions.end_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.end_date IS 'Дата/время окончания действия подписки (null - подписка не активна)';


--
-- Name: COLUMN subscriptions.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.delete_date IS 'Дата/время удаления';


--
-- Name: COLUMN subscriptions.last_check_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.last_check_date IS 'Дата/время последней проверки (поиска вариантов)';


--
-- Name: COLUMN subscriptions.realty_limit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.realty_limit IS 'Ограничение макс. количества подобранных объектов недвижимости';


--
-- Name: COLUMN subscriptions.send_owner_phone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN subscriptions.send_owner_phone IS 'Отправлять в СМС номер собственника или нет';


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE subscriptions_id_seq OWNED BY subscriptions.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tags (
    id integer NOT NULL,
    name character varying(32) NOT NULL,
    keywords character varying(128),
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone
);


--
-- Name: COLUMN tags.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tags.name IS 'Название';


--
-- Name: COLUMN tags.keywords; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tags.keywords IS 'Ключевые слова';


--
-- Name: COLUMN tags.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tags.metadata IS 'Метаданные';


--
-- Name: COLUMN tags.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tags.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN tags.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tags.delete_date IS 'Дата/время удаления';


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tags_id_seq OWNED BY tags.id;


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tasks (
    id integer NOT NULL,
    parent_task_id integer,
    creator_id integer,
    assigned_user_id integer NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    deadline_date date NOT NULL,
    remind_date timestamp with time zone,
    description text NOT NULL,
    status character varying(10) NOT NULL,
    realty_id integer,
    category character varying(32) NOT NULL,
    type character varying(3) NOT NULL,
    CONSTRAINT tasks_category_chk CHECK (((category)::text = ANY (ARRAY[('realty'::character varying)::text, ('other'::character varying)::text]))),
    CONSTRAINT tasks_chk CHECK (((((category)::text = 'realty'::text) AND (realty_id IS NOT NULL)) OR (((category)::text = 'other'::text) AND (realty_id IS NULL)))),
    CONSTRAINT tasks_date_chk CHECK (((add_date <= now()) AND (add_date <= delete_date))),
    CONSTRAINT tasks_status_chk CHECK (((status)::text = ANY (ARRAY[('scheduled'::character varying)::text, ('finished'::character varying)::text, ('cancelled'::character varying)::text]))),
    CONSTRAINT tasks_type_chk CHECK (((type)::text = ANY (ARRAY[('in'::character varying)::text, ('out'::character varying)::text])))
);


--
-- Name: TABLE tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE tasks IS 'Ежедневник';


--
-- Name: COLUMN tasks.parent_task_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.parent_task_id IS 'Родительская задача';


--
-- Name: COLUMN tasks.creator_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.creator_id IS 'Сотрудник, создавший задачу, либо система (null)';


--
-- Name: COLUMN tasks.assigned_user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.assigned_user_id IS 'Сотрудник, отвечающий за выполнение задачи';


--
-- Name: COLUMN tasks.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.add_date IS 'Дата/время добавления задачи';


--
-- Name: COLUMN tasks.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.delete_date IS 'Дата/время удаления';


--
-- Name: COLUMN tasks.deadline_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.deadline_date IS 'Дата дедлайна';


--
-- Name: COLUMN tasks.remind_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.remind_date IS 'Дата/время напоминания';


--
-- Name: COLUMN tasks.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.description IS 'Описание задачи';


--
-- Name: COLUMN tasks.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.status IS 'Статус задачи:
  scheduled - запланировано,
  finished - завершено,
  cancelled - отменено';


--
-- Name: COLUMN tasks.realty_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.realty_id IS 'Объект недвижимости, связанный с задачей';


--
-- Name: COLUMN tasks.category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.category IS 'Категория задачи (realty, other)';


--
-- Name: COLUMN tasks.type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN tasks.type IS 'Тип задачи:
  in - входящая
  out - исходящая';


--
-- Name: CONSTRAINT tasks_category_chk ON tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT tasks_category_chk ON tasks IS 'category IN (''realty'', ''other'')';


--
-- Name: CONSTRAINT tasks_chk ON tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT tasks_chk ON tasks IS '(category = ''realty'' AND realty_id IS NOT NULL) OR (category = ''other'' AND realty_id IS NULL)';


--
-- Name: CONSTRAINT tasks_date_chk ON tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT tasks_date_chk ON tasks IS 'add_date <= now() and add_date <= delete_date';


--
-- Name: CONSTRAINT tasks_status_chk ON tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT tasks_status_chk ON tasks IS 'status IN (''scheduled'', ''finished'', ''cancelled'')';


--
-- Name: CONSTRAINT tasks_type_chk ON tasks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT tasks_type_chk ON tasks IS 'type IN (''in'', ''out'')';


--
-- Name: tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tasks_id_seq OWNED BY tasks.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    login character varying(16) NOT NULL,
    password character varying NOT NULL,
    role character varying(10) NOT NULL,
    name character varying(64) NOT NULL,
    phone_num character varying(10),
    description text,
    metadata json DEFAULT '{}'::json NOT NULL,
    add_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    public_name character varying(64),
    public_phone_num character varying(16),
    permissions json DEFAULT '{}'::json NOT NULL,
    CONSTRAINT users_phone_num_chk CHECK (((phone_num)::text ~ '^\d{10}$'::text))
);


--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE users IS 'Пользователи системы';


--
-- Name: COLUMN users.login; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.login IS 'Логин';


--
-- Name: COLUMN users.password; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.password IS 'Пароль';


--
-- Name: COLUMN users.role; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.role IS 'Роль в системе';


--
-- Name: COLUMN users.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.name IS 'Имя';


--
-- Name: COLUMN users.phone_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.phone_num IS 'Номер телефона';


--
-- Name: COLUMN users.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.description IS 'Дополнительная информация';


--
-- Name: COLUMN users.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.metadata IS 'Метаданные';


--
-- Name: COLUMN users.add_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.add_date IS 'Дата/время добавления';


--
-- Name: COLUMN users.delete_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.delete_date IS 'Дата/время удаления';


--
-- Name: COLUMN users.public_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.public_name IS 'Паблик имя';


--
-- Name: COLUMN users.public_phone_num; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.public_phone_num IS 'Паблик номер телефона';


--
-- Name: COLUMN users.permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN users.permissions IS 'Локальные права пользователя';


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY _query_cache ALTER COLUMN id SET DEFAULT nextval('_query_cache_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY address_objects ALTER COLUMN id SET DEFAULT nextval('address_objects_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY clients ALTER COLUMN id SET DEFAULT nextval('clients_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dict_ap_schemes ALTER COLUMN id SET DEFAULT nextval('dict_ap_schemes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dict_balconies ALTER COLUMN id SET DEFAULT nextval('dict_balconies_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dict_bathrooms ALTER COLUMN id SET DEFAULT nextval('dict_bathrooms_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dict_conditions ALTER COLUMN id SET DEFAULT nextval('dict_conditions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dict_house_types ALTER COLUMN id SET DEFAULT nextval('dict_house_types_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dict_room_schemes ALTER COLUMN id SET DEFAULT nextval('dict_room_schemes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY landmarks ALTER COLUMN id SET DEFAULT nextval('landmarks_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY media ALTER COLUMN id SET DEFAULT nextval('media_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY media_import_history ALTER COLUMN id SET DEFAULT nextval('media_import_history_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY mediator_companies ALTER COLUMN id SET DEFAULT nextval('mediator_companies_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY mediators ALTER COLUMN id SET DEFAULT nextval('mediators_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY photos ALTER COLUMN id SET DEFAULT nextval('photos_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty ALTER COLUMN id SET DEFAULT nextval('realty_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY sms_messages ALTER COLUMN id SET DEFAULT nextval('sms_messages_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscription_realty ALTER COLUMN id SET DEFAULT nextval('subscription_realty_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions ALTER COLUMN id SET DEFAULT nextval('subscriptions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tags ALTER COLUMN id SET DEFAULT nextval('tags_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tasks ALTER COLUMN id SET DEFAULT nextval('tasks_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: _query_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY _query_cache
    ADD CONSTRAINT _query_cache_pkey PRIMARY KEY (id);


--
-- Name: _runtime_params_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY _runtime_params
    ADD CONSTRAINT _runtime_params_pkey PRIMARY KEY (key);


--
-- Name: address_objects_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY address_objects
    ADD CONSTRAINT address_objects_pkey PRIMARY KEY (id);


--
-- Name: clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: dict_ap_schemes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dict_ap_schemes
    ADD CONSTRAINT dict_ap_schemes_pkey PRIMARY KEY (id);


--
-- Name: dict_balconies_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dict_balconies
    ADD CONSTRAINT dict_balconies_pkey PRIMARY KEY (id);


--
-- Name: dict_bathrooms_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dict_bathrooms
    ADD CONSTRAINT dict_bathrooms_pkey PRIMARY KEY (id);


--
-- Name: dict_conditions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dict_conditions
    ADD CONSTRAINT dict_conditions_pkey PRIMARY KEY (id);


--
-- Name: dict_house_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dict_house_types
    ADD CONSTRAINT dict_house_types_pkey PRIMARY KEY (id);


--
-- Name: dict_room_schemes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dict_room_schemes
    ADD CONSTRAINT dict_room_schemes_pkey PRIMARY KEY (id);


--
-- Name: landmarks_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY landmarks
    ADD CONSTRAINT landmarks_pkey PRIMARY KEY (id);


--
-- Name: media_import_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY media_import_history
    ADD CONSTRAINT media_import_history_pkey PRIMARY KEY (id);


--
-- Name: media_import_history_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY media_import_history
    ADD CONSTRAINT media_import_history_uniq UNIQUE (media_id, realty_id, media_num);


--
-- Name: media_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY media
    ADD CONSTRAINT media_pkey PRIMARY KEY (id);


--
-- Name: mediator_companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY mediator_companies
    ADD CONSTRAINT mediator_companies_pkey PRIMARY KEY (id);


--
-- Name: mediators_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY mediators
    ADD CONSTRAINT mediators_pkey PRIMARY KEY (id);


--
-- Name: photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY photos
    ADD CONSTRAINT photos_pkey PRIMARY KEY (id);


--
-- Name: query_keywords_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY query_keywords
    ADD CONSTRAINT query_keywords_pkey PRIMARY KEY (ftype, fkey, fval);


--
-- Name: realty_categories_code_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_categories
    ADD CONSTRAINT realty_categories_code_uniq UNIQUE (code);


--
-- Name: realty_categories_name_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_categories
    ADD CONSTRAINT realty_categories_name_uniq UNIQUE (name);


--
-- Name: realty_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_categories
    ADD CONSTRAINT realty_categories_pkey PRIMARY KEY (id);


--
-- Name: realty_offer_types_code_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_offer_types
    ADD CONSTRAINT realty_offer_types_code_key UNIQUE (code);


--
-- Name: realty_offer_types_name_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_offer_types
    ADD CONSTRAINT realty_offer_types_name_key UNIQUE (name);


--
-- Name: realty_offer_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_offer_types
    ADD CONSTRAINT realty_offer_types_pkey PRIMARY KEY (id);


--
-- Name: realty_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_pkey PRIMARY KEY (id);


--
-- Name: realty_states_code_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_states
    ADD CONSTRAINT realty_states_code_key UNIQUE (code);


--
-- Name: realty_states_name_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_states
    ADD CONSTRAINT realty_states_name_key UNIQUE (name);


--
-- Name: realty_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_states
    ADD CONSTRAINT realty_states_pkey PRIMARY KEY (id);


--
-- Name: realty_types_code_uniq; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_types
    ADD CONSTRAINT realty_types_code_uniq UNIQUE (code);


--
-- Name: realty_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY realty_types
    ADD CONSTRAINT realty_types_pkey PRIMARY KEY (id);


--
-- Name: sms_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY sms_messages
    ADD CONSTRAINT sms_messages_pkey PRIMARY KEY (id);


--
-- Name: subscription_realty_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY subscription_realty
    ADD CONSTRAINT subscription_realty_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: _query_cache_add_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX _query_cache_add_date_idx ON _query_cache USING btree (add_date);


--
-- Name: _query_cache_query_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX _query_cache_query_idx ON _query_cache USING btree (query);


--
-- Name: address_objects_aoid_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX address_objects_aoid_uniq_idx ON address_objects USING btree (aoid);


--
-- Name: address_objects_curr_status_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_curr_status_idx ON address_objects USING btree (curr_status);


--
-- Name: address_objects_end_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_end_date_idx ON address_objects USING btree (end_date NULLS FIRST);


--
-- Name: address_objects_expanded_name_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_expanded_name_idx ON address_objects USING btree (expanded_name);


--
-- Name: address_objects_expanded_name_lc_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_expanded_name_lc_idx ON address_objects USING btree (lower((expanded_name)::text) varchar_pattern_ops);


--
-- Name: address_objects_fts_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_fts_idx ON address_objects USING gin (fts);


--
-- Name: address_objects_guid_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_guid_idx ON address_objects USING btree (guid);


--
-- Name: address_objects_level_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_level_idx ON address_objects USING btree (level);


--
-- Name: address_objects_name_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_name_idx ON address_objects USING btree (name);


--
-- Name: address_objects_name_lc_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_name_lc_idx ON address_objects USING btree (lower((name)::text) varchar_pattern_ops);


--
-- Name: address_objects_parent_guid_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_parent_guid_idx ON address_objects USING btree (parent_guid);


--
-- Name: address_objects_plain_code_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX address_objects_plain_code_idx ON address_objects USING btree (plain_code);


--
-- Name: clients_additional_phones_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX clients_additional_phones_idx ON clients USING gin (additional_phones);


--
-- Name: clients_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX clients_delete_date_idx ON clients USING btree (delete_date NULLS FIRST);


--
-- Name: clients_email_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX clients_email_uniq_idx ON clients USING btree (email) WHERE (delete_date IS NULL);


--
-- Name: clients_login_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX clients_login_uniq_idx ON clients USING btree (login) WHERE (delete_date IS NULL);


--
-- Name: clients_phone_num_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX clients_phone_num_uniq_idx ON clients USING btree (phone_num) WHERE (delete_date IS NULL);


--
-- Name: dict_ap_schemes_name_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX dict_ap_schemes_name_uniq_idx ON dict_ap_schemes USING btree (name) WHERE (delete_date IS NULL);


--
-- Name: dict_balconies_name_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX dict_balconies_name_uniq_idx ON dict_balconies USING btree (name) WHERE (delete_date IS NULL);


--
-- Name: dict_bathrooms_name_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX dict_bathrooms_name_uniq_idx ON dict_bathrooms USING btree (name) WHERE (delete_date IS NULL);


--
-- Name: dict_conditions_name_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX dict_conditions_name_uniq_idx ON dict_conditions USING btree (name) WHERE (delete_date IS NULL);


--
-- Name: dict_house_types_name_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX dict_house_types_name_uniq_idx ON dict_house_types USING btree (name) WHERE (delete_date IS NULL);


--
-- Name: dict_room_schemes_name_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX dict_room_schemes_name_uniq_idx ON dict_room_schemes USING btree (name) WHERE (delete_date IS NULL);


--
-- Name: landmarks_change_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX landmarks_change_date_idx ON landmarks USING btree (change_date);


--
-- Name: landmarks_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX landmarks_delete_date_idx ON landmarks USING btree (delete_date NULLS FIRST);


--
-- Name: landmarks_geodata_geography_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX landmarks_geodata_geography_idx ON landmarks USING gist (((geodata)::postgis.geography));


--
-- Name: landmarks_geodata_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX landmarks_geodata_idx ON landmarks USING gist (geodata);


--
-- Name: landmarks_grp_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX landmarks_grp_idx ON landmarks USING btree (grp);


--
-- Name: landmarks_type_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX landmarks_type_idx ON landmarks USING btree (type);


--
-- Name: landmarks_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX landmarks_uniq_idx ON landmarks USING btree (name, type) WHERE (delete_date IS NULL);


--
-- Name: media_code_type_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX media_code_type_uniq_idx ON media USING btree (code, type) WHERE (delete_date IS NULL);


--
-- Name: media_import_history_media_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX media_import_history_media_idx ON media_import_history USING btree (media_id);


--
-- Name: media_import_history_media_text_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX media_import_history_media_text_idx ON media_import_history USING hash (media_text);


--
-- Name: media_import_history_realty_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX media_import_history_realty_idx ON media_import_history USING btree (realty_id);


--
-- Name: mediator_companies_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX mediator_companies_delete_date_idx ON mediator_companies USING btree (delete_date NULLS FIRST);


--
-- Name: mediator_companies_name_lc_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX mediator_companies_name_lc_uniq_idx ON mediator_companies USING btree (lower((name)::text) varchar_pattern_ops) WHERE (delete_date IS NULL);


--
-- Name: mediators_company_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX mediators_company_idx ON mediators USING btree (company_id);


--
-- Name: mediators_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX mediators_delete_date_idx ON mediators USING btree (delete_date NULLS FIRST);


--
-- Name: mediators_phone_num_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX mediators_phone_num_uniq_idx ON mediators USING btree (phone_num varchar_pattern_ops) WHERE (delete_date IS NULL);


--
-- Name: photos_add_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX photos_add_date_idx ON photos USING btree (add_date);


--
-- Name: photos_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX photos_delete_date_idx ON photos USING btree (delete_date NULLS FIRST);


--
-- Name: photos_main_photo_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX photos_main_photo_uniq_idx ON photos USING btree (realty_id, is_main) WHERE (is_main = true);


--
-- Name: photos_realty_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX photos_realty_idx ON photos USING btree (realty_id);


--
-- Name: query_keywords_fts_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX query_keywords_fts_idx ON query_keywords USING gin (fts);


--
-- Name: query_keywords_fval_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX query_keywords_fval_idx ON query_keywords USING btree (fval varchar_pattern_ops);


--
-- Name: realty_add_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_add_date_idx ON realty USING btree (add_date);


--
-- Name: realty_address_object_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_address_object_idx ON realty USING btree (address_object_id);


--
-- Name: realty_agency_price_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_agency_price_idx ON realty USING btree (agency_price);


--
-- Name: realty_agent_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_agent_idx ON realty USING btree (agent_id);


--
-- Name: realty_ap_condition_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_ap_condition_idx ON realty USING btree (condition_id);


--
-- Name: realty_ap_num_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_ap_num_idx ON realty USING btree (ap_num);


--
-- Name: realty_ap_scheme_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_ap_scheme_idx ON realty USING btree (ap_scheme_id);


--
-- Name: realty_balcony_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_balcony_idx ON realty USING btree (balcony_id);


--
-- Name: realty_bathroom_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_bathroom_idx ON realty USING btree (bathroom_id);


--
-- Name: realty_buyer_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_buyer_idx ON realty USING btree (buyer_id);


--
-- Name: realty_change_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_change_date_idx ON realty USING btree (change_date);


--
-- Name: realty_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_delete_date_idx ON realty USING btree (delete_date NULLS FIRST);


--
-- Name: realty_export_media_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_export_media_idx ON realty USING gin (export_media);


--
-- Name: realty_floor_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_floor_idx ON realty USING btree (floor);


--
-- Name: realty_floors_count_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_floors_count_idx ON realty USING btree (floors_count);


--
-- Name: realty_floors_count_sub_floor_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_floors_count_sub_floor_idx ON realty USING btree (((floors_count - floor)));


--
-- Name: realty_fts_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_fts_idx ON realty USING gin (fts);


--
-- Name: realty_house_type_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_house_type_idx ON realty USING btree (house_type_id);


--
-- Name: realty_landmarks_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_landmarks_idx ON realty USING gin (landmarks);


--
-- Name: realty_latlng_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_latlng_idx ON realty USING btree (latitude, longitude);


--
-- Name: realty_offer_type_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_offer_type_idx ON realty USING btree (offer_type_code);


--
-- Name: realty_owner_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_owner_idx ON realty USING btree (owner_id);


--
-- Name: realty_owner_phones_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_owner_phones_idx ON realty USING gin (owner_phones);


--
-- Name: realty_price_change_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_price_change_date_idx ON realty USING btree (price_change_date);


--
-- Name: realty_price_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_price_idx ON realty USING btree (price);


--
-- Name: realty_room_scheme_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_room_scheme_idx ON realty USING btree (room_scheme_id);


--
-- Name: realty_rooms_count_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_rooms_count_idx ON realty USING btree (rooms_count);


--
-- Name: realty_source_media_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_source_media_idx ON realty USING btree (source_media_id);


--
-- Name: realty_source_media_text_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_source_media_text_idx ON realty USING hash (source_media_text);


--
-- Name: realty_square_land_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_square_land_idx ON realty USING btree (square_land);


--
-- Name: realty_square_land_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_square_land_type ON realty USING btree (square_land_type);


--
-- Name: realty_square_total_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_square_total_idx ON realty USING btree (square_total);


--
-- Name: realty_state_change_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_state_change_date_idx ON realty USING btree (state_change_date);


--
-- Name: realty_state_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_state_idx ON realty USING btree (state_code);


--
-- Name: realty_sublandmark_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_sublandmark_idx ON realty USING btree (sublandmark_id);


--
-- Name: realty_tags_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_tags_idx ON realty USING gin (tags);


--
-- Name: realty_type_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX realty_type_idx ON realty USING btree (type_code);


--
-- Name: sms_messages_add_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX sms_messages_add_date_idx ON sms_messages USING btree (add_date);


--
-- Name: sms_messages_phone_num_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX sms_messages_phone_num_idx ON sms_messages USING btree (phone_num);


--
-- Name: sms_messages_status_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX sms_messages_status_idx ON sms_messages USING btree (status);


--
-- Name: subscription_realty_realty_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX subscription_realty_realty_idx ON subscription_realty USING btree (realty_id);


--
-- Name: subscription_realty_subscription_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX subscription_realty_subscription_idx ON subscription_realty USING btree (subscription_id);


--
-- Name: subscription_realty_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX subscription_realty_uniq_idx ON subscription_realty USING btree (subscription_id, realty_id) WHERE (delete_date IS NULL);


--
-- Name: subscriptions_client_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX subscriptions_client_idx ON subscriptions USING btree (client_id);


--
-- Name: subscriptions_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX subscriptions_delete_date_idx ON subscriptions USING btree (delete_date NULLS FIRST);


--
-- Name: subscriptions_end_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX subscriptions_end_date_idx ON subscriptions USING btree (end_date);


--
-- Name: subscriptions_last_check_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX subscriptions_last_check_date_idx ON subscriptions USING btree (last_check_date);


--
-- Name: subscriptions_user_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX subscriptions_user_idx ON subscriptions USING btree (user_id);


--
-- Name: tags_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tags_delete_date_idx ON tags USING btree (delete_date NULLS FIRST);


--
-- Name: tags_name_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX tags_name_uniq_idx ON tags USING btree (name) WHERE (delete_date IS NULL);


--
-- Name: tasks_add_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_add_date_idx ON tasks USING btree (add_date);


--
-- Name: tasks_assigned_user_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_assigned_user_idx ON tasks USING btree (assigned_user_id);


--
-- Name: tasks_category_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_category_idx ON tasks USING btree (category);


--
-- Name: tasks_creator_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_creator_idx ON tasks USING btree (creator_id);


--
-- Name: tasks_deadline_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_deadline_date_idx ON tasks USING btree (deadline_date);


--
-- Name: tasks_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_delete_date_idx ON tasks USING btree (delete_date);


--
-- Name: tasks_parent_task_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_parent_task_idx ON tasks USING btree (parent_task_id);


--
-- Name: tasks_realty_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_realty_idx ON tasks USING btree (realty_id);


--
-- Name: tasks_remind_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_remind_date_idx ON tasks USING btree (remind_date);


--
-- Name: tasks_status_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_status_idx ON tasks USING btree (status);


--
-- Name: tasks_type_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX tasks_type_idx ON tasks USING btree (type);


--
-- Name: users_delete_date_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX users_delete_date_idx ON users USING btree (delete_date NULLS FIRST);


--
-- Name: users_login_uniq_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX users_login_uniq_idx ON users USING btree (login) WHERE (delete_date IS NULL);


--
-- Name: users_phone_num_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX users_phone_num_idx ON users USING btree (phone_num);


--
-- Name: clients_additional_phones_chk_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER clients_additional_phones_chk_tr BEFORE INSERT OR UPDATE OF additional_phones ON clients FOR EACH ROW EXECUTE PROCEDURE clients_additional_phones_chk();


--
-- Name: realty_before_insert_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER realty_before_insert_tr BEFORE INSERT ON realty FOR EACH ROW EXECUTE PROCEDURE realty_before_insert();


--
-- Name: realty_before_update_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER realty_before_update_tr BEFORE UPDATE OF state_code, owner_price, agency_price ON realty FOR EACH ROW EXECUTE PROCEDURE realty_before_update();


--
-- Name: realty_owner_phones_chk_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER realty_owner_phones_chk_tr BEFORE INSERT OR UPDATE OF owner_phones ON realty FOR EACH ROW EXECUTE PROCEDURE realty_owner_phones_chk();


--
-- Name: realty_update_fts_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER realty_update_fts_tr AFTER INSERT OR UPDATE OF type_code, offer_type_code, address_object_id, house_type_id, ap_scheme_id, room_scheme_id, condition_id, balcony_id, bathroom_id, description, sublandmark_id, tags ON realty FOR EACH ROW EXECUTE PROCEDURE realty_update_fts();


--
-- Name: realty_update_geo_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER realty_update_geo_tr AFTER INSERT OR UPDATE OF latitude, longitude ON realty FOR EACH ROW EXECUTE PROCEDURE realty_update_geo();


--
-- Name: sms_messages_update_status_change_date_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sms_messages_update_status_change_date_tr BEFORE UPDATE OF status ON sms_messages FOR EACH ROW WHEN (((new.status)::text <> (old.status)::text)) EXECUTE PROCEDURE sms_messages_update_status_change_date();


--
-- Name: media_import_history_media_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY media_import_history
    ADD CONSTRAINT media_import_history_media_fk FOREIGN KEY (media_id) REFERENCES media(id);


--
-- Name: media_import_history_realty_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY media_import_history
    ADD CONSTRAINT media_import_history_realty_fk FOREIGN KEY (realty_id) REFERENCES realty(id);


--
-- Name: mediators_company_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY mediators
    ADD CONSTRAINT mediators_company_fk FOREIGN KEY (company_id) REFERENCES mediator_companies(id);


--
-- Name: photos_realty_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY photos
    ADD CONSTRAINT photos_realty_fk FOREIGN KEY (realty_id) REFERENCES realty(id);


--
-- Name: realty_address_object_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_address_object_fk FOREIGN KEY (address_object_id) REFERENCES address_objects(id);


--
-- Name: realty_agent_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_agent_fk FOREIGN KEY (agent_id) REFERENCES users(id);


--
-- Name: realty_ap_scheme_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_ap_scheme_fk FOREIGN KEY (ap_scheme_id) REFERENCES dict_ap_schemes(id);


--
-- Name: realty_balcony_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_balcony_fk FOREIGN KEY (balcony_id) REFERENCES dict_balconies(id);


--
-- Name: realty_bathroom_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_bathroom_fk FOREIGN KEY (bathroom_id) REFERENCES dict_bathrooms(id);


--
-- Name: realty_buyer_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_buyer_fk FOREIGN KEY (buyer_id) REFERENCES clients(id);


--
-- Name: realty_condition_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_condition_fk FOREIGN KEY (condition_id) REFERENCES dict_conditions(id);


--
-- Name: realty_creator_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_creator_fk FOREIGN KEY (creator_id) REFERENCES users(id);


--
-- Name: realty_house_type_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_house_type_fk FOREIGN KEY (house_type_id) REFERENCES dict_house_types(id);


--
-- Name: realty_offer_type_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_offer_type_fk FOREIGN KEY (offer_type_code) REFERENCES realty_offer_types(code);


--
-- Name: realty_owner_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_owner_fk FOREIGN KEY (owner_id) REFERENCES clients(id);


--
-- Name: realty_room_scheme_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_room_scheme_fk FOREIGN KEY (room_scheme_id) REFERENCES dict_room_schemes(id);


--
-- Name: realty_source_media_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_source_media_fk FOREIGN KEY (source_media_id) REFERENCES media(id);


--
-- Name: realty_state_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_state_fk FOREIGN KEY (state_code) REFERENCES realty_states(code);


--
-- Name: realty_sublandmark_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_sublandmark_fk FOREIGN KEY (sublandmark_id) REFERENCES landmarks(id);


--
-- Name: realty_type_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty
    ADD CONSTRAINT realty_type_fk FOREIGN KEY (type_code) REFERENCES realty_types(code);


--
-- Name: realty_types_category_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY realty_types
    ADD CONSTRAINT realty_types_category_fk FOREIGN KEY (category_code) REFERENCES realty_categories(code);


--
-- Name: subscription_realty_realty_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscription_realty
    ADD CONSTRAINT subscription_realty_realty_fk FOREIGN KEY (realty_id) REFERENCES realty(id);


--
-- Name: subscription_realty_subscription_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscription_realty
    ADD CONSTRAINT subscription_realty_subscription_fk FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);


--
-- Name: subscriptions_client_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_client_fk FOREIGN KEY (client_id) REFERENCES clients(id);


--
-- Name: subscriptions_offer_type_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_offer_type_fk FOREIGN KEY (offer_type_code) REFERENCES realty_offer_types(code);


--
-- Name: subscriptions_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_user_fk FOREIGN KEY (user_id) REFERENCES users(id);


--
-- Name: tasks_assigned_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_assigned_user_fk FOREIGN KEY (assigned_user_id) REFERENCES users(id);


--
-- Name: tasks_creator_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_creator_fk FOREIGN KEY (creator_id) REFERENCES users(id);


--
-- Name: tasks_parent_task_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_parent_task_fk FOREIGN KEY (parent_task_id) REFERENCES tasks(id);


--
-- Name: tasks_realty_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_realty_fk FOREIGN KEY (realty_id) REFERENCES realty(id);


--
-- Name: public; Type: ACL; Schema: -; Owner: -
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

