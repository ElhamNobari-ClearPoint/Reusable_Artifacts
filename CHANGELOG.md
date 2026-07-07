# Changelog

## Unreleased

## 0.1.0 - 2026-07-07

Initial release. Package scaffold plus a first working macro in each of the four planned capability areas, all verified end-to-end against Snowflake via `integration_tests/`.

### Added

- **Audit columns**: `audit_columns()` — standard `_loaded_at`, `_dbt_invocation_id`, `_load_source` metadata columns appended to a model's select.
- **SCD Type 2**: a documented native-`snapshot` config pattern (see README — not a macro, since dbt snapshots cannot call macros from installed packages) plus `scd2_current_flag()`, deriving an `_is_current` boolean from `dbt_valid_to` in downstream models.
- **Bronze → Silver ODS staging**: `dedupe_latest_record()` — a Snowflake `QUALIFY`-based macro collapsing raw/CDC Bronze rows to one current row per business key.
- **Star schema**: `surrogate_key()` — standardized dimension surrogate key generation wrapping `dbt_utils.generate_surrogate_key()` with a `_key`-suffix naming convention; `scd2_asof_join()` — point-in-time join condition resolving a fact row to the SCD2 dimension version valid at its event timestamp.
