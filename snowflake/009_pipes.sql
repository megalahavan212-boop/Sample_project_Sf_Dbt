/*
==============================================================================
 File:        009_pipes.sql
 Purpose:     Snowpipe definitions for near-real-time auto-ingestion of CSVs
              landing in STG_PETRF_LANDING. Used as an alternative to the
              batch Python COPY INTO path (python/ingestion/loader.py) for
              high-frequency response files; both paths write to the same
              RAW tables so downstream models are agnostic to load method.
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;
USE SCHEMA RAW;

CREATE OR REPLACE PIPE PIPE_PETRF_RESPONSE_AUTOINGEST
    COMMENT = 'Auto-ingests response_data_*.csv files landing under @STG_PETRF_LANDING/response/.'
AS
    COPY INTO RAW_RESPONSE (
        response_id_src, survey_id_src, respondent_id_src, question_id_src,
        product_code_ref, response_value, response_score, response_timestamp,
        _file_name, _row_number
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8,
            METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
        FROM @STG_PETRF_LANDING/response/
    )
    FILE_FORMAT = (FORMAT_NAME = FF_PETRF_CSV_STRICT)
    ON_ERROR = 'CONTINUE';

CREATE OR REPLACE PIPE PIPE_PETRF_SURVEY_AUTOINGEST
    COMMENT = 'Auto-ingests survey_master_*.csv files landing under @STG_PETRF_LANDING/survey/.'
AS
    COPY INTO RAW_SURVEY (
        survey_id_src, survey_name, survey_type, indication_code, wave_code,
        launch_date, close_date, fielding_vendor, _file_name, _row_number
    )
    FROM (
        SELECT
            $1, $2, $3, $4, $5, $6, $7, $8,
            METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
        FROM @STG_PETRF_LANDING/survey/
    )
    FILE_FORMAT = (FORMAT_NAME = FF_PETRF_CSV_STRICT)
    ON_ERROR = 'CONTINUE';

-- NOTE: AUTO_INGEST = TRUE requires a cloud-provider notification
-- integration (SQS for S3, Event Grid for Azure Blob) wired to the stage's
-- underlying external location. Since STG_PETRF_LANDING is an internal
-- stage in this reference implementation, ingestion in practice is driven
-- by python/ingestion/loader.py issuing explicit COPY INTO statements, and
-- these pipe definitions exist to document the migration path to
-- external-stage + event-driven autoingest at higher data volumes.

SHOW PIPES LIKE 'PIPE_PETRF%';
