/*
==============================================================================
 File:        004_file_formats.sql
 Purpose:     Defines reusable file formats for CSV ingestion. Two variants:
              a strict format for well-formed survey exports and a lenient
              format used by the quarantine/reprocessing path.
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;
USE SCHEMA RAW;

CREATE FILE FORMAT IF NOT EXISTS FF_PETRF_CSV_STRICT
    TYPE                        = 'CSV'
    FIELD_DELIMITER             = ','
    SKIP_HEADER                 = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                     = ('', 'NULL', 'null', 'NA', 'N/A')
    EMPTY_FIELD_AS_NULL         = TRUE
    TRIM_SPACE                  = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
    DATE_FORMAT                 = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT             = 'YYYY-MM-DD HH24:MI:SS'
    ENCODING                    = 'UTF8'
    COMMENT = 'Strict CSV parsing for validated survey/waves exports. Fails fast on column mismatch.';

CREATE FILE FORMAT IF NOT EXISTS FF_PETRF_CSV_LENIENT
    TYPE                        = 'CSV'
    FIELD_DELIMITER             = ','
    SKIP_HEADER                 = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                     = ('', 'NULL', 'null', 'NA', 'N/A')
    EMPTY_FIELD_AS_NULL         = TRUE
    TRIM_SPACE                  = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    ENCODING                    = 'UTF8'
    COMMENT = 'Lenient CSV parsing used by COPY INTO ... ON_ERROR = CONTINUE for quarantine loads.';

CREATE FILE FORMAT IF NOT EXISTS FF_PETRF_JSON
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE
    COMMENT = 'Used for occasional semi-structured payloads (e.g. respondent metadata exports).';
