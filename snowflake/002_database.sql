/*
==============================================================================
 File:        002_database.sql
 Purpose:     Creates the PETRF database and configures data-retention /
              replication defaults.
 Run as:      SYSADMIN (or R_PETRF_ADMIN once granted)
==============================================================================
*/

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS ONCLITE_PETRF
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'OncLite Product Evaluation & Tracking Research Framework - healthcare market research platform.';

GRANT OWNERSHIP ON DATABASE ONCLITE_PETRF TO ROLE R_PETRF_ADMIN COPY CURRENT GRANTS;

USE DATABASE ONCLITE_PETRF;

-- Time-travel is bumped to 1 day on the RAW schema in 003, and left at the
-- 7-day database default for SILVER/GOLD so analysts can recover from a
-- bad dbt run without engineering intervention.
