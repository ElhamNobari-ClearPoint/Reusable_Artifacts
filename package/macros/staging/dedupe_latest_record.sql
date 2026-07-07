{% macro dedupe_latest_record(partition_by, order_by, order_direction='desc') %}
{#-
    Generates a QUALIFY ROW_NUMBER() clause to collapse raw Bronze rows down
    to one current row per business key, for use in Bronze -> Silver staging
    models. Snowflake-specific (QUALIFY is not standard ANSI SQL).

    Args:
        partition_by (string or list, required): business key column(s) to dedupe by.
        order_by (string or list, required): recency column(s) determining which row wins.
        order_direction (string, optional): 'asc' or 'desc'. Defaults to 'desc' (latest wins).

    Usage:
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
-#}
{%- if order_direction not in ('asc', 'desc') -%}
    {{ exceptions.raise_compiler_error(
        "clearpoint_dbt_utils.dedupe_latest_record: order_direction must be 'asc' or 'desc', got '" ~ order_direction ~ "'."
    ) }}
{%- endif -%}

{%- set partition_cols = partition_by if (partition_by is iterable and partition_by is not string) else [partition_by] -%}
{%- set order_cols = order_by if (order_by is iterable and order_by is not string) else [order_by] -%}

qualify row_number() over (
    partition by {{ partition_cols | join(', ') }}
    order by {{ order_cols | join(', ') }} {{ order_direction }}
) = 1
{% endmacro %}
