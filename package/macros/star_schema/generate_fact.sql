{% macro generate_fact(source_relation, fact_key, measure_columns, dimension_lookups, fact_alias='f', load_source=none) %}
{#-
    Generates a full SELECT statement for a star schema fact table: measures
    plus one or more resolved dimension surrogate keys, composing this
    package's scd2_asof_join() (for point-in-time dimension lookups) and
    audit_columns() so a fact model's entire .sql file can be a single call
    to this macro.

    Args:
        source_relation (Relation, required): the fact source to select from,
            e.g. ref('stg_orders').
        fact_key (string or list, required): natural/business key column(s)
            of the fact source. Selected as-is; this macro does not generate
            a surrogate key for the fact row itself.
        measure_columns (list, required): measure/descriptive column(s) to
            select as-is. Pass an empty list if there are none.
        dimension_lookups (list of dicts, required): one entry per dimension
            to resolve a surrogate key from. Each entry:
                relation (Relation, required): the dimension relation to join.
                alias (string, required): unique join alias for this dimension.
                fact_key (string or list, required): fact-side join key column(s).
                dim_key (string or list, required): dimension-side join key column(s).
                surrogate_key_column (string, required): the dimension's
                    surrogate key column to select into the fact output.
                asof (boolean, optional): defaults to false (plain equality
                    join). Set true for a point-in-time join against an SCD2
                    dimension via scd2_asof_join().
                fact_ts (string, required if asof=true): fact-side event
                    timestamp column for the point-in-time join.
        fact_alias (string, optional): table alias for source_relation in the
            generated SQL. Defaults to 'f'.
        load_source (string, optional): passed through to audit_columns();
            defaults to the current model's identifier when not supplied.

    Usage (this is the entire content of models/fct_orders.sql):
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
-#}
{%- set fact_keys = fact_key if (fact_key is iterable and fact_key is not string) else [fact_key] -%}

{%- set select_exprs = [] -%}
{%- for col in fact_keys -%}
    {%- do select_exprs.append(fact_alias ~ '.' ~ col) -%}
{%- endfor -%}
{%- for col in measure_columns -%}
    {%- do select_exprs.append(fact_alias ~ '.' ~ col) -%}
{%- endfor -%}
{%- for lookup in dimension_lookups -%}
    {%- do select_exprs.append(lookup['alias'] ~ '.' ~ lookup['surrogate_key_column']) -%}
{%- endfor -%}

{%- set join_clauses = [] -%}
{%- for lookup in dimension_lookups -%}
    {%- if lookup.get('asof', false) -%}
        {%- set condition = clearpoint_dbt_utils.scd2_asof_join(
            fact_alias=fact_alias,
            fact_key=lookup['fact_key'],
            fact_ts=lookup['fact_ts'],
            dim_alias=lookup['alias'],
            dim_key=lookup['dim_key']
        ) -%}
    {%- else -%}
        {%- set dim_fact_keys = lookup['fact_key'] if (lookup['fact_key'] is iterable and lookup['fact_key'] is not string) else [lookup['fact_key']] -%}
        {%- set dim_dim_keys = lookup['dim_key'] if (lookup['dim_key'] is iterable and lookup['dim_key'] is not string) else [lookup['dim_key']] -%}
        {%- set conds = [] -%}
        {%- for i in range(dim_fact_keys | length) -%}
            {%- do conds.append(fact_alias ~ '.' ~ dim_fact_keys[i] ~ ' = ' ~ lookup['alias'] ~ '.' ~ dim_dim_keys[i]) -%}
        {%- endfor -%}
        {%- set condition = conds | join(' and ') -%}
    {%- endif -%}
    {%- do join_clauses.append('left join ' ~ lookup['relation'] ~ ' as ' ~ lookup['alias'] ~ ' on ' ~ condition) -%}
{%- endfor -%}

select
    {{ select_exprs | join(',\n    ') }}
    {{ clearpoint_dbt_utils.audit_columns(load_source) }}
from {{ source_relation }} as {{ fact_alias }}
{% for join_clause in join_clauses %}
{{ join_clause }}
{% endfor %}
{% endmacro %}
