select
    1 as id,
    'foo' as name
    {{ clearpoint_dbt_utils.audit_columns() }}
