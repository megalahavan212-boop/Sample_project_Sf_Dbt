/*
==============================================================================
 File:        003_schema.sql
 Purpose:     Creates the medallion-architecture schemas plus supporting
              operational schemas (audit, error logging, staging area for
              internal stages).
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;

-- Bronze: raw, untransformed landing zone. 1:1 with source CSV structure.
CREATE SCHEMA IF NOT EXISTS RAW
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Bronze layer - raw CSV data loaded as-is from internal stages, no transformation.';

-- Silver: cleaned, typed, deduplicated staging models built by dbt.
CREATE SCHEMA IF NOT EXISTS STAGING
    COMMENT = 'Silver layer - dbt staging models: typed, renamed, deduplicated.';

-- Intermediate: reusable business-logic building blocks, not exposed to BI.
CREATE SCHEMA IF NOT EXISTS INTERMEDIATE
    COMMENT = 'Silver+ layer - dbt intermediate models joining/aggregating staging models.';

-- Gold: dimensional model consumed by Power BI and analysts.
CREATE SCHEMA IF NOT EXISTS MARTS
    COMMENT = 'Gold layer - dbt mart models (dimensions + facts) for BI consumption.';

-- Operational schemas
CREATE SCHEMA IF NOT EXISTS AUDIT
    COMMENT = 'Pipeline run metadata: load history, row counts, durations.';

CREATE SCHEMA IF NOT EXISTS ERROR_HANDLING
    COMMENT = 'Rejected records and structured error/exception logs.';

CREATE SCHEMA IF NOT EXISTS SECURITY_ADMIN
    COMMENT = 'Row access policies, masking policies, and tag definitions.';

-- Grants: least-privilege by schema
GRANT USAGE, CREATE TABLE, CREATE STAGE, CREATE FILE FORMAT ON SCHEMA RAW TO ROLE R_PETRF_LOADER;
GRANT USAGE ON SCHEMA RAW TO ROLE R_PETRF_TRANSFORMER;

GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA STAGING TO ROLE R_PETRF_TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA INTERMEDIATE TO ROLE R_PETRF_TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA MARTS TO ROLE R_PETRF_TRANSFORMER;

GRANT USAGE ON SCHEMA MARTS TO ROLE R_PETRF_ANALYST;

GRANT USAGE ON SCHEMA AUDIT TO ROLE R_PETRF_AUDITOR;
GRANT USAGE ON SCHEMA ERROR_HANDLING TO ROLE R_PETRF_AUDITOR;

GRANT USAGE, CREATE TABLE ON SCHEMA AUDIT TO ROLE R_PETRF_LOADER;
GRANT USAGE, CREATE TABLE ON SCHEMA ERROR_HANDLING TO ROLE R_PETRF_LOADER;

GRANT USAGE, CREATE TABLE ON SCHEMA AUDIT TO ROLE R_PETRF_TRANSFORMER;
GRANT USAGE, CREATE TABLE ON SCHEMA ERROR_HANDLING TO ROLE R_PETRF_TRANSFORMER;