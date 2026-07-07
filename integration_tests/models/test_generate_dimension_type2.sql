{{ clearpoint_dbt_utils.generate_dimension(
    source_relation=ref('scd2_test_snapshot'),
    business_key=['customer_id', 'dbt_valid_from'],
    surrogate_key_alias='customer_key',
    attribute_columns=['name', 'email', 'status', 'dbt_valid_to'],
    include_current_flag=true
) }}
