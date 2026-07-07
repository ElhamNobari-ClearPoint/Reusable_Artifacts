{% macro scd2_asof_join(fact_alias, fact_key, fact_ts, dim_alias, dim_key, valid_from_column='dbt_valid_from', valid_to_column='dbt_valid_to') %}
{#-
    Point-in-time ("as-of") join condition between a fact table and a Type 2
    dimension: matches the fact row's business key to the dimension row that
    was valid at the fact's event timestamp, not just the current version.
    Returns a boolean ON-clause condition to splice into the caller's own
    `left join ... on {{ ... }}`.

    Args:
        fact_alias (string, required): table alias of the fact side in the join.
        fact_key (string or list, required): fact-side business key column(s).
        fact_ts (string, required): fact-side event timestamp column.
        dim_alias (string, required): table alias of the dimension side in the join.
        dim_key (string or list, required): dimension-side business key column(s).
            Must have the same number of columns as fact_key, in matching order.
        valid_from_column (string, optional): dimension's "valid from" column.
            Defaults to 'dbt_valid_from', the column dbt's native snapshot mechanism creates.
        valid_to_column (string, optional): dimension's "valid to" column.
            Defaults to 'dbt_valid_to', the column dbt's native snapshot mechanism creates.

    Usage:
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
-#}
{%- set fact_keys = fact_key if (fact_key is iterable and fact_key is not string) else [fact_key] -%}
{%- set dim_keys = dim_key if (dim_key is iterable and dim_key is not string) else [dim_key] -%}

{%- if fact_keys | length != dim_keys | length -%}
    {{ exceptions.raise_compiler_error(
        "clearpoint_dbt_utils.scd2_asof_join: fact_key and dim_key must have the same number of columns, got "
        ~ (fact_keys | length) ~ " and " ~ (dim_keys | length) ~ "."
    ) }}
{%- endif -%}

{%- set key_conditions = [] -%}
{%- for i in range(fact_keys | length) -%}
    {%- do key_conditions.append(fact_alias ~ '.' ~ fact_keys[i] ~ ' = ' ~ dim_alias ~ '.' ~ dim_keys[i]) -%}
{%- endfor -%}

{{ key_conditions | join(' and ') }}
    and {{ fact_alias }}.{{ fact_ts }} >= {{ dim_alias }}.{{ valid_from_column }}
    and ({{ fact_alias }}.{{ fact_ts }} < {{ dim_alias }}.{{ valid_to_column }} or {{ dim_alias }}.{{ valid_to_column }} is null)
{% endmacro %}
