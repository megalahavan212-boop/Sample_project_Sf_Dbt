/*
==============================================================================
 File:        008_tasks.sql
 Purpose:     Snowflake Tasks for PETRF CDC Pipeline
==============================================================================
*/

USE ROLE R_PETRF_ADMIN;
USE DATABASE ONCLITE_PETRF;
USE SCHEMA RAW;

-- Root scheduler
CREATE OR REPLACE TASK TASK_ROOT_PETRF_INGEST_SCHEDULE
    WAREHOUSE = WH_PETRF_TASKS
    SCHEDULE = '15 MINUTE'
AS
SELECT CURRENT_TIMESTAMP();

------------------------------------------------------------
-- Response Stream Task
------------------------------------------------------------

CREATE OR REPLACE TASK TASK_MERGE_RESPONSE_STREAM
    WAREHOUSE = WH_PETRF_TASKS
    AFTER TASK_ROOT_PETRF_INGEST_SCHEDULE
    WHEN SYSTEM$STREAM_HAS_DATA('STRM_RAW_RESPONSE')
AS

INSERT INTO ONCLITE_PETRF.AUDIT.PIPELINE_RUN_LOG
(
    pipeline_name,
    target_table,
    status,
    rows_read,
    rows_loaded,
    rows_rejected,
    started_at,
    ended_at,
    duration_seconds,
    triggered_by
)

SELECT
'TASK_MERGE_RESPONSE_STREAM',
'RAW_RESPONSE',
'SUCCESS',
COUNT(*),
COUNT(*),
0,
CURRENT_TIMESTAMP(),
CURRENT_TIMESTAMP(),
0,
'task'
FROM STRM_RAW_RESPONSE;

------------------------------------------------------------
-- Survey Stream Task
------------------------------------------------------------

CREATE OR REPLACE TASK TASK_MERGE_SURVEY_STREAM
    WAREHOUSE = WH_PETRF_TASKS
    AFTER TASK_ROOT_PETRF_INGEST_SCHEDULE
    WHEN SYSTEM$STREAM_HAS_DATA('STRM_RAW_SURVEY')
AS

INSERT INTO ONCLITE_PETRF.AUDIT.PIPELINE_RUN_LOG
(
pipeline_name,
target_table,
status,
rows_read,
rows_loaded,
rows_rejected,
started_at,
ended_at,
duration_seconds,
triggered_by
)

SELECT
'TASK_MERGE_SURVEY_STREAM',
'RAW_SURVEY',
'SUCCESS',
COUNT(*),
COUNT(*),
0,
CURRENT_TIMESTAMP(),
CURRENT_TIMESTAMP(),
0,
'task'
FROM STRM_RAW_SURVEY;

------------------------------------------------------------
-- Placeholder dbt Trigger Task
------------------------------------------------------------

CREATE OR REPLACE TASK TASK_TRIGGER_DBT_RUN
    WAREHOUSE = WH_PETRF_TASKS
    AFTER TASK_MERGE_RESPONSE_STREAM,
          TASK_MERGE_SURVEY_STREAM
AS

INSERT INTO ONCLITE_PETRF.AUDIT.PIPELINE_RUN_LOG
(
pipeline_name,
target_table,
status,
started_at,
ended_at,
triggered_by
)

VALUES
(
'TASK_TRIGGER_DBT_RUN',
'DBT',
'SUCCESS',
CURRENT_TIMESTAMP(),
CURRENT_TIMESTAMP(),
'task'
);

------------------------------------------------------------
-- Resume Tasks
------------------------------------------------------------

--ALTER TASK TASK_ROOT_PETRF_INGEST_SCHEDULE RESUME;

--ALTER TASK TASK_MERGE_RESPONSE_STREAM RESUME;

--ALTER TASK TASK_MERGE_SURVEY_STREAM RESUME;

--ALTER TASK TASK_TRIGGER_DBT_RUN RESUME;