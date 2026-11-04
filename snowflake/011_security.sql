/*
==============================================================================
 File:        011_security.sql
 Purpose:     Column masking policies (PII/PHI-adjacent fields on the
              respondent dimension) and object tagging for data
              classification, plus final grant reconciliation.

              Even though DIM_RESPONDENT is de-identified before it reaches
              MARTS, region/specialty combinations can be quasi-identifying
              for small panels, so a masking policy is applied for the
              R_PETRF_ANALYST role in non-prod environments.
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;
USE SCHEMA SECURITY_ADMIN;

-- ---------------------------------------------------------------------------
-- 1. DATA CLASSIFICATION TAGS
-- ---------------------------------------------------------------------------

CREATE TAG IF NOT EXISTS DATA_CLASSIFICATION
    ALLOWED_VALUES 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED'
    COMMENT = 'Classifies column sensitivity for governance/audit reporting.';

CREATE TAG IF NOT EXISTS PII_CATEGORY
    ALLOWED_VALUES 'NONE', 'QUASI_IDENTIFIER', 'DIRECT_IDENTIFIER'
    COMMENT = 'Flags columns that require masking policy consideration.';

ALTER TABLE MARTS.DIM_RESPONDENT MODIFY COLUMN region
    SET TAG SECURITY_ADMIN.PII_CATEGORY = 'QUASI_IDENTIFIER';
ALTER TABLE MARTS.DIM_RESPONDENT MODIFY COLUMN specialty
    SET TAG SECURITY_ADMIN.PII_CATEGORY = 'QUASI_IDENTIFIER';

-- ---------------------------------------------------------------------------
-- 2. MASKING POLICY
--    R_PETRF_ADMIN and R_PETRF_TRANSFORMER see unmasked values (required to
--    build/validate models); R_PETRF_ANALYST sees a generalized bucket.
-- ---------------------------------------------------------------------------

CREATE MASKING POLICY IF NOT EXISTS MP_GENERALIZE_REGION AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('R_PETRF_ADMIN', 'R_PETRF_TRANSFORMER', 'R_PETRF_AUDITOR') THEN val
        ELSE 'REGION_MASKED'
    END;

ALTER TABLE MARTS.DIM_RESPONDENT MODIFY COLUMN region
    SET MASKING POLICY MP_GENERALIZE_REGION;

-- ---------------------------------------------------------------------------
-- 3. ROW ACCESS POLICY
--    Example: restrict FACT_RESPONSE visibility for a hypothetical
--    client-scoped analyst role to their contracted therapeutic area only.
--    Mapping table would be populated by the account team; left as a
--    documented pattern here since PETRF is currently single-tenant.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS SECURITY_ADMIN.ANALYST_THERAPEUTIC_AREA_ACCESS (
    role_name           VARCHAR(128),
    therapeutic_area       VARCHAR(128)
)
COMMENT = 'Maps a restricted analyst role to the therapeutic areas it may query. Empty = no restriction applied.';

CREATE ROW ACCESS POLICY IF NOT EXISTS RAP_THERAPEUTIC_AREA_SCOPE
    AS (indication_key NUMBER) RETURNS BOOLEAN ->
    EXISTS (
        SELECT 1
        FROM SECURITY_ADMIN.ANALYST_THERAPEUTIC_AREA_ACCESS a
        JOIN MARTS.DIM_INDICATION d ON d.indication_key = indication_key
        WHERE a.role_name = CURRENT_ROLE()
          AND a.therapeutic_area = d.therapeutic_area
    )
    OR NOT EXISTS (
        SELECT 1 FROM SECURITY_ADMIN.ANALYST_THERAPEUTIC_AREA_ACCESS
        WHERE role_name = CURRENT_ROLE()
    );

-- Applied to FACT_SURVEY_METRICS only (FACT_RESPONSE stays admin/transformer
-- only, gated at the schema grant level rather than row level).
ALTER TABLE MARTS.FACT_SURVEY_METRICS
    ADD ROW ACCESS POLICY RAP_THERAPEUTIC_AREA_SCOPE ON (indication_key);

-- ---------------------------------------------------------------------------
-- 4. FUTURE GRANTS
--    Ensures new tables created by dbt in MARTS automatically inherit
--    read access for analysts, without a manual grant per model.
-- ---------------------------------------------------------------------------

GRANT SELECT ON FUTURE TABLES IN SCHEMA MARTS TO ROLE R_PETRF_ANALYST;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA MARTS TO ROLE R_PETRF_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA MARTS TO ROLE R_PETRF_AUDITOR;
GRANT SELECT ON FUTURE TABLES IN SCHEMA STAGING
TO ROLE R_PETRF_AUDITOR;

GRANT SELECT ON FUTURE TABLES IN SCHEMA INTERMEDIATE
TO ROLE R_PETRF_AUDITOR;
