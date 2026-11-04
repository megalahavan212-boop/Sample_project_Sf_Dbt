/*
==============================================================================
 File:        006_tables.sql
 Purpose:     Full table DDL for OncLite-PETRF:
                - RAW (bronze landing tables, 1:1 with source CSVs)
                - MARTS dimension tables (DIM_*)
                - MARTS fact tables (FACT_*)
                - Bridge table (PRODUCT_INDICATION)
                - AUDIT and ERROR_HANDLING operational tables
              Note: STAGING and INTERMEDIATE tables are dbt-managed views/
              tables built via `dbt run` (see dbt/onclite_petrf_dbt) and are
              intentionally NOT hand-created here.
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;

-- =============================================================================
-- SECTION 1: RAW (BRONZE) LANDING TABLES
-- =============================================================================
USE SCHEMA RAW;

CREATE TABLE IF NOT EXISTS RAW_SURVEY (
    survey_id_src           VARCHAR(64),
    survey_name             VARCHAR(255),
    survey_type             VARCHAR(64),
    indication_code         VARCHAR(32),
    wave_code                VARCHAR(32),
    launch_date              VARCHAR(32),   -- kept as text at bronze; typed in staging
    close_date                VARCHAR(32),
    fielding_vendor          VARCHAR(128),
    _file_name                VARCHAR(500),
    _row_number                NUMBER,
    _loaded_at                 TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze: raw survey_master.csv exports, untyped, no dedup.';

CREATE TABLE IF NOT EXISTS RAW_RESPONDENT (
    respondent_id_src        VARCHAR(64),
    survey_id_src             VARCHAR(64),
    specialty                  VARCHAR(128),
    years_in_practice          VARCHAR(16),
    region                      VARCHAR(64),
    country_code                 VARCHAR(8),
    panel_source                  VARCHAR(64),
    consent_flag                   VARCHAR(8),
    _file_name                     VARCHAR(500),
    _row_number                     NUMBER,
    _loaded_at                      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze: raw respondent_panel.csv exports (HCP survey panel members).';

CREATE TABLE IF NOT EXISTS RAW_QUESTION (
    question_id_src           VARCHAR(64),
    survey_id_src               VARCHAR(64),
    question_text                 VARCHAR(2000),
    question_type                  VARCHAR(64),
    question_category               VARCHAR(128),
    product_code_ref                  VARCHAR(32),
    _file_name                        VARCHAR(500),
    _row_number                        NUMBER,
    _loaded_at                          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze: raw question_bank.csv exports.';

CREATE TABLE IF NOT EXISTS RAW_RESPONSE (
    response_id_src            VARCHAR(64),
    survey_id_src                VARCHAR(64),
    respondent_id_src              VARCHAR(64),
    question_id_src                  VARCHAR(64),
    product_code_ref                   VARCHAR(32),
    response_value                       VARCHAR(2000),
    response_score                        VARCHAR(32),  -- text at bronze; NUMBER at staging
    response_timestamp                     VARCHAR(32),
    _file_name                              VARCHAR(500),
    _row_number                              NUMBER,
    _loaded_at                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze: raw response_data.csv exports - one row per respondent/question answer.';

CREATE TABLE IF NOT EXISTS RAW_PRODUCT (
    product_code_src          VARCHAR(32),
    product_name                VARCHAR(255),
    manufacturer                  VARCHAR(255),
    molecule                        VARCHAR(255),
    therapeutic_class                 VARCHAR(128),
    launch_status                       VARCHAR(64),
    _file_name                          VARCHAR(500),
    _row_number                          NUMBER,
    _loaded_at                           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze: raw product_master.csv exports.';

CREATE TABLE IF NOT EXISTS RAW_INDICATION (
    indication_code_src       VARCHAR(32),
    indication_name              VARCHAR(255),
    therapeutic_area                VARCHAR(128),
    icd10_code                        VARCHAR(16),
    _file_name                        VARCHAR(500),
    _row_number                        NUMBER,
    _loaded_at                          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze: raw indication_master.csv exports.';

CREATE TABLE IF NOT EXISTS RAW_PRODUCT_INDICATION (
    product_code_src           VARCHAR(32),
    indication_code_src           VARCHAR(32),
    is_primary_indication            VARCHAR(8),
    approval_date                       VARCHAR(32),
    _file_name                          VARCHAR(500),
    _row_number                          NUMBER,
    _loaded_at                            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze: raw product-to-indication mapping exports (many-to-many).';

-- =============================================================================
-- SECTION 2: GOLD DIMENSION TABLES
--   Convention: surrogate integer key (_key) is IDENTITY; the natural/source
--   key from the vendor system is retained as *_id for lineage and joins from
--   fact tables. All dims carry audit columns and are managed as dbt
--   snapshots/tables (this DDL documents the target contract dbt builds to).
-- =============================================================================
USE SCHEMA MARTS;

CREATE TABLE IF NOT EXISTS DIM_PRODUCT (
    product_key             NUMBER          IDENTITY(1,1) PRIMARY KEY,
    product_id                VARCHAR(32)   NOT NULL UNIQUE,   -- natural key
    product_name                VARCHAR(255) NOT NULL,
    manufacturer                  VARCHAR(255),
    molecule                        VARCHAR(255),
    therapeutic_class                 VARCHAR(128),
    launch_status                       VARCHAR(64),
    is_current                           BOOLEAN      DEFAULT TRUE,
    dbt_valid_from                        TIMESTAMP_NTZ,
    dbt_valid_to                            TIMESTAMP_NTZ,
    created_at                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at                                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Gold: SCD Type-2 tracked product dimension (pharma/device products under study).';

CREATE TABLE IF NOT EXISTS DIM_INDICATION (
    indication_key            NUMBER        IDENTITY(1,1) PRIMARY KEY,
    indication_id                VARCHAR(32) NOT NULL UNIQUE,
    indication_name                 VARCHAR(255) NOT NULL,
    therapeutic_area                   VARCHAR(128),
    icd10_code                           VARCHAR(16),
    created_at                            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at                             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Gold: disease/indication dimension.';

CREATE TABLE IF NOT EXISTS DIM_SURVEY (
    survey_key                NUMBER        IDENTITY(1,1) PRIMARY KEY,
    survey_id                    VARCHAR(64) NOT NULL UNIQUE,
    survey_name                     VARCHAR(255) NOT NULL,
    survey_type                       VARCHAR(64),
    fielding_vendor                     VARCHAR(128),
    launch_date                           DATE,
    close_date                             DATE,
    created_at                              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Gold: survey instance dimension - one row per fielded PETRF survey.';

CREATE TABLE IF NOT EXISTS DIM_WAVE (
    wave_key                  NUMBER        IDENTITY(1,1) PRIMARY KEY,
    wave_id                      VARCHAR(32) NOT NULL UNIQUE,
    wave_code                       VARCHAR(32) NOT NULL,
    wave_sequence                     NUMBER,
    wave_start_date                     DATE,
    wave_end_date                         DATE,
    created_at                             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at                              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Gold: tracking-wave dimension (PETRF studies are longitudinal, run in waves).';

CREATE TABLE IF NOT EXISTS DIM_RESPONDENT (
    respondent_key             NUMBER        IDENTITY(1,1) PRIMARY KEY,
    respondent_id                 VARCHAR(64) NOT NULL UNIQUE,
    specialty                        VARCHAR(128),
    years_in_practice_bucket           VARCHAR(32),
    region                                VARCHAR(64),
    country_code                          VARCHAR(8),
    panel_source                           VARCHAR(64),
    consent_flag                            BOOLEAN,
    created_at                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at                                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Gold: de-identified HCP respondent dimension. No direct identifiers persisted (PII stripped in staging).';

CREATE TABLE IF NOT EXISTS DIM_QUESTION (
    question_key                NUMBER        IDENTITY(1,1) PRIMARY KEY,
    question_id                    VARCHAR(64) NOT NULL UNIQUE,
    question_text                     VARCHAR(2000),
    question_type                       VARCHAR(64),
    question_category                     VARCHAR(128),
    product_key_ref                        NUMBER REFERENCES DIM_PRODUCT(product_key),
    created_at                              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Gold: survey question dimension.';

-- =============================================================================
-- SECTION 3: BRIDGE TABLE (many-to-many product <-> indication)
-- =============================================================================

CREATE TABLE IF NOT EXISTS PRODUCT_INDICATION (
    product_indication_key       NUMBER  IDENTITY(1,1) PRIMARY KEY,
    product_key                     NUMBER NOT NULL REFERENCES DIM_PRODUCT(product_key),
    indication_key                     NUMBER NOT NULL REFERENCES DIM_INDICATION(indication_key),
    is_primary_indication                 BOOLEAN DEFAULT FALSE,
    approval_date                           DATE,
    created_at                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT UQ_PRODUCT_INDICATION UNIQUE (product_key, indication_key)
)
COMMENT = 'Gold bridge: resolves many-to-many relationship between products and treated indications.';

-- =============================================================================
-- SECTION 4: FACT TABLES
-- =============================================================================

CREATE TABLE IF NOT EXISTS FACT_RESPONSE (
    response_key                 NUMBER   IDENTITY(1,1) PRIMARY KEY,
    response_id                     VARCHAR(64) NOT NULL UNIQUE,
    survey_key                        NUMBER NOT NULL REFERENCES DIM_SURVEY(survey_key),
    wave_key                            NUMBER REFERENCES DIM_WAVE(wave_key),
    respondent_key                        NUMBER NOT NULL REFERENCES DIM_RESPONDENT(respondent_key),
    question_key                            NUMBER NOT NULL REFERENCES DIM_QUESTION(question_key),
    product_key                              NUMBER REFERENCES DIM_PRODUCT(product_key),
    response_value                            VARCHAR(2000),
    response_score                             NUMBER(10,2),
    response_timestamp                          TIMESTAMP_NTZ,
    load_date                                   DATE DEFAULT CURRENT_DATE(),
    created_at                                   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Gold: grain = one row per respondent answer to one question, in one wave, for one survey.';

CREATE TABLE IF NOT EXISTS FACT_SURVEY_METRICS (
    survey_metric_key             NUMBER  IDENTITY(1,1) PRIMARY KEY,
    survey_key                       NUMBER NOT NULL REFERENCES DIM_SURVEY(survey_key),
    wave_key                            NUMBER REFERENCES DIM_WAVE(wave_key),
    product_key                          NUMBER REFERENCES DIM_PRODUCT(product_key),
    indication_key                        NUMBER REFERENCES DIM_INDICATION(indication_key),
    metric_date                            DATE NOT NULL,
    respondent_count                        NUMBER,
    completion_rate                          NUMBER(5,2),
    avg_response_score                        NUMBER(10,2),
    nps_score                                  NUMBER(6,2),
    awareness_pct                               NUMBER(5,2),
    preference_pct                               NUMBER(5,2),
    created_at                                    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT UQ_SURVEY_METRIC UNIQUE (survey_key, wave_key, product_key, indication_key, metric_date)
)
COMMENT = 'Gold: pre-aggregated wave-level KPI table consumed directly by Power BI for fast dashboard load.';

-- =============================================================================
-- SECTION 5: OPERATIONAL SCHEMAS - AUDIT + ERROR HANDLING
-- =============================================================================
USE SCHEMA AUDIT;

CREATE TABLE IF NOT EXISTS PIPELINE_RUN_LOG (
    run_id                  VARCHAR(64)   DEFAULT UUID_STRING() PRIMARY KEY,
    pipeline_name              VARCHAR(128) NOT NULL,
    source_file                   VARCHAR(500),
    target_table                     VARCHAR(128),
    status                              VARCHAR(32) NOT NULL,   -- STARTED / SUCCESS / FAILED
    rows_read                            NUMBER,
    rows_loaded                           NUMBER,
    rows_rejected                          NUMBER,
    started_at                              TIMESTAMP_NTZ NOT NULL,
    ended_at                                 TIMESTAMP_NTZ,
    duration_seconds                          NUMBER,
    error_message                              VARCHAR(4000),
    triggered_by                                VARCHAR(64)    -- 'airflow' | 'manual' | 'task'
)
COMMENT = 'One row per pipeline execution (Python ingestion, dbt run, or Snowflake Task run).';

CREATE TABLE IF NOT EXISTS DBT_RUN_SUMMARY (
    run_id                  VARCHAR(64)   DEFAULT UUID_STRING() PRIMARY KEY,
    invocation_id              VARCHAR(64),
    model_name                    VARCHAR(255),
    status                            VARCHAR(32),
    rows_affected                        NUMBER,
    execution_time_seconds                NUMBER,
    run_started_at                         TIMESTAMP_NTZ,
    materialization                         VARCHAR(32)
)
COMMENT = 'Populated by dbt on-run-end hook (see macros/log_dbt_run_results.sql) for observability.';

USE SCHEMA ERROR_HANDLING;

CREATE TABLE IF NOT EXISTS REJECTED_RECORDS (
    rejection_id             NUMBER   IDENTITY(1,1) PRIMARY KEY,
    source_file                  VARCHAR(500),
    source_table                    VARCHAR(128),
    raw_row_number                     NUMBER,
    raw_payload                          VARIANT,
    rejection_reason                       VARCHAR(1000),
    rejection_category                       VARCHAR(64),  -- SCHEMA | NULL_CHECK | DUPLICATE | REFERENTIAL
    rejected_at                               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    resolved_flag                              BOOLEAN DEFAULT FALSE
)
COMMENT = 'Records that failed python/validation checks or dbt not_null/relationships tests, quarantined for review.';

CREATE TABLE IF NOT EXISTS DQ_TEST_RESULTS (
    test_result_id            NUMBER  IDENTITY(1,1) PRIMARY KEY,
    test_name                    VARCHAR(255),
    model_name                      VARCHAR(255),
    test_type                          VARCHAR(64),   -- unique | not_null | relationships | custom
    status                                VARCHAR(32),   -- PASS | FAIL | WARN
    failing_rows                          NUMBER,
    executed_at                             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Captures dbt test outcomes for trend analysis and CI gating.';
