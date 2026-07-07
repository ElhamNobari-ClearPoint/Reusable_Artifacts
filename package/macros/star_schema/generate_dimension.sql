{% macro generate_dimension(source_relation, business_key, surrogate_key_alias, attribute_columns, include_current_flag=false, load_source=none) %}
{#-
    Generates a full SELECT statement for a star schema dimension table,
    composing this package's surrogate_key(), audit_columns(), and
    (optionally) scd2_current_flag() macros so a simple dimension model's
    entire .sql file can be a single call to this macro.

    Args:
        source_relation (Relation, required): the relation to select from,
            e.g. ref('stg_customers') or ref('dim_customer_snapshot').
        business_key (string or list, required): natural/business key column(s).
        surrogate_key_alias (string, required): name for the surrogate key
            column. Must end with '_key' (enforced by surrogate_key()).
        attribute_columns (list, required): descriptive attribute column(s)
            to select as-is. Pass an empty list if there are none.
        include_current_flag (boolean, optional): defaults to false. Set true
            when source_relation is an SCD2 snapshot, to append scd2_current_flag().
        load_source (string, optional): passed through to audit_columns();
            defaults to the current model's identifier when not supplied.

    Usage (this is the entire content of models/dim_customer.sql):
        {{ clearpoint_dbt_utils.generate_dimension(
            source_relation=ref('stg_customers'),
            business_key='customer_id',
            surrogate_key_alias='customer_key',
            attribute_columns=['name', 'email', 'status']
        ) }}
-#}
{%- set business_keys = business_key if (business_key is iterable and business_key is not string) else [business_key] -%}

{%- set select_exprs = [clearpoint_dbt_utils.surrogate_key(surrogate_key_alias, business_keys)] -%}
{%- for col in business_keys -%}
    {%- do select_exprs.append(col) -%}
{%- endfor -%}
{%- for col in attribute_columns -%}
    {%- do select_exprs.append(col) -%}
{%- endfor -%}

select
    {{ select_exprs | join(',\n    ') }}
    {{ clearpoint_dbt_utils.audit_columns(load_source) }}
    {%- if include_current_flag %}
    {{ clearpoint_dbt_utils.scd2_current_flag() }}
    {%- endif %}
from {{ source_relation }}
{% endmacro %}
