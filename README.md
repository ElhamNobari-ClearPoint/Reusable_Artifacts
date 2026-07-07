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

`generate_dimension()` is a full statement generator — unlike the snippet-style macros above, it composes `surrogate_key()`, `audit_columns()`, and (optionally) `scd2_current_flag()` into a complete `select`, so a simple dimension model's entire `.sql` file can be one macro call:

```sql
-- models/dim_customer.sql
{{ clearpoint_dbt_utils.generate_dimension(
    source_relation=ref('stg_customers'),
    business_key='customer_id',
    surrogate_key_alias='customer_key',
    attribute_columns=['name', 'email', 'status']
) }}
```

For a **Type-2** dimension (`source_relation` is an SCD2 snapshot), pass `include_current_flag=true` to append `_is_current`, and — importantly — make `business_key` a composite of the natural key plus a version discriminator (e.g. `['customer_id', 'dbt_valid_from']`), not just the natural key alone. Otherwise every historical version of the same customer collapses to the *same* surrogate key, since `surrogate_key()` hashes exactly what it's given:

```sql
{{ clearpoint_dbt_utils.generate_dimension(
    source_relation=ref('dim_customer_snapshot'),
    business_key=['customer_id', 'dbt_valid_from'],
    surrogate_key_alias='customer_key',
    attribute_columns=['name', 'email', 'status', 'dbt_valid_to'],
    include_current_flag=true
) }}
```

`generate_fact()` is the fact-table counterpart: measures plus one or more resolved dimension surrogate keys, each lookup either a plain equality join or a point-in-time join via `scd2_asof_join()`:

```sql
-- models/fct_orders.sql
{{ clearpoint_dbt_utils.generate_fact(
    source_relation=ref('stg_orders'),
    fact_key='order_id',
    measure_columns=['order_amount', 'order_date'],
    dimension_lookups=[
        {
            'relation': ref('dim_customer_snapshot'), 'alias': 'dim_customer',
            'fact_key': 'customer_id', 'dim_key': 'customer_id',
            'surrogate_key_column': 'customer_key',
            'asof': true, 'fact_ts': 'order_date'
        },
        {
            'relation': ref('dim_product'), 'alias': 'dim_product',
            'fact_key': 'product_id', 'dim_key': 'product_id',
            'surrogate_key_column': 'product_key'
        }
    ]
) }}
```

Each `dimension_lookups` entry needs `relation`, a unique `alias`, `fact_key`/`dim_key` (join columns — string or list), and `surrogate_key_column` (the column to pull from the dimension). Add `asof: true` and `fact_ts` for a point-in-time lookup against an SCD2 dimension; omit them for a plain equality join against a Type-1 dimension. `generate_fact()` does not generate a surrogate key for the fact row itself — `fact_key` is selected as-is.

`one_current_record_per_key` is a generic dbt test for Type-2 dimensions, asserting no business key has more than one current (`_is_current = true`) row:

```yaml
# schema.yml
models:
  - name: dim_customer
    tests:
      - clearpoint_dbt_utils.one_current_record_per_key:
          arguments:
            business_key: customer_id
```

It deliberately does **not** flag a business key with *zero* current records as a failure — a hard-deleted key (via `invalidate_hard_deletes=true`, this package's recommended SCD2 pattern) legitimately has zero current rows, and that's correct, not a bug. `business_key` accepts a single column or a list; `current_flag_column` defaults to `_is_current` (what `scd2_current_flag()` produces) but can be overridden.

`fact_join_fanout_check` is a generic dbt test for fact tables: it catches a "fanout" bug that `unique`/`not_null`/`relationships` don't — a dimension lookup silently duplicating (or dropping) fact rows because a dimension had more than one matching row for some fact_key/timestamp (e.g. overlapping SCD2 validity windows, or a data quality issue upstream):

```yaml
# schema.yml
models:
  - name: fct_orders
    tests:
      - clearpoint_dbt_utils.fact_join_fanout_check:
          arguments:
            source_relation: ref('stg_orders')
            fact_key: order_id
```

It compares, per `fact_key` value, the row count in `source_relation` (before any dimension joins) against the row count in the fact model itself (after them) — any mismatch fails. `fact_key` must be unique in `source_relation` for the comparison to be meaningful.

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
