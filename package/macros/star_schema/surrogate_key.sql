{% macro surrogate_key(alias, field_list) %}
{#-
    Standardized surrogate key generation for star schema dimension tables.
    Thin wrapper around dbt_utils.generate_surrogate_key() enforcing this
    package's naming convention: surrogate key columns must end in '_key'.

    Args:
        alias (string, required): name for the surrogate key column. Must end in '_key'.
        field_list (list, required): natural/business key column(s) to hash.

    Usage:
        select
            {{ clearpoint_dbt_utils.surrogate_key('customer_key', ['customer_id']) }},
            customer_id,
            name,
            email
        from {{ ref('stg_customers') }}
-#}
{%- if not alias.endswith('_key') -%}
    {{ exceptions.raise_compiler_error(
        "clearpoint_dbt_utils.surrogate_key: alias must end with '_key', got '" ~ alias ~ "'."
    ) }}
{%- endif -%}
{{ dbt_utils.generate_surrogate_key(field_list) }} as {{ alias }}
{% endmacro %}
