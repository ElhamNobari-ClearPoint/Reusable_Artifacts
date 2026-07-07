{% test fact_join_fanout_check(model, source_relation, fact_key) %}
{#-
    Generic dbt test for fact tables built with generate_fact() (or any
    hand-written fact model): asserts that resolving dimension_lookups did
    not silently duplicate or drop rows. Compares, per fact_key value, the
    row count in source_relation (before any dimension joins) against the
    row count in model (after them). A mismatch means a dimension had more
    than one matching row for some fact_key/timestamp (a "fanout" -- e.g. a
    data quality issue upstream, overlapping SCD2 validity windows, or a
    misconfigured join) or, less commonly, that rows were unexpectedly
    dropped (e.g. an inner join used where a left join was intended).

    Args:
        source_relation (Relation, required): the fact source before any
            dimension joins, e.g. ref('stg_orders').
        fact_key (string or list, required): natural/business key column(s)
            of the fact source. Must be unique in source_relation for this
            test to be meaningful -- it compares counts per key, not overall.

    Usage:
        models:
          - name: fct_orders
            tests:
              - clearpoint_dbt_utils.fact_join_fanout_check:
                  arguments:
                    source_relation: ref('stg_orders')
                    fact_key: order_id
-#}
{%- set fact_keys = fact_key if (fact_key is iterable and fact_key is not string) else [fact_key] -%}
{%- set key_cols = fact_keys | join(', ') -%}

with source_counts as (
    select {{ key_cols }}, count(*) as source_row_count
    from {{ source_relation }}
    group by {{ key_cols }}
),
output_counts as (
    select {{ key_cols }}, count(*) as output_row_count
    from {{ model }}
    group by {{ key_cols }}
)
select
    {{ key_cols }},
    coalesce(source_counts.source_row_count, 0) as source_row_count,
    coalesce(output_counts.output_row_count, 0) as output_row_count
from source_counts
full outer join output_counts using ({{ key_cols }})
where coalesce(source_counts.source_row_count, 0) != coalesce(output_counts.output_row_count, 0)
{% endtest %}
