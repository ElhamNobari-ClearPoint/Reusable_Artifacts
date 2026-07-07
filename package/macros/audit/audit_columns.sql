{% macro audit_columns(load_source=none) %}
{#-
    Standard audit columns, returned as a comma-prefixed column list so they can
    be appended directly after a model's business columns in a final select.

    Args:
        load_source (string, optional): value for the _load_source column.
            Defaults to the current model's identifier (this.identifier).

    Usage:
        select
            id,
            name
            {{ clearpoint_dbt_utils.audit_columns() }}
        from ...
-#}
    {%- set load_source = load_source if load_source is not none else this.identifier -%}
    , current_timestamp()   as _loaded_at
    , '{{ invocation_id }}' as _dbt_invocation_id
    , '{{ load_source }}'   as _load_source
{% endmacro %}
