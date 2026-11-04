/*
==============================================================================
 File:        005_stages.sql
 Purpose:     Internal stages used to land CSV survey exports before they are
              COPY INTO'd into RAW tables. A separate quarantine stage holds
              files that fail strict validation.
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;
USE SCHEMA RAW;

-- Primary landing stage. Server-side encryption is the Snowflake default;
-- directory table is enabled so Python can list/verify uploaded files.
CREATE STAGE IF NOT EXISTS STG_PETRF_LANDING
    FILE_FORMAT = FF_PETRF_CSV_STRICT
    DIRECTORY   = (ENABLE = TRUE)
    COMMENT = 'Internal stage that Python ingestion PUTs raw survey CSVs to before COPY INTO.';

-- Quarantine stage for files that fail schema/row validation.
CREATE STAGE IF NOT EXISTS STG_PETRF_QUARANTINE
    FILE_FORMAT = FF_PETRF_CSV_LENIENT
    DIRECTORY   = (ENABLE = TRUE)
    COMMENT = 'Holds CSV files that failed validation in python/validation for manual review.';

-- Archive stage for successfully processed files (cost-optimized retention).
CREATE STAGE IF NOT EXISTS STG_PETRF_ARCHIVE
    FILE_FORMAT = FF_PETRF_CSV_STRICT
    DIRECTORY   = (ENABLE = TRUE)
    COMMENT = 'Successfully loaded files are moved here for a 90-day audit trail before deletion.';

GRANT READ, WRITE ON STAGE STG_PETRF_LANDING    TO ROLE R_PETRF_LOADER;
GRANT READ, WRITE ON STAGE STG_PETRF_QUARANTINE TO ROLE R_PETRF_LOADER;
GRANT READ, WRITE ON STAGE STG_PETRF_ARCHIVE    TO ROLE R_PETRF_LOADER;
GRANT READ ON STAGE STG_PETRF_QUARANTINE TO ROLE R_PETRF_AUDITOR;
