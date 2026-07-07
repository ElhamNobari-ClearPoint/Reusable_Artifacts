{{ clearpoint_dbt_utils.generate_dimension(
    source_relation=ref('test_dedupe_latest_record'),
    business_key='customer_id',
    surrogate_key_alias='customer_key',
    attribute_columns=['name', 'email']
) }}
