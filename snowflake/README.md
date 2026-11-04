# snowflake/

Hand-authored Snowflake DDL that provisions the account-level and database-level
objects dbt and Python depend on. This layer is **not** managed by dbt because
it includes account objects (warehouses, roles, users, resource monitors) that
sit outside dbt's scope.

## Purpose
Stand up every non-dbt-managed Snowflake object required by OncLite-PETRF:
compute, security, the bronze landing zone, CDC streams/tasks, Snowpipes, and
governance policies.

## Inputs
None — these are idempotent DDL scripts intended to run against a fresh (or
existing) Snowflake account.

## Outputs
- `ONCLITE_PETRF` database with `RAW`, `STAGING`, `INTERMEDIATE`, `MARTS`,
  `AUDIT`, `ERROR_HANDLING`, and `SECURITY_ADMIN` schemas
- 4 warehouses (loading, transform, BI, tasks), 5 functional roles, 2 service users
- Bronze tables, gold dimension/fact/bridge tables, audit + error tables
- Streams, Tasks, Pipes, views, masking/row-access policies

## Dependencies
- Executed in numeric order (001 → 011); each file assumes the prior ran successfully.
- `sql/procedures.sql` depends on tables from `006_tables.sql` and the AUDIT
  schema from `003_schema.sql`.
- RSA public keys referenced in `001_environment.sql` are injected by the
  CI/CD pipeline (`.github/workflows/deploy-snowflake.yml`) from GitHub Secrets
  — never commit real key material.

## Run order

```bash
snowsql -c petrf_admin -f 001_environment.sql
snowsql -c petrf_admin -f 002_database.sql
snowsql -c petrf_admin -f 003_schema.sql
snowsql -c petrf_admin -f 004_file_formats.sql
snowsql -c petrf_admin -f 005_stages.sql
snowsql -c petrf_admin -f 006_tables.sql
snowsql -c petrf_admin -f 007_streams.sql
snowsql -c petrf_admin -f 008_tasks.sql
snowsql -c petrf_admin -f 009_pipes.sql
snowsql -c petrf_admin -f 010_views.sql
snowsql -c petrf_admin -f 011_security.sql
snowsql -c petrf_admin -f sql/procedures.sql
```

In CI/CD this is orchestrated by `.github/workflows/deploy-snowflake.yml`,
which runs schema-change validation on PRs and applies on merge to `main`.

## Best practices applied
- Every object is `CREATE ... IF NOT EXISTS` — scripts are safely re-runnable.
- Least-privilege grants: loaders can't read marts, analysts can't write raw.
- Resource monitors prevent runaway credit spend.
- Bronze tables retain `_file_name` / `_row_number` / `_loaded_at` for full lineage.
- SCD Type-2 pattern (`is_current`, `dbt_valid_from/to`) on `DIM_PRODUCT` for
  point-in-time correct historical reporting.
