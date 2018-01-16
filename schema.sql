--
-- PostgreSQL database dump
--


--
-- Name: data_source_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE data_source_type AS ENUM (
    'sim_gta',
    'safetypilot'
);


--
-- Name: detection_class; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE detection_class AS ENUM (
    'Unknown',
    'Compacts',
    'Sedans',
    'SUVs',
    'Coupes',
    'Muscle',
    'SportsClassics',
    'Sports',
    'Super',
    'Motorcycles',
    'OffRoad',
    'Industrial',
    'Utility',
    'Vans',
    'Cycles',
    'Boats',
    'Helicopters',
    'Planes',
    'Service',
    'Emergency',
    'Military',
    'Commercial',
    'Trains'
);


--
-- Name: detection_method; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE detection_method AS ENUM (
    'gtagame',
    'stencil'
);


--
-- Name: detection_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE detection_type AS ENUM (
    'background',
    'person',
    'car',
    'bicycle'
);


--
-- Name: vector; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE vector AS (
	x real,
	y real,
	z real
);


--
-- Name: weather; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE weather AS ENUM (
    'Unknown',
    'ExtraSunny',
    'Clear',
    'Clouds',
    'Smog',
    'Foggy',
    'Overcast',
    'Raining',
    'ThunderStorm',
    'Clearing',
    'Neutral',
    'Snowing',
    'Blizzard',
    'Snowlight',
    'Christmas'
);


--
-- Name: ngv_box3dmultipoint(box3d); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION ngv_box3dmultipoint(box3d) RETURNS geometry
    LANGUAGE sql
    AS $_$ select ST_Multi(ST_Collect(ST_MakePoint(ST_XMin($1), ST_YMin($1), ST_ZMin($1)), ST_MakePoint(ST_XMax($1), ST_YMax($1), ST_ZMax($1)))) $_$;


--
-- Name: ngv_box3dpolygon(box3d); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION ngv_box3dpolygon(box3d) RETURNS geometry
    LANGUAGE sql
    AS $_$
SELECT ST_Collect(ARRAY[
     ST_MakePoint(ST_XMin($1), ST_YMin($1), ST_ZMin($1)),
     ST_MakePoint(ST_XMax($1), ST_YMin($1), ST_ZMin($1)),
     ST_MakePoint(ST_XMax($1), ST_YMax($1), ST_ZMin($1)),
     ST_MakePoint(ST_XMin($1), ST_YMax($1), ST_ZMin($1)),
     ST_MakePoint(ST_XMin($1), ST_YMin($1), ST_ZMax($1)),
     ST_MakePoint(ST_XMax($1), ST_YMin($1), ST_ZMax($1)),
     ST_MakePoint(ST_XMax($1), ST_YMax($1), ST_ZMax($1)),
     ST_MakePoint(ST_XMin($1), ST_YMax($1), ST_ZMax($1))])
$_$;


--
-- Name: ngv_contract(box, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION ngv_contract(bbox box, width integer, height integer) RETURNS box
    LANGUAGE sql
    AS $$
    select box(point((bbox[0])[0] / width, (bbox[0])[1] / height), point((bbox[1])[0] / width, (bbox[1])[1] / height));
$$;


--
-- Name: ngv_expand(box, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION ngv_expand(bbox box, width integer, height integer) RETURNS box
    LANGUAGE sql
    AS $$
    select box(point((bbox[0])[0] * width, (bbox[0])[1] * height), point((bbox[1])[0] * width, (bbox[1])[1] * height));
$$;


--
-- Name: ngv_get_bytes(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION ngv_get_bytes(id integer) RETURNS bytea
    LANGUAGE sql
    AS $$
SELECT ngv_get_bytes(localpath, imagepath) FROM snapshots JOIN runs USING(run_id) where snapshot_id=id
$$;


--
-- Name: ngv_get_raster(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION ngv_get_raster(archive text, image text) RETURNS raster
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN ST_FromGDALRaster(ngv_get_bytes(archive, image));
END;
$$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: detections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE detections (
    detection_id integer NOT NULL,
    snapshot_id integer,
    type detection_type,
    pos geometry(PointZ),
    bbox box,
    class detection_class DEFAULT 'Unknown'::detection_class,
    handle integer DEFAULT '-1'::integer,
    best_bbox box,
    best_bbox_old box,
    method detection_method DEFAULT 'gtagame'::detection_method,
    bbox3d box3d,
    rot geometry,
    coverage real DEFAULT 0.0
);


--
-- Name: runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE runs (
    run_id integer NOT NULL,
    runguid uuid,
    archivepath text,
    localpath text,
    session_id integer DEFAULT 1,
    instance_id integer DEFAULT 0
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE sessions (
    session_id integer NOT NULL,
    name text,
    start timestamp with time zone,
    "end" timestamp with time zone
);


--
-- Name: snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE snapshots (
    snapshot_id integer NOT NULL,
    run_id integer,
    version integer,
    imagepath text,
    "timestamp" timestamp with time zone,
    timeofday time without time zone,
    currentweather weather,
    camera_pos geometry(PointZ),
    datasource data_source_type,
    camera_direction geometry,
    camera_fov real,
    view_matrix double precision[],
    proj_matrix double precision[],
    processed boolean DEFAULT false NOT NULL,
    width integer,
    height integer
);


--
-- Name: data_by_detection; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW data_by_detection AS
 SELECT runs.session_id,
    snapshots.run_id,
    detections.snapshot_id,
    detections.detection_id,
    detections.type,
    detections.pos,
    detections.bbox,
    detections.class,
    detections.handle,
    detections.best_bbox,
    detections.best_bbox_old,
    snapshots.version,
    snapshots.imagepath,
    snapshots."timestamp",
    snapshots.timeofday,
    snapshots.currentweather,
    snapshots.camera_pos,
    snapshots.datasource,
    snapshots.camera_direction,
    snapshots.camera_fov,
    runs.runguid,
    runs.archivepath,
    runs.localpath,
    runs.instance_id,
    sessions.name,
    sessions.start,
    sessions."end",
    snapshots.width,
    snapshots.height
   FROM (((detections
     JOIN snapshots USING (snapshot_id))
     JOIN runs USING (run_id))
     JOIN sessions USING (session_id));


--
-- Name: data_by_snapshot; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW data_by_snapshot AS
 SELECT runs.session_id,
    snapshots.run_id,
    snapshots.snapshot_id,
    snapshots.version,
    snapshots.imagepath,
    snapshots."timestamp",
    snapshots.timeofday,
    snapshots.currentweather,
    snapshots.camera_pos,
    snapshots.datasource,
    runs.runguid,
    runs.archivepath,
    runs.localpath,
    runs.instance_id,
    sessions.name,
    sessions.start,
    sessions."end",
    snapshots.processed,
    snapshots.width,
    snapshots.height
   FROM ((snapshots
     JOIN runs USING (run_id))
     JOIN sessions USING (session_id));


--
-- Name: datasets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE datasets (
    dataset_id integer NOT NULL,
    dataset_name text,
    view_name text
);


--
-- Name: datasets_dataset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE datasets_dataset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: datasets_dataset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE datasets_dataset_id_seq OWNED BY datasets.dataset_id;


--
-- Name: detections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE detections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: detections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE detections_id_seq OWNED BY detections.detection_id;

--
-- Name: instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE instances (
    instance_id integer NOT NULL,
    hostname text,
    instanceid text,
    instancetype text,
    publichostname text,
    amiid text
);


--
-- Name: isntances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE isntances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: isntances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE isntances_id_seq OWNED BY instances.instance_id;

--
-- Name: runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE runs_id_seq OWNED BY runs.run_id;


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE sessions_id_seq OWNED BY sessions.session_id;


--
-- Name: snapshot_weathers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE snapshot_weathers (
    weather_id integer NOT NULL,
    snapshot_id integer,
    weather_type weather,
    snapshot_page integer
);


--
-- Name: snapshot_weathers_weather_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE snapshot_weathers_weather_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: snapshot_weathers_weather_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE snapshot_weathers_weather_id_seq OWNED BY snapshot_weathers.weather_id;


--
-- Name: snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE snapshots_id_seq OWNED BY snapshots.snapshot_id;


--
-- Name: system_graphics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE system_graphics (
    system_graphic_id integer NOT NULL,
    deviceid text,
    adaptercompatibility text,
    adapterdactype text,
    adapterram integer,
    availability integer,
    caption text,
    description text,
    driverdate timestamp with time zone,
    driverversion text,
    pnpdeviceid text,
    name text,
    videoarch integer,
    memtype integer,
    videoprocessor text,
    bpp integer,
    hrez integer,
    vrez integer,
    num_colors integer,
    cols integer,
    rows integer,
    refresh integer,
    scanmode integer,
    videomodedesc text
);


--
-- Name: system_graphics_system_graphic_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE system_graphics_system_graphic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_graphics_system_graphic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE system_graphics_system_graphic_id_seq OWNED BY system_graphics.system_graphic_id;


--
-- Name: systems; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE systems (
    system_uuid uuid NOT NULL,
    vendor text,
    dnshostname text,
    username text,
    systemtype text,
    totalmem integer
);


--
-- Name: uploads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE uploads (
    id integer NOT NULL,
    bucket text,
    key text,
    uploadid text
);


--
-- Name: uploads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE uploads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: uploads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE uploads_id_seq OWNED BY uploads.id;


--
-- Name: datasets dataset_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY datasets ALTER COLUMN dataset_id SET DEFAULT nextval('datasets_dataset_id_seq'::regclass);


--
-- Name: detections detection_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY detections ALTER COLUMN detection_id SET DEFAULT nextval('detections_id_seq'::regclass);


--
-- Name: instances instance_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY instances ALTER COLUMN instance_id SET DEFAULT nextval('isntances_id_seq'::regclass);


--
-- Name: runs run_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs ALTER COLUMN run_id SET DEFAULT nextval('runs_id_seq'::regclass);


--
-- Name: sessions session_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY sessions ALTER COLUMN session_id SET DEFAULT nextval('sessions_id_seq'::regclass);


--
-- Name: snapshot_weathers weather_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY snapshot_weathers ALTER COLUMN weather_id SET DEFAULT nextval('snapshot_weathers_weather_id_seq'::regclass);


--
-- Name: snapshots snapshot_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY snapshots ALTER COLUMN snapshot_id SET DEFAULT nextval('snapshots_id_seq'::regclass);


--
-- Name: system_graphics system_graphic_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY system_graphics ALTER COLUMN system_graphic_id SET DEFAULT nextval('system_graphics_system_graphic_id_seq'::regclass);


--
-- Name: uploads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY uploads ALTER COLUMN id SET DEFAULT nextval('uploads_id_seq'::regclass);


--
-- Name: datasets datasets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY datasets
    ADD CONSTRAINT datasets_pkey PRIMARY KEY (dataset_id);


--
-- Name: detections detections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY detections
    ADD CONSTRAINT detections_pkey PRIMARY KEY (detection_id);


--
-- Name: instances instance_info_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY instances
    ADD CONSTRAINT instance_info_uniq UNIQUE (hostname, instanceid, instancetype, publichostname, amiid);


--
-- Name: instances instanceid_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY instances
    ADD CONSTRAINT instanceid_uniq UNIQUE (instanceid);


--
-- Name: instances isntances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY instances
    ADD CONSTRAINT isntances_pkey PRIMARY KEY (instance_id);


--
-- Name: runs runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs
    ADD CONSTRAINT runs_pkey PRIMARY KEY (run_id);


--
-- Name: sessions sessions_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY sessions
    ADD CONSTRAINT sessions_name_key UNIQUE (name);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (session_id);


--
-- Name: snapshot_weathers snapshot_weathers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY snapshot_weathers
    ADD CONSTRAINT snapshot_weathers_pkey PRIMARY KEY (weather_id);


--
-- Name: snapshots snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY snapshots
    ADD CONSTRAINT snapshots_pkey PRIMARY KEY (snapshot_id);


--
-- Name: system_graphics system_graphics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY system_graphics
    ADD CONSTRAINT system_graphics_pkey PRIMARY KEY (system_graphic_id);


--
-- Name: systems systems_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY systems
    ADD CONSTRAINT systems_pkey PRIMARY KEY (system_uuid);


--
-- Name: uploads uploads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY uploads
    ADD CONSTRAINT uploads_pkey PRIMARY KEY (id);


--
-- Name: detections_bbox_null_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX detections_bbox_null_idx ON detections USING btree (((bbox IS NOT NULL)));


--
-- Name: detections_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX detections_gix ON detections USING gist (pos);


--
-- Name: fki_detections_snapshot_fkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fki_detections_snapshot_fkey ON detections USING btree (snapshot_id);


--
-- Name: fki_snapshots_run_fkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fki_snapshots_run_fkey ON snapshots USING btree (run_id);


--
-- Name: idx_detections_pkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_detections_pkey ON detections USING btree (detection_id);


--
-- Name: idx_snapshots_pkey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_snapshots_pkey ON snapshots USING btree (snapshot_id);


--
-- Name: processed_counts_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX processed_counts_id_idx ON processed_counts USING btree (snapshot_id);


--
-- Name: processed_counts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX processed_counts_idx ON processed_counts USING btree (count);


--
-- Name: repro_1m_nosmall_snapshots; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX repro_1m_nosmall_snapshots ON repro_1m_nosmall USING btree (snapshot_id);


--
-- Name: runs_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX runs_id_index ON runs USING btree (run_id);


--
-- Name: snapshots_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX snapshots_gix ON snapshots USING gist (camera_pos);


--
-- Name: detections detections_snapshot_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY detections
    ADD CONSTRAINT detections_snapshot_fkey FOREIGN KEY (snapshot_id) REFERENCES snapshots(snapshot_id) ON DELETE CASCADE;


--
-- Name: runs runs_instance_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs
    ADD CONSTRAINT runs_instance_fkey FOREIGN KEY (instance_id) REFERENCES instances(instance_id);


--
-- Name: runs runs_session_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs
    ADD CONSTRAINT runs_session_fkey FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE;


--
-- Name: snapshot_weathers snapshot_weathers_snapshot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY snapshot_weathers
    ADD CONSTRAINT snapshot_weathers_snapshot_id_fkey FOREIGN KEY (snapshot_id) REFERENCES snapshots(snapshot_id) ON DELETE CASCADE;


--
-- Name: snapshots snapshots_run_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY snapshots
    ADD CONSTRAINT snapshots_run_fkey FOREIGN KEY (run_id) REFERENCES runs(run_id) ON DELETE CASCADE;


