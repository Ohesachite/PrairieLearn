CREATE OR REPLACE FUNCTION
    sync_course_instances_new(
        IN disk_course_instances_data JSONB[],
        IN syncing_course_id bigint,
        OUT course_instance_ids JSONB
    )
AS $$
BEGIN
    -- Move all our data into a temporary table so it's easier to work with
    DROP TABLE IF EXISTS disk_course_instances;
    CREATE TEMPORARY TABLE disk_course_instances (
        short_name TEXT NOT NULL,
        uuid uuid,
        errors TEXT,
        warnings TEXT,
        data JSONB
    ) ON COMMIT DROP;
    INSERT INTO disk_course_instances (
        short_name,
        uuid,
        errors,
        warnings,
        data
    ) SELECT
        entries->>0,
        (entries->>1)::uuid,
        entries->>2,
        entries->>3,
        (entries->4)::JSONB
    FROM UNNEST(disk_course_instances_data) AS entries;

    -- First, update the names of everything we have a UUID for
    UPDATE course_instances AS ci
    SET short_name = dci.short_name, deleted_at = NULL
    FROM disk_course_instances AS dci
    WHERE
        dci.uuid IS NOT NULL
        AND ci.uuid = dci.uuid
        AND ci.course_id = syncing_course_id;

    -- Next, add known UUIDs to previously synced course instances without UUIDS
    UPDATE course_instances AS ci
    SET uuid = dci.uuid 
    FROM disk_course_instances AS dci
    WHERE
        dci.uuid IS NOT NULL
        AND ci.short_name = dci.short_name
        AND ci.deleted_at IS NULL
        AND ci.uuid IS NULL
        AND ci.course_id = syncing_course_id;

    -- Next, soft-delete any rows for which we have a mismatched UUID
    UPDATE course_instances AS ci
    SET deleted_at = now()
    FROM disk_course_instances AS dci
    WHERE
        ci.short_name = dci.short_name
        AND ci.deleted_at IS NOT NULL
        AND dci.uuid IS NOT NULL
        AND ci.uuid IS NOT NULL
        AND ci.uuid != dci.uuid
        AND ci.course_id = syncing_course_id;

    -- Insert new rows for missing names for which we have a UUID
    WITH short_names_to_insert AS (
        SELECT short_name FROM disk_course_instances WHERE uuid IS NOT NULL
        EXCEPT
        SELECT short_name FROM course_instances WHERE deleted_at IS NULL
    )
    INSERT INTO course_instances (short_name, uuid, course_id)
    SELECT
        snti.short_name,
        dci.uuid,
        syncing_course_id
    FROM
        short_names_to_insert AS snti
        JOIN disk_course_instances AS dci ON (dci.short_name = snti.short_name);

    -- Insert new rows for missing names for which we do not have a UUID
    WITH short_names_to_insert AS (
        SELECT short_name FROM disk_course_instances WHERE uuid IS NULL
        EXCEPT
        SELECT short_name FROM course_instances WHERE deleted_at IS NULL
    )
    INSERT INTO course_instances (short_name, course_id)
    SELECT short_name, syncing_course_id FROM short_names_to_insert;

    -- Finally, soft-delete rows with unwanted names
    WITH short_names_to_delete AS (
        SELECT short_name FROM course_instances WHERE deleted_at IS NULL
        EXCEPT
        SELECT short_name FROM disk_course_instances
    )
    UPDATE course_instances
    SET deleted_at = now()
    FROM short_names_to_delete
    WHERE course_instances.short_name = short_names_to_delete.short_name;


    -- At this point, there will be exactly one non-deleted row for all short names
    -- that we loaded from disk. It is now safe to update all those rows with
    -- the new information from disk (if we have any).

    -- First pass: update complete information for all course instances without errors
    UPDATE course_instances AS ci
    SET
        long_name = dci.data->>'long_name',
        number = (dci.data->>'number')::integer,
        display_timezone = dci.data->>'display_timezone',
        sync_errors = NULL,
        sync_warnings = dci.warnings
    FROM disk_course_instances AS dci
    WHERE
        ci.short_name = dci.short_name
        AND ci.course_id = syncing_course_id
        AND (dci.errors IS NULL OR dci.errors = '');

    -- Second pass: add errors where needed.
    UPDATE course_instances AS ci
    SET
        sync_errors = dci.errors,
        sync_warnings = dci.warnings
    FROM disk_course_instances AS dci
    WHERE
        ci.short_name = dci.short_name
        AND ci.course_id = syncing_course_id
        AND (dci.errors IS NOT NULL AND dci.errors != '');

    -- Make a map from CIID to ID to return to the caller
    SELECT
        coalesce(
            jsonb_agg(jsonb_build_array(ci.short_name, ci.id)),
            '[]'::jsonb
        ) AS course_instances_json
    FROM course_instances AS ci, disk_course_instances AS dci
    INTO course_instance_ids
    WHERE
        ci.short_name = dci.short_name
        AND ci.course_id = syncing_course_id;
END;
$$ LANGUAGE plpgsql VOLATILE;
