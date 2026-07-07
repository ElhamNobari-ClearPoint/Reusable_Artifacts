# Changelog

## Unreleased

## 0.4.0 - 2026-07-07

A generic dbt test for fact table join integrity, verified end-to-end against Snowflake via `integration_tests/`.

### Added

- **Star schema**: `fact_join_fanout_check` — generic dbt test asserting a fact table's dimension joins did not silently duplicate or drop rows, by comparing per-key row counts between the pre-join fact source and the fact model's output. Complements (rather than duplicates) dbt's built-in `unique`/`not_null`/`relationships` tests, which don't catch join fanout.

## 0.3.0 - 2026-07-07

A generic dbt test for Type-2 dimension quality, verified end-to-end against Snowflake via `integration_tests/`.

### Added

- **SCD Type 2**: `one_current_record_per_key` — generic dbt test asserting no business key has more than one current (`_is_current = true`) row. Deliberately does not flag zero current records, since a hard-deleted key (via `invalidate_hard_deletes=true`, this package's recommended SCD2 pattern) legitimately has zero.

## 0.2.0 - 2026-07-07

Full-statement star schema generators, built on top of the 0.1.0 primitives (`surrogate_key()`, `audit_columns()`, `scd2_current_flag()`, `scd2_asof_join()`), verified end-to-end against Snowflake via `integration_tests/`.

### Added

- **Star schema**: `generate_dimension()` — full dimension SELECT generator composing `surrogate_key()`, `audit_columns()`, and (optionally) `scd2_current_flag()`; supports both Type-1 dimensions and Type-2 (SCD2 snapshot-sourced) dimensions via a composite `business_key` (natural key + version discriminator) for row-level surrogate key uniqueness.
- **Star schema**: `generate_fact()` — full fact SELECT generator resolving one or more dimension surrogate keys per fact row, each lookup either a plain equality join or a point-in-time join via `scd2_asof_join()`, composed with `audit_columns()`.

## 0.1.0 - 2026-07-07

Initial release. Package scaffold plus a first working macro in each of the four planned capability areas, all verified end-to-end against Snowflake via `integration_tests/`.

### Added

- **Audit columns**: `audit_columns()` — standard `_loaded_at`, `_dbt_invocation_id`, `_load_source` metadata columns appended to a model's select.
- **SCD Type 2**: a documented native-`snapshot` config pattern (see README — not a macro, since dbt snapshots cannot call macros from installed packages) plus `scd2_current_flag()`, deriving an `_is_current` boolean from `dbt_valid_to` in downstream models.
- **Bronze → Silver ODS staging**: `dedupe_latest_record()` — a Snowflake `QUALIFY`-based macro collapsing raw/CDC Bronze rows to one current row per business key.
- **Star schema**: `surrogate_key()` — standardized dimension surrogate key generation wrapping `dbt_utils.generate_surrogate_key()` with a `_key`-suffix naming convention; `scd2_asof_join()` — point-in-time join condition resolving a fact row to the SCD2 dimension version valid at its event timestamp.
