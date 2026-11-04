/*
==============================================================================
 File:        001_environment.sql
 Project:     OncLite-PETRF-Automation
 Purpose:     Provisions the core Snowflake compute and security environment
              (warehouses, functional roles, service users) for the
              Product Evaluation & Tracking Research Framework (PETRF)
              healthcare market-research data platform.

 Layer:       Environment / Account-level
 Run as:      ACCOUNTADMIN (one-time, or via Terraform/Schemachange in CI)
 Idempotent:  Yes - all statements use CREATE ... IF NOT EXISTS or
              CREATE OR ALTER where supported.
==============================================================================
*/

-- ---------------------------------------------------------------------------
-- 1. WAREHOUSES
--    Separate warehouses per workload so that ingestion, transformation
--    and BI consumption never contend for the same compute credits.
-- ---------------------------------------------------------------------------

CREATE WAREHOUSE IF NOT EXISTS WH_PETRF_LOADING
    WAREHOUSE_SIZE          = 'XSMALL'
    AUTO_SUSPEND            = 60
    AUTO_RESUME             = TRUE
    INITIALLY_SUSPENDED     = TRUE
    MIN_CLUSTER_COUNT       = 1
    MAX_CLUSTER_COUNT       = 2
    SCALING_POLICY          = 'STANDARD'
    COMMENT                 = 'Used by Python/Snowpipe ingestion jobs to load raw CSV survey data.';

CREATE WAREHOUSE IF NOT EXISTS WH_PETRF_TRANSFORM
    WAREHOUSE_SIZE          = 'SMALL'
    AUTO_SUSPEND            = 90
    AUTO_RESUME             = TRUE
    INITIALLY_SUSPENDED     = TRUE
    MIN_CLUSTER_COUNT       = 1
    MAX_CLUSTER_COUNT       = 3
    SCALING_POLICY          = 'ECONOMY'
    COMMENT                 = 'Used by dbt for staging -> intermediate -> marts transformations.';

CREATE WAREHOUSE IF NOT EXISTS WH_PETRF_BI
    WAREHOUSE_SIZE          = 'SMALL'
    AUTO_SUSPEND            = 300
    AUTO_RESUME             = TRUE
    INITIALLY_SUSPENDED     = TRUE
    COMMENT                 = 'Used by Power BI / dashboard consumers for interactive query.';

CREATE WAREHOUSE IF NOT EXISTS WH_PETRF_TASKS
    WAREHOUSE_SIZE          = 'XSMALL'
    AUTO_SUSPEND            = 60
    AUTO_RESUME             = TRUE
    INITIALLY_SUSPENDED     = TRUE
    COMMENT                 = 'Dedicated warehouse for Snowflake Tasks (stream consumption, audit rollups).';

-- ---------------------------------------------------------------------------
-- 2. FUNCTIONAL ROLES
--    Role hierarchy follows Snowflake best practice: functional roles are
--    granted to a top-level admin role, and access roles are granted
--    down to functional roles (not directly to users).
-- ---------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS R_PETRF_ADMIN
    COMMENT = 'Owns all PETRF database objects. Granted only to platform leads.';

CREATE ROLE IF NOT EXISTS R_PETRF_LOADER
    COMMENT = 'Used by ingestion service account to write to RAW/BRONZE schemas.';

CREATE ROLE IF NOT EXISTS R_PETRF_TRANSFORMER
    COMMENT = 'Used by dbt service account to build SILVER/GOLD models.';

CREATE ROLE IF NOT EXISTS R_PETRF_ANALYST
    COMMENT = 'Read-only access to GOLD marts for analysts and Power BI.';

CREATE ROLE IF NOT EXISTS R_PETRF_AUDITOR
    COMMENT = 'Read-only access to audit/logging/error schemas for compliance review.';

GRANT ROLE R_PETRF_LOADER       TO ROLE R_PETRF_ADMIN;
GRANT ROLE R_PETRF_TRANSFORMER  TO ROLE R_PETRF_ADMIN;
GRANT ROLE R_PETRF_ANALYST      TO ROLE R_PETRF_ADMIN;
GRANT ROLE R_PETRF_AUDITOR      TO ROLE R_PETRF_ADMIN;
GRANT ROLE R_PETRF_ADMIN        TO ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- 3. WAREHOUSE GRANTS
-- ---------------------------------------------------------------------------

GRANT USAGE ON WAREHOUSE WH_PETRF_LOADING   TO ROLE R_PETRF_LOADER;
GRANT USAGE ON WAREHOUSE WH_PETRF_TRANSFORM TO ROLE R_PETRF_TRANSFORMER;
GRANT USAGE ON WAREHOUSE WH_PETRF_BI        TO ROLE R_PETRF_ANALYST;
GRANT USAGE ON WAREHOUSE WH_PETRF_TASKS     TO ROLE R_PETRF_TRANSFORMER;
GRANT USAGE ON WAREHOUSE WH_PETRF_TRANSFORM TO ROLE R_PETRF_AUDITOR;

-- ---------------------------------------------------------------------------
-- 4. SERVICE USERS
--    Passwords/keys are never hard-coded here. In practice these users are
--    provisioned with RSA key-pair auth via Terraform/1Password, and the
--    literal below is a placeholder swapped out by the secrets pipeline.
-- ---------------------------------------------------------------------------

CREATE USER IF NOT EXISTS SVC_PETRF_LOADER
    DEFAULT_ROLE      = R_PETRF_LOADER
    DEFAULT_WAREHOUSE = WH_PETRF_LOADING
    RSA_PUBLIC_KEY    = '<INJECTED_AT_DEPLOY_TIME>'
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT           = 'Service account used by python/ingestion/* scripts.';

CREATE USER IF NOT EXISTS SVC_PETRF_DBT
    DEFAULT_ROLE      = R_PETRF_TRANSFORMER
    DEFAULT_WAREHOUSE = WH_PETRF_TRANSFORM
    RSA_PUBLIC_KEY    = '<INJECTED_AT_DEPLOY_TIME>'
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT           = 'Service account used by dbt Cloud / CI dbt runs.';

GRANT ROLE R_PETRF_LOADER TO USER JANSIRANIP24;
GRANT ROLE R_PETRF_TRANSFORMER TO USER JANSIRANIP24;

-- ---------------------------------------------------------------------------
-- 5. RESOURCE MONITORS
--    Guardrails so a runaway backfill cannot blow the monthly credit budget.
-- ---------------------------------------------------------------------------

CREATE RESOURCE MONITOR IF NOT EXISTS RM_PETRF_MONTHLY
    WITH CREDIT_QUOTA = 500
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75  PERCENT DO NOTIFY
        ON 90  PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE WH_PETRF_LOADING   SET RESOURCE_MONITOR = RM_PETRF_MONTHLY;
ALTER WAREHOUSE WH_PETRF_TRANSFORM SET RESOURCE_MONITOR = RM_PETRF_MONTHLY;
ALTER WAREHOUSE WH_PETRF_BI        SET RESOURCE_MONITOR = RM_PETRF_MONTHLY;
