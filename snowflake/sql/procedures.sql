/*
==============================================================================
 File:        sql/procedures.sql
 Purpose:     Stored procedures supporting the ingestion + CDC pipeline:
                - SP_LOAD_RAW_FROM_STAGE: parameterized COPY INTO wrapper
                  with structured audit logging and quarantine routing.
                - SP_REFRESH_DIM_PRODUCT: SCD Type-2 merge example.
                - SP_PURGE_PROCESSED_STAGE_FILES: housekeeping.
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;
USE SCHEMA RAW;

CREATE OR REPLACE PROCEDURE SP_LOAD_RAW_FROM_STAGE(
    p_stage_path    VARCHAR,
    p_target_table  VARCHAR,
    p_column_list   VARCHAR,
    p_file_format   VARCHAR DEFAULT 'FF_PETRF_CSV_STRICT'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_start_ts       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    v_rows_loaded     NUMBER DEFAULT 0;
    v_rows_rejected    NUMBER DEFAULT 0;
    v_error_msg         VARCHAR DEFAULT NULL;
    v_status              VARCHAR DEFAULT 'SUCCESS';
    v_copy_sql              VARCHAR;
    v_result_row              VARIANT;
BEGIN
    v_copy_sql := 'COPY INTO ' || :p_target_table || ' (' || :p_column_list ||
                  ', _file_name, _row_number) FROM (SELECT ' ||
                  '$1,$2,$3,$4,$5,$6,$7,$8, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER ' ||
                  'FROM ' || :p_stage_path || ') FILE_FORMAT = (FORMAT_NAME = ' || :p_file_format ||
                  ') ON_ERROR = ''CONTINUE''';

    BEGIN
        EXECUTE IMMEDIATE :v_copy_sql;

        SELECT PARSE_JSON('{"rows_loaded":' || COALESCE("rows_loaded",0)::STRING ||
                           ',"rows_parsed":' || COALESCE("rows_parsed",0)::STRING || '}')
        INTO :v_result_row
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        v_rows_loaded := v_result_row:rows_loaded::NUMBER;
        v_rows_rejected := GREATEST(v_result_row:rows_parsed::NUMBER - v_rows_loaded, 0);

    EXCEPTION
        WHEN OTHER THEN
            v_status := 'FAILED';
            v_error_msg := SQLERRM;
    END;

    INSERT INTO ONCLITE_PETRF.AUDIT.PIPELINE_RUN_LOG
        (pipeline_name, source_file, target_table, status, rows_read,
         rows_loaded, rows_rejected, started_at, ended_at, duration_seconds,
         error_message, triggered_by)
    VALUES
        ('SP_LOAD_RAW_FROM_STAGE', :p_stage_path, :p_target_table, :v_status,
         :v_rows_loaded + :v_rows_rejected, :v_rows_loaded, :v_rows_rejected,
         :v_start_ts, CURRENT_TIMESTAMP(),
         DATEDIFF('second', :v_start_ts, CURRENT_TIMESTAMP()),
         :v_error_msg, 'stored_procedure');

    RETURN OBJECT_CONSTRUCT(
        'status', :v_status,
        'rows_loaded', :v_rows_loaded,
        'rows_rejected', :v_rows_rejected,
        'error_message', :v_error_msg
    );
END;
$$;

-- -----------------------------------------------------------------------
-- SCD Type-2 refresh for DIM_PRODUCT. Called after RAW_PRODUCT loads, or
-- from the dbt on-run-end hook for full-refresh scenarios.
-- -----------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REFRESH_DIM_PRODUCT()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    -- Step 1: expire rows whose attributes have changed
    UPDATE ONCLITE_PETRF.MARTS.DIM_PRODUCT d
    SET is_current = FALSE,
        dbt_valid_to = CURRENT_TIMESTAMP(),
        updated_at = CURRENT_TIMESTAMP()
    FROM (
        SELECT DISTINCT product_code_src, product_name, manufacturer, molecule,
               therapeutic_class, launch_status
        FROM ONCLITE_PETRF.RAW.RAW_PRODUCT
    ) src
    WHERE d.product_id = src.product_code_src
      AND d.is_current = TRUE
      AND (d.product_name        != src.product_name
        OR d.manufacturer         != src.manufacturer
        OR d.molecule               != src.molecule
        OR d.therapeutic_class       != src.therapeutic_class
        OR d.launch_status             != src.launch_status);

    -- Step 2: insert new + changed rows as current
    INSERT INTO ONCLITE_PETRF.MARTS.DIM_PRODUCT
        (product_id, product_name, manufacturer, molecule, therapeutic_class,
         launch_status, is_current, dbt_valid_from, dbt_valid_to)
    SELECT
        src.product_code_src, src.product_name, src.manufacturer, src.molecule,
        src.therapeutic_class, src.launch_status, TRUE, CURRENT_TIMESTAMP(), NULL
    FROM (
        SELECT DISTINCT product_code_src, product_name, manufacturer, molecule,
               therapeutic_class, launch_status
        FROM ONCLITE_PETRF.RAW.RAW_PRODUCT
    ) src
    LEFT JOIN ONCLITE_PETRF.MARTS.DIM_PRODUCT d
        ON d.product_id = src.product_code_src AND d.is_current = TRUE
    WHERE d.product_key IS NULL;

    RETURN OBJECT_CONSTRUCT('status', 'SUCCESS', 'executed_at', CURRENT_TIMESTAMP()::STRING);
END;
$$;

-- -----------------------------------------------------------------------
-- Housekeeping: move files older than N days out of the landing stage
-- directory table listing into the archive stage's logical namespace.
-- -----------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_PURGE_PROCESSED_STAGE_FILES(p_older_than_days NUMBER DEFAULT 7)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO :v_count
    FROM DIRECTORY(@STG_PETRF_LANDING)
    WHERE last_modified < DATEADD('day', -1 * :p_older_than_days, CURRENT_TIMESTAMP());

    -- Actual file move requires REMOVE + re-PUT via external tooling or a
    -- Python UDF; this procedure reports candidates for the housekeeping
    -- Airflow task (automation/airflow/dags/petrf_housekeeping_dag.py).
    RETURN :v_count || ' files older than ' || :p_older_than_days || ' days identified for archival.';
END;
$$;

GRANT USAGE ON PROCEDURE SP_LOAD_RAW_FROM_STAGE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE R_PETRF_LOADER;
GRANT USAGE ON PROCEDURE SP_REFRESH_DIM_PRODUCT() TO ROLE R_PETRF_TRANSFORMER;
GRANT USAGE ON PROCEDURE SP_PURGE_PROCESSED_STAGE_FILES(NUMBER) TO ROLE R_PETRF_LOADER;
