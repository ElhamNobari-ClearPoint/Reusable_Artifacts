{% test no_overlapping_scd2_periods(model, business_key, valid_from_column='dbt_valid_from', valid_to_column='dbt_valid_to') %}
{#-
    Generic dbt test for Type-2 (SCD2) dimensions: asserts no two historical
    versions of the same business key have overlapping validity windows.
    Catches bad SCD2 history data (e.g. a hand-rolled backfill, a duplicate
    snapshot run, or a source system correction that wasn't applied
    correctly) at the dimension itself -- before it can cause a fanout in a
    downstream fact join (see fact_join_fanout_check, which catches the
    same class of bug reactively, from the fact side).

    Windows are treated as [valid_from, valid_to) -- valid_to is an
    exclusive upper bound, matching this package's scd2_asof_join()
    convention. A null valid_to means "still open" (current).

    Known limitation: this compares each row only to the immediately
    preceding row (by valid_from) for the same business key. It assumes
    rows are otherwise well-formed (e.g. an open/current row is the
    chronologically last row for its key) -- it will not catch every
    conceivable malformed ordering, only genuine overlapping windows.

    Args:
        business_key (string or list, required): natural/business key column(s).
        valid_from_column (string, optional): defaults to 'dbt_valid_from'.
        valid_to_column (string, optional): defaults to 'dbt_valid_to'.

    Usage:
        models:
          - name: dim_customer_snapshot
            tests:
              - clearpoint_dbt_utils.no_overlapping_scd2_periods:
                  arguments:
                    business_key: customer_id
-#}
{%- set business_keys = business_key if (business_key is iterable and business_key is not string) else [business_key] -%}
{%- set key_cols = business_keys | join(', ') -%}

with ordered as (
    select
        {{ key_cols }},
        {{ valid_from_column }} as valid_from,
        {{ valid_to_column }} as valid_to,
        lag({{ valid_to_column }}) over (
            partition by {{ key_cols }}
            order by {{ valid_from_column }}
        ) as prev_valid_to
    from {{ model }}
)
select *
from ordered
where prev_valid_to is not null
  and valid_from < prev_valid_to
{% endtest %}
