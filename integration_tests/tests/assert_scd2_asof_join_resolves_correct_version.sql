-- Fails if any order does not resolve to the exact expected dimension version
-- (or NULL, for order 104 which falls in the gap after customer 3's only
-- dimension version closed with no later replacement).
select *
from {{ ref('test_scd2_asof_join') }}
where (order_id = 101 and customer_key != 'cust_1_v1')
   or (order_id = 102 and customer_key != 'cust_2_v1')
   or (order_id = 103 and customer_key != 'cust_2_v2')
   or (order_id = 104 and customer_key is not null)
   or (order_id = 105 and customer_key != 'cust_3_v1')
