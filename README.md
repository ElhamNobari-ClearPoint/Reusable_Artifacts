# clearpoint_dbt_utils

Reusable dbt macros for ClearPoint data engagements, targeting dbt Core on Snowflake.

## What's included

- **Audit columns** (`package/macros/audit/`) — standard metadata columns applied across Bronze/Silver/Gold models.
- **SCD Type 2** (`package/macros/scd/`) — a standard snapshot pattern (see below) plus macros for querying an already-built SCD2 snapshot from downstream models.
- **Bronze → Silver ODS staging** (`package/macros/staging/`) — generic staging patterns for landing raw source data into a conformed ODS layer.
- **Star schema generators** (`package/macros/star_schema/`) — dimension and fact table generation helpers.

## Repo layout

The installable dbt package lives in `package/` (its own `dbt_project.yml`, `packages.yml`, `macros/`). `integration_tests/` is a sibling project used only for development — it is **not** part of the installable package. They are kept as siblings (rather than `integration_tests/` nested inside `package/`, the usual dbt-labs convention) because `package/`'s local install path must never contain `integration_tests/` itself — see the "Windows symlink note" below.

## Installation

Add to your `packages.yml`, using `subdirectory` since the package is not at the repo root:

```yaml
packages:
  - git: "https://github.com/<org>/clearpoint-dbt-package.git"
    subdirectory: "package"
    revision: <tag-or-branch>
```

## SCD Type 2

This package uses dbt's native `snapshot` mechanism for SCD Type 2, not a custom incremental-model implementation. **dbt snapshots cannot call macros from installed packages at all** (this package included) — the snapshot Jinja context doesn't expose other packages' macro namespaces, only the root project's own macros. So there is no `clearpoint_dbt_utils` macro to call inside your `{% snapshot %}` block; write the `config()` call directly, following this standard pattern:

```sql
{% snapshot dim_customer_snapshot %}
{{ config(
    unique_key='customer_id',
    strategy='check',
    check_cols=['name', 'email', 'status'],
    invalidate_hard_deletes=true
) }}
select * from {{ ref('stg_customers') }}
{% endsnapshot %}
```

Rules of thumb:
- **Never use `check_cols='all'`.** If your source rows also carry this package's `audit_columns()` output (e.g. `_loaded_at`), `'all'` would register a new SCD2 row on every single run, since that column changes every run. Always list the specific business columns to track.
- Default `invalidate_hard_deletes` to `true` so a row deleted at the source gets `dbt_valid_to` closed out, rather than looking perpetually current.
- Once the snapshot exists, downstream models querying it *can* use this package's macros normally (models, unlike snapshots, do have full access to installed packages' macros) — e.g. `clearpoint_dbt_utils.scd2_current_flag()` to derive an `_is_current` boolean from `dbt_valid_to`.

## Bronze → Silver ODS staging

`dedupe_latest_record()` collapses raw Bronze rows (which often carry multiple raw/CDC rows per business key) down to one current row per key, using Snowflake's `QUALIFY` clause:

```sql
select
    customer_id,
    name,
    email,
    _loaded_at
from {{ source('bronze', 'raw_customers') }}
{{ clearpoint_dbt_utils.dedupe_latest_record(
    partition_by='customer_id',
    order_by='_loaded_at'
) }}
```

`partition_by` and `order_by` each accept a single column name or a list of columns. `order_direction` defaults to `'desc'` (the row with the latest `order_by` value wins).

## Star schema

`surrogate_key()` standardizes dimension surrogate key generation: a thin wrapper around `dbt_utils.generate_surrogate_key()` that enforces a naming convention (the alias must end in `_key`), so every dimension in a project generates its key the same way.

```sql
select
    {{ clearpoint_dbt_utils.surrogate_key('customer_key', ['customer_id']) }},
    customer_id,
    name,
    email
from {{ ref('stg_customers') }}
```

Passing an alias that doesn't end in `_key` (e.g. `'customer_id_hash'`) raises a compiler error rather than silently allowing inconsistent naming across models.

`scd2_asof_join()` resolves a fact row to the dimension version that was valid *at the fact's event timestamp* — not just the current version — when joining against a Type 2 (SCD2) dimension. It returns a boolean ON-clause condition, not a full join statement:

```sql
select
    f.order_id,
    f.order_date,
    d.customer_key,
    d.status as customer_status_at_order_time
from {{ ref('stg_orders') }} f
left join {{ ref('dim_customer_snapshot') }} d
    on {{ clearpoint_dbt_utils.scd2_asof_join(
        fact_alias='f', fact_key='customer_id', fact_ts='order_date',
        dim_alias='d', dim_key='customer_id'
    ) }}
```

`fact_key`/`dim_key` each accept a single column name or a list of columns (for composite business keys); `valid_from_column`/`valid_to_column` default to dbt's native snapshot columns (`dbt_valid_from`/`dbt_valid_to`) but can be overridden. If a fact event falls in a gap — after a dimension version closed with no later replacement (e.g. a hard-deleted business key) — the join correctly produces `NULL` rather than falsely matching a stale or wrong version.

## Dependencies

This package depends on [dbt-labs/dbt_utils](https://github.com/dbt-labs/dbt-utils).

## Development

Macros are developed and tested against the `integration_tests/` sub-project:

```bash
cd integration_tests
dbt deps
dbt build
```

### Windows symlink note

`dbt deps` installs `local:` packages via a symlink, falling back to a recursive `shutil.copytree` if `os.symlink()` fails (which it does on Windows without Developer Mode or admin rights). That copytree fallback has no cycle protection — if the local package root ever contains the consuming project's own directory (e.g. `integration_tests/` nested inside `package/`, pointing `local:` back at `package/`), it recurses into itself indefinitely, copying `dbt_packages/` inside itself over and over until disk space runs out. That's why `package/` and `integration_tests/` are siblings, not nested, in this repo. If you enable Developer Mode on your machine, `os.symlink()` will succeed and this stops being a concern — but don't assume that for anyone else cloning this repo.
