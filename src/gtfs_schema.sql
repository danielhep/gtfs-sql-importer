drop table IF EXISTS gtfs_agency cascade;
drop table IF EXISTS gtfs_stops cascade;
drop table IF EXISTS gtfs_routes cascade;
drop table IF EXISTS gtfs_calendar cascade;
drop table IF EXISTS gtfs_calendar_dates cascade;
drop table IF EXISTS gtfs_fare_attributes cascade;
drop table IF EXISTS gtfs_fare_rules cascade;
drop table IF EXISTS gtfs_shapes cascade;
drop table IF EXISTS gtfs_trips cascade;
drop table IF EXISTS gtfs_stop_times cascade;
drop table IF EXISTS gtfs_frequencies cascade;

DROP TABLE IF EXISTS gtfs_shape_geoms CASCADE;

drop table IF EXISTS gtfs_transfers cascade;
drop table IF EXISTS gtfs_feed_info cascade;

drop table IF EXISTS gtfs_route_types cascade;
drop table IF EXISTS gtfs_directions cascade;
drop table IF EXISTS gtfs_pickup_dropoff_types cascade;
drop table IF EXISTS gtfs_payment_methods cascade;

drop table IF EXISTS gtfs_location_types cascade;
drop table IF EXISTS gtfs_wheelchair_boardings cascade;
drop table IF EXISTS gtfs_wheelchair_accessible cascade;
drop table IF EXISTS gtfs_transfer_types cascade;

drop table IF EXISTS service_combo_ids cascade;
drop table IF EXISTS service_combinations cascade;

begin;

create table gtfs_agency (
  agency_id    text, --PRIMARY KEY,
  agency_name  text,
  agency_url   text,
  agency_timezone    text,
  agency_lang  text,
  agency_phone text,
  agency_fare_url text
);

create table gtfs_stops (
  feed_index int,
  stop_id    text,--PRIMARY KEY,
  stop_name  text, --NOT NULL,
  stop_desc  text,
  stop_lat   double precision,
  stop_lon   double precision,
  zone_id    text,
  stop_url   text,
  stop_code  text,

  -- new
  stop_street text,
  stop_city   text,
  stop_region text,
  stop_postcode text,
  stop_country text,

  direction text,
  position text
  -- PRIMARY KEY (feed_index, stop_id)
);
SELECT AddGeometryColumn('gtfs_stops', 'the_geom', 4326, 'POINT', 2);

-- tigger the_geom update with lat or lon inserted
CREATE OR REPLACE FUNCTION gtfs_stop_geom_update() RETURNS TRIGGER AS $stop_geom$
  BEGIN
    NEW.the_geom = ST_SetSRID(ST_MakePoint(NEW.stop_lon, NEW.stop_lat), 4326);
    RETURN NEW;
  END;
$stop_geom$ LANGUAGE plpgsql;

CREATE TRIGGER gtfs_stop_geom_trigger BEFORE INSERT OR UPDATE ON gtfs_stops
    FOR EACH ROW EXECUTE PROCEDURE gtfs_stop_geom_update();

create table gtfs_routes (
  feed_index int,
  route_id    text,--PRIMARY KEY,
  agency_id   text, --REFERENCES gtfs_agency(agency_id),
  route_short_name  text DEFAULT '',
  route_long_name   text DEFAULT '',
  route_desc  text,
  route_type  int, --REFERENCES gtfs_route_types(route_type),
  route_url   text,
  route_color text,
  route_text_color text
  -- PRIMARY KEY (feed_index, route_id)
);

create table gtfs_calendar (
  service_id   text,--PRIMARY KEY,
  monday int, --NOT NULL,
  tuesday int, --NOT NULL,
  wednesday    int, --NOT NULL,
  thursday     int, --NOT NULL,
  friday int, --NOT NULL,
  saturday     int, --NOT NULL,
  sunday int, --NOT NULL,
  start_date   date, --NOT NULL,
  end_date     date  --NOT NULL
);

create table gtfs_calendar_dates (
  service_id     text, --REFERENCES gtfs_calendar(service_id),
  date     date, --NOT NULL,
  exception_type int  --NOT NULL
);

create table gtfs_fare_attributes (
  feed_index  int,
  fare_id     text,--PRIMARY KEY,
  price       double precision, --NOT NULL,
  currency_type     text, --NOT NULL,
  payment_method    int, --REFERENCES gtfs_payment_methods,
  transfers         int,
  transfer_duration int,
  -- unofficial features
  agency_id text  --REFERENCES gtfs_agency(agency_id)
  -- PRIMARY KEY (feed_index, fare_id)
);

create table gtfs_fare_rules (
  feed_index int,
  fare_id     text, --REFERENCES gtfs_fare_attributes(fare_id),
  route_id    text, --REFERENCES gtfs_routes(route_id),
  origin_id   text,
  destination_id text,
  contains_id text,
  -- unofficial features
  service_id text -- REFERENCES gtfs_calendar(service_id) ?
  -- primary key(feed_index, fare_id)
);

create table gtfs_shapes (
  feed_index int,
  shape_id text, --NOT NULL,
  shape_pt_lat double precision, --NOT NULL,
  shape_pt_lon double precision, --NOT NULL,
  shape_pt_sequence int, --NOT NULL,
  shape_dist_traveled double precision
  -- primary key(feed_index, shape_id)
);

-- Create new table to store the shape geometries
CREATE TABLE gtfs_shape_geoms (
  shape_id text
);
-- Add the_geom column to the gtfs_shape_geoms table - a 2D linestring geometry
SELECT AddGeometryColumn('gtfs_shape_geoms', 'the_geom', 4326, 'LINESTRING', 2);

CREATE OR REPLACE FUNCTION gtfs_shape_update()
  RETURNS TRIGGER AS $shape_func$
  BEGIN
    IF TG_OP = 'INSERT' THEN
      INSERT INTO gtfs_shape_geoms
        SELECT
          shape_id,
          ST_SetSRID(ST_MakeLine(shape.the_geom), 4326) AS the_geom
      FROM (
        SELECT
          s.shape_id,
          ST_MakePoint(shape_pt_lon, shape_pt_lat) AS the_geom
        FROM gtfs_shapes s
          LEFT JOIN gtfs_shape_geoms sg ON (s.shape_id = sg.shape_id)
        WHERE sg.shape_id IS NULL
        ORDER BY shape_id, shape_pt_sequence
      ) AS shape
      GROUP BY shape.shape_id;

    ELSIF (TG_OP = 'UPDATE') THEN
      UPDATE gtfs_shape_geoms
        SET (shape_id, the_geom) = 
          (shape_id, ST_SetSRID(ST_MakeLine(shape.the_geom), 4326))
      FROM (
        SELECT
          s.shape_id,
          ST_MakePoint(shape_pt_lon, shape_pt_lat) AS the_geom
        FROM gtfs_shapes s
          INNER JOIN gtfs_shape_geoms sg ON (s.shape_id = sg.shape_id)
        ORDER BY shape_id, shape_pt_sequence
      ) AS shape
      GROUP BY shape.shape_id;
    END IF;
  END;
$shape_func$ LANGUAGE plpgsql;

CREATE TRIGGER gtfs_shape_geom_trigger AFTER INSERT OR UPDATE ON gtfs_shapes
  FOR EACH STATEMENT EXECUTE PROCEDURE gtfs_shape_update();

create table gtfs_trips (
  feed_index int,
  route_id text, --REFERENCES gtfs_routes(route_id),
  service_id text, --REFERENCES gtfs_calendar(service_id),
  trip_id text,--PRIMARY KEY,
  trip_headsign text,
  direction_id  int, --REFERENCES gtfs_directions(direction_id),
  block_id text,
  shape_id text,
  trip_short_name text,
  wheelchair_accessible int, --FOREIGN KEY REFERENCES gtfs_wheelchair_accessible(wheelchair_accessible)

  -- unofficial features
  trip_type text
  -- primary key (feed_index, trip_id)
);

create table gtfs_stop_times (
  feed_index int,
  trip_id text, --REFERENCES gtfs_trips(trip_id),
  arrival_time text, -- CHECK (arrival_time LIKE '__:__:__'),
  departure_time text, -- CHECK (departure_time LIKE '__:__:__'),
  stop_id text, --REFERENCES gtfs_stops(stop_id),
  stop_sequence int, --NOT NULL,
  stop_headsign text,
  pickup_type   int, --REFERENCES gtfs_pickup_dropoff_types(type_id),
  drop_off_type int, --REFERENCES gtfs_pickup_dropoff_types(type_id),
  shape_dist_traveled double precision,
  -- unofficial features

  timepoint int,
  -- the following are not in the spec

  arrival_time_seconds int,
  departure_time_seconds int
  -- PRIMARY KEY (feed_index, trip_id, stop_id)
);

--create index arr_time_index on gtfs_stop_times(arrival_time_seconds);
--create index dep_time_index on gtfs_stop_times(departure_time_seconds);

create table gtfs_frequencies (
  feed_index int,
  trip_id     text, --REFERENCES gtfs_trips(trip_id),
  start_time  text, --NOT NULL,
  end_time    text, --NOT NULL,
  headway_secs int, --NOT NULL
  exact_times int,
  start_time_seconds int,
  end_time_seconds int
  -- primary key (feed_index, trip_id, start_time)
);

create table gtfs_transfers (
  feed_index int,
  from_stop_id text, --REFERENCES gtfs_stops(stop_id)
  to_stop_id text, --REFERENCES gtfs_stops(stop_id)
  transfer_type int, --REFERENCES gtfs_transfer_types(transfer_type)
  min_transfer_time int,
  -- Unofficial fields
  from_route_id text, --REFERENCES gtfs_routes(route_id)
  to_route_id text, --REFERENCES gtfs_routes(route_id)
  service_id text --REFERENCES gtfs_calendar(service_id) ?
);

-- tracks uploads, avoids key collisions
create table gtfs_feed_info (
  feed_index serial primary key,
  feed_publisher_name text,
  feed_publisher_url text,
  feed_timezone text,
  feed_lang text,
  feed_version text,
  feed_start_date date,
  feed_end_date date,
  feed_download_date date
);

-- The following two tables are not in the spec, but they make dealing with dates and services easier
create table service_combo_ids (
combination_id serial --primary key
);

create table service_combinations (
combination_id int, --references service_combo_ids(combination_id),
service_id text --references gtfs_calendar(service_id)
);

create table gtfs_transfer_types (
  transfer_type int PRIMARY KEY,
  description text
);

insert into gtfs_transfer_types (transfer_type, description)
       values (0,'Preferred transfer point');
insert into gtfs_transfer_types (transfer_type, description)
       values (1,'Designated transfer point');
insert into gtfs_transfer_types (transfer_type, description)
       values (2,'Transfer possible with min_transfer_time window');
insert into gtfs_transfer_types (transfer_type, description)
       values (3,'Transfers forbidden');


--related to gtfs_stops(location_type)
create table gtfs_location_types (
  location_type int PRIMARY KEY,
  description text
);

insert into gtfs_location_types(location_type, description)
       values (0,'stop');
insert into gtfs_location_types(location_type, description)
       values (1,'station');
insert into gtfs_location_types(location_type, description)
       values (2,'station entrance');

--related to gtfs_stops(wheelchair_boarding)
create table gtfs_wheelchair_boardings (
  wheelchair_boarding int PRIMARY KEY,
  description text
);

insert into gtfs_wheelchair_boardings(wheelchair_boarding, description)
       values (0, 'No accessibility information available for the stop');
insert into gtfs_wheelchair_boardings(wheelchair_boarding, description)
       values (1, 'At least some vehicles at this stop can be boarded by a rider in a wheelchair');
insert into gtfs_wheelchair_boardings(wheelchair_boarding, description)
       values (2, 'Wheelchair boarding is not possible at this stop');

--related to gtfs_stops(wheelchair_accessible)
create table gtfs_wheelchair_accessible (
  wheelchair_accessible int PRIMARY KEY,
  description text
);

insert into gtfs_wheelchair_accessible(wheelchair_accessible, description)
        values (0, 'No accessibility information available for this trip');
insert into gtfs_wheelchair_accessible(wheelchair_accessible, description)
        values (1, 'The vehicle being used on this particular trip can accommodate at least one rider in a wheelchair');
insert into gtfs_wheelchair_accessible(wheelchair_accessible, description)
        values (2, 'No riders in wheelchairs can be accommodated on this trip');

create table gtfs_route_types (
  route_type int PRIMARY KEY,
  description text
);

insert into gtfs_route_types (route_type, description) values (0, 'Street Level Rail');
insert into gtfs_route_types (route_type, description) values (1, 'Underground Rail');
insert into gtfs_route_types (route_type, description) values (2, 'Intercity Rail');
insert into gtfs_route_types (route_type, description) values (3, 'Bus');
insert into gtfs_route_types (route_type, description) values (4, 'Ferry');
insert into gtfs_route_types (route_type, description) values (5, 'Cable Car');
insert into gtfs_route_types (route_type, description) values (6, 'Suspended Car');
insert into gtfs_route_types (route_type, description) values (7, 'Steep Incline Mode');

create table gtfs_directions (
  direction_id int PRIMARY KEY,
  description text
);

insert into gtfs_directions (direction_id, description) values (0,'This way');
insert into gtfs_directions (direction_id, description) values (1,'That way');

create table gtfs_pickup_dropoff_types (
  type_id int PRIMARY KEY,
  description text
);

insert into gtfs_pickup_dropoff_types (type_id, description) values (0,'Regularly Scheduled');
insert into gtfs_pickup_dropoff_types (type_id, description) values (1,'Not available');
insert into gtfs_pickup_dropoff_types (type_id, description) values (2,'Phone arrangement only');
insert into gtfs_pickup_dropoff_types (type_id, description) values (3,'Driver arrangement only');

create table gtfs_payment_methods (
  payment_method int PRIMARY KEY,
  description text
);

insert into gtfs_payment_methods (payment_method, description) values (0,'On Board');
insert into gtfs_payment_methods (payment_method, description) values (1,'Prepay');


commit;