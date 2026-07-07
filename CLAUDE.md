# clearpoint_dbt_utils — conventions

Reusable dbt macro package for ClearPoint client engagements. Target: dbt Core on Snowflake only.

## Package shape

- Macro-only package (like `dbt_utils`/`codegen`) — no models are shipped to consumers. Every capability is a macro that generates SQL/DDL or is called from a consuming project's own models.
- `dbt_project.yml` `name:` is `clearpoint_dbt_utils`. The repo folder name (`clearpoint-dbt-package`) intentionally does not match — the package name is what consumers reference in `packages.yml` and in macro calls (`{{ clearpoint_dbt_utils.macro_name() }}`).
- Depends on `dbt-labs/dbt_utils` (`>=1.1.0,<2.0.0`, pinned in `packages.yml`). Reuse dbt_utils macros (e.g. `generate_surrogate_key`) inside SCD2/star-schema macros rather than reimplementing hashing/key logic.
- No `adapter.dispatch()` pattern — Snowflake is the only supported adapter, so macros are written as plain single-implementation macros, not dispatched by adapter type. Don't add multi-adapter dispatch speculatively.

## Folder structure

```
package/               — the actual installable dbt package (this is the `local:`/`subdirectory:` target)
  dbt_project.yml
  packages.yml
  macros/
    audit/        — standard audit/metadata columns
    scd/          — SCD Type 2: downstream-consumption macros only, NOT snapshot-config macros (see below)
    staging/      — Bronze -> Silver ODS staging patterns (e.g. dedupe_latest_record, Snowflake QUALIFY-based)
    star_schema/  — dimension/fact table generators: surrogate_key (wraps dbt_utils.generate_surrogate_key with a '_key'-suffix naming rule), scd2_asof_join (fact-to-SCD2-dimension point-in-time join condition), generate_dimension and generate_fact (full-statement generators composing the other star_schema/audit macros)
    utils/        — shared helpers used by the above
integration_tests/     — sibling dev project, installs the package via `local: ../package`
  dbt_project.yml      — profile: integration_tests
  packages.yml
  seeds/ models/ macros/
```

`package/` and `integration_tests/` are **siblings**, not nested (unlike the usual dbt-labs convention of `integration_tests/` living inside the package root). This is deliberate, not an oversight — see "Windows local-package symlink recursion" below before ever moving `integration_tests/` back inside `package/`.

Each macro file `package/macros/<area>/<macro_name>.sql` has a sibling `package/macros/<area>/<macro_name>.yml` documenting its description and arguments (dbt macro properties schema).

## Naming conventions

- Macro files and macro names: `snake_case`, one primary macro per file, file name matches macro name (`audit_columns.sql` → `{% macro audit_columns(...) %}`).
- Metadata/audit columns use a **leading underscore**, `snake_case` style: `_loaded_at`, `_dbt_invocation_id`, `_load_source`. This visually separates pipeline metadata from business columns. Don't switch to a `dbt_`-prefix style — underscore-prefix was chosen deliberately over that alternative.
- Macros that emit column lists for splicing into a `select` (e.g. `audit_columns()`) return a **leading-comma** list (`, col_a\n, col_b`), not a trailing-comma list — this lets callers append the macro output straight after their own column list without comma bookkeeping.
- Most macros return composable snippets (column lists, ON-clause conditions, QUALIFY clauses), not full statements — this is deliberate, confirmed with the user, and should stay the default. `generate_dimension()` and `generate_fact()` are the intentional exceptions (full-statement generators, by explicit user choice) — don't casually convert other macros to this shape without the same kind of confirmation.
- `generate_fact()`'s `dimension_lookups` argument is a list of plain dicts (not a Jinja/dbt object) — keys are accessed with `lookup['key']` and `lookup.get('key', default)` inside the macro. This works because dbt's Jinja environment allows normal Python dict method calls; don't assume this generalizes to arbitrary objects passed through `ref()`/`source()`, which are `Relation` objects, not dicts.
- **Type-2 dimension gotcha**: when calling `generate_dimension()` (or `surrogate_key()` directly) against an SCD2 snapshot, `business_key` must be a composite of the natural key plus a version discriminator (e.g. `['customer_id', 'dbt_valid_from']`), never just the natural key alone. `surrogate_key()` hashes exactly what it's given — a natural-key-only surrogate key collapses every historical version of the same entity to one identical key, silently breaking row-level uniqueness. Verified with an integration test (`assert_generate_dimension_type2_keys_unique_per_version.sql`) — don't regress this.

## Medallion terminology used in this package

- **Bronze**: raw, as-landed source data, no conforming.
- **Silver / ODS**: conformed, deduplicated staging layer — the `staging/` macros target this Bronze → Silver transition.
- **Gold**: dimensional star schema (facts/dimensions) built by the `star_schema/` macros, for direct consumption (BI, reporting).
- Audit columns and SCD2 are cross-cutting: audit columns apply at every layer; SCD2 typically governs Silver/Gold dimension history.

## Snowflake / environment assumptions

- Local dev reuses the Snowflake connection already configured in `~/.dbt/profiles.yml` for the health-ingest project: account `VWNWQDW-QF08134`, user `HEALTH_INGEST_USER`, key-pair auth (`private_key_path`), role `HEALTH_PIPELINE_ROLE`, warehouse `COMPUTE_WH`.
- The `integration_tests` profile reuses that same account/user/key/role/warehouse (no new Snowflake grants needed) but points at database `APAC_HEALTH`, schema `DBT_UTILS_SANDBOX` — a schema deliberately separate from the real `BRONZE` schema so package-test artifacts never mix with real health-pipeline data. Don't point integration tests at `BRONZE` or any real client schema.
- This is a dev-machine convenience, not a CI setup — if/when this package gets a CI pipeline, it should get its own dedicated Snowflake role/warehouse/database rather than continuing to borrow the health-ingest credentials.
- Local Python environment: **must use Python 3.11** (a `.venv` in the repo root, gitignored). Python 3.13/3.14 are NOT compatible with the current dbt-core dependency chain (`mashumaro` fails: `UnserializableField` on `Optional[str]`). If the venv needs recreating, build it with the 3.11 interpreter, not whatever `python`/`py` defaults to.
- Installed in `.venv`: `dbt-core` 1.11.x, `dbt-snowflake` 1.11.x. `require-dbt-version` in both `dbt_project.yml` files is pinned to `>=1.7.0,<2.0.0`.

## Workflow

- Run macros through `integration_tests/` to validate against real Snowflake-compiled SQL as they're built — don't consider a macro done until it's been run there, not just written.
- From `integration_tests/`: `../.venv/Scripts/dbt.exe deps` then `../.venv/Scripts/dbt.exe build`.
- **Rerun `dbt deps` after every edit to `package/macros/`.** The local package install (`local: ../package`) is a snapshot copy taken at `deps` time, not a live view — `dbt build`/`dbt run`/`dbt parse` do not refresh it. Editing a macro and rebuilding without rerunning `deps` first silently runs against the stale copy (surfaces as `'dict object' has no attribute '<macro_name>'` for a macro you just added, or old behavior for one you just changed).
- Structural/dependency decisions (new package deps, folder layout changes, profile/credential setup) should be confirmed with the user before making them — this package is built incrementally, one macro at a time, by agreement.

## Windows local-package symlink recursion (do not reintroduce)

`dbt deps` installs a `local:` package by trying `os.symlink()` first, and falling back to a plain recursive `shutil.copytree` if that raises `OSError` (which it does on Windows without Developer Mode/admin rights — confirmed OFF on this dev machine). That copytree has no cycle guard.

Early in this repo's history, `integration_tests/` was nested inside the package root and its `packages.yml` used `local: ../` — pointing straight at the tree containing itself. `dbt deps` hung for 40+ minutes copying `dbt_packages/clearpoint_dbt_utils/integration_tests/dbt_packages/clearpoint_dbt_utils/...` recursively, duplicating the multi-hundred-MB `.venv` at every level, before it was killed manually. The fix was splitting `package/` and `integration_tests/` into siblings so `local: ../package` can never resolve to a directory containing `integration_tests/` itself.

If you ever restructure this repo, keep that invariant: whatever `integration_tests/packages.yml`'s `local:` path resolves to must never contain `integration_tests/` as a descendant. Enabling Developer Mode on a given machine works around it too (real symlinks have no copy cost), but don't rely on that — assume future contributors' machines won't have it on.

## Macro `.yml` doc descriptions are Jinja-rendered — never put literal `{{ }}` in them

dbt renders `description:` fields in macro/model properties `.yml` files as Jinja templates (so `{{ doc(...) }}` blocks work). If a description contains a literal usage example like `` `left join ... on {{ ... }}` ``, dbt tries to parse `{{ ... }}` as a real Jinja expression and fails with a cryptic `Compilation Error: unexpected '.'`. Hit this writing `scd2_asof_join.yml`. Usage examples with real macro-call syntax belong in the `.sql` file's `{#- ... -#}` comment block (never rendered) or in `README.md` (plain markdown, not Jinja-rendered) — never in a `.yml` `description:` field.

## dbt snapshots cannot call macros from installed packages (do not reattempt)

Verified against dbt-core 1.11.12: a `{% snapshot %}...{% endsnapshot %}` block's Jinja context does not expose any installed package's macro namespace — only the root project's own macros are resolvable there. This is not specific to `config()`, to `**kwargs` unpacking, or to how a macro is written; a macro doing nothing but `{{ return("x") }}`, called from this package, fails inside a snapshot block with `'dict object' has no attribute '<macro_name>'`. The identical call works fine inside a regular **model** (that's how `audit_columns()` and `scd2_current_flag()` work).

Consequence: this package cannot ship a `scd2_snapshot_config()`-style macro that a consumer calls directly inside their own `{% snapshot %}` block — an earlier version of this package attempted exactly that (see git history) and it is not fixable by changing the macro's implementation. The SCD Type 2 feature is split accordingly:
- **Snapshot config**: not a macro. It's a documented literal pattern in `README.md` ("SCD Type 2" section) that consumers copy into their own `{% snapshot %}` block, with the config values (`unique_key`, `strategy`, `check_cols`, `invalidate_hard_deletes`) written directly, not proxied through any macro call.
- **Downstream consumption**: real macros in `package/macros/scd/` (e.g. `scd2_current_flag()`), used in ordinary models that query an already-built snapshot relation via `ref()`. Models don't have this restriction — cross-package macros work normally there.

If a future SCD2 macro idea only makes sense called from inside a `{% snapshot %}` block, it isn't viable as a package macro — redirect it into the README's documented pattern instead, the same way `scd2_snapshot_config()` was replaced.
