{% macro scd2_current_flag(valid_to_column='dbt_valid_to') %}
{#-
    Standard "is this the current version of this record" boolean column,
    returned as a comma-prefixed column list so it can be appended directly
    after a model's other columns in a final select over an SCD Type 2
    snapshot table.

    Centralizes the current-record convention (valid_to IS NULL) in one place
    rather than each downstream model re-deriving it (and risking inconsistent
    null-handling across models).

    Args:
        valid_to_column (string, optional): name of the "valid to" column on
            the snapshot relation being queried. Defaults to 'dbt_valid_to',
            the column dbt's native snapshot mechanism creates.

    Usage:
        select
            customer_id,
            name,
            dbt_valid_from,
            dbt_valid_to
            {{ clearpoint_dbt_utils.scd2_current_flag() }}
        from {{ ref('dim_customer_snapshot') }}
-#}
    , case when {{ valid_to_column }} is null then true else false end as _is_current
{% endmacro %}
