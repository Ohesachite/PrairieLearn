CREATE TABLE IF NOT EXISTS course_instances (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID NOT NULL UNIQUE,
    course_id BIGINT NOT NULL REFERENCES courses ON DELETE CASCADE ON UPDATE CASCADE,
    short_name varchar(255),
    long_name varchar(255),
    number INTEGER,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- FIXME: make NOT NULL after upgrade is done
ALTER TABLE course_instances ADD COLUMN IF NOT EXISTS uuid UUID UNIQUE;

ALTER TABLE course_instances DROP CONSTRAINT IF EXISTS course_instances_short_name_course_id_key;

ALTER TABLE course_instances ALTER COLUMN id SET DATA TYPE BIGINT;
ALTER TABLE course_instances ALTER COLUMN course_id SET DATA TYPE BIGINT;
