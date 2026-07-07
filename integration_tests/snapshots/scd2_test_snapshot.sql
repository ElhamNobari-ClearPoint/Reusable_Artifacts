{% snapshot scd2_test_snapshot %}
{{ config(
    unique_key='customer_id',
    strategy='check',
    check_cols=['name', 'email', 'status'],
    invalidate_hard_deletes=true
) }}
select * from {{ ref('scd2_source_seed') }}
{% endsnapshot %}
