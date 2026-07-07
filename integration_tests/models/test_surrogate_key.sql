select
    {{ clearpoint_dbt_utils.surrogate_key('customer_key', ['customer_id']) }},
    customer_id,
    name,
    email
from {{ ref('test_dedupe_latest_record') }}
