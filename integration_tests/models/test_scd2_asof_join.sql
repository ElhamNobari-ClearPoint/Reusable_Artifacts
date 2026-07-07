select
    f.order_id,
    f.customer_id,
    f.order_date,
    d.customer_key,
    d.status as customer_status_at_order_time
from {{ ref('fact_orders_asof_seed') }} f
left join {{ ref('dim_customer_asof_seed') }} d
    on {{ clearpoint_dbt_utils.scd2_asof_join(
        fact_alias='f', fact_key='customer_id', fact_ts='order_date',
        dim_alias='d', dim_key='customer_id'
    ) }}
