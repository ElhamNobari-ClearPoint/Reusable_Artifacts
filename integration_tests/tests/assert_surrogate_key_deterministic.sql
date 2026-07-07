-- Fails if any customer_id produces more than one distinct surrogate key
-- across its raw duplicate rows in bronze_raw_customers_seed -- proving
-- surrogate_key() is a pure/deterministic function of its field_list.
select customer_id, count(distinct customer_key) as distinct_key_count
from (
    select
        customer_id,
        {{ clearpoint_dbt_utils.surrogate_key('customer_key', ['customer_id']) }}
    from {{ ref('bronze_raw_customers_seed') }}
) raw_keys
group by customer_id
having count(distinct customer_key) > 1
