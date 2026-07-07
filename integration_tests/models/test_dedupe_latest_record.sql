select
    customer_id,
    name,
    email,
    _loaded_at
from {{ ref('bronze_raw_customers_seed') }}
{{ clearpoint_dbt_utils.dedupe_latest_record(
    partition_by='customer_id',
    order_by='_loaded_at'
) }}
