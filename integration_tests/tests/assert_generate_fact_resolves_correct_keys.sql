-- Fails if any order does not resolve to the exact expected customer_key
-- (point-in-time, via scd2_asof_join) and product_key (plain equality join).
-- Order 104 falls in a gap after customer 3's only dimension version closed
-- with no replacement, so customer_key must be NULL there.
select *
from {{ ref('test_generate_fact') }}
where (order_id = 101 and (customer_key != 'cust_1_v1' or product_key != 'prod_1_key'))
   or (order_id = 102 and (customer_key != 'cust_2_v1' or product_key != 'prod_1_key'))
   or (order_id = 103 and (customer_key != 'cust_2_v2' or product_key != 'prod_2_key'))
   or (order_id = 104 and (customer_key is not null or product_key != 'prod_2_key'))
   or (order_id = 105 and (customer_key != 'cust_3_v1' or product_key != 'prod_1_key'))
