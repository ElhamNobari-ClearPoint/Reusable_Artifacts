{{ clearpoint_dbt_utils.generate_fact(
    source_relation=ref('fact_orders_full_seed'),
    fact_key='order_id',
    measure_columns=['order_amount', 'order_date'],
    dimension_lookups=[
        {
            'relation': ref('dim_customer_asof_seed'), 'alias': 'dim_customer',
            'fact_key': 'customer_id', 'dim_key': 'customer_id',
            'surrogate_key_column': 'customer_key',
            'asof': true, 'fact_ts': 'order_date'
        },
        {
            'relation': ref('dim_product_seed'), 'alias': 'dim_product',
            'fact_key': 'product_id', 'dim_key': 'product_id',
            'surrogate_key_column': 'product_key'
        }
    ]
) }}
