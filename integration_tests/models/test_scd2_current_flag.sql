select
    customer_id,
    name,
    email,
    status,
    dbt_valid_from,
    dbt_valid_to
    {{ clearpoint_dbt_utils.scd2_current_flag() }}
from {{ ref('scd2_test_snapshot') }}
