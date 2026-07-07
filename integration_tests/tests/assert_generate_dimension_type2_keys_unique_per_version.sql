-- Fails if Bob's two historical versions (customer_id=2) collapse to the
-- same surrogate key -- proving the composite business_key
-- (customer_id + dbt_valid_from) makes the key unique per historical row,
-- not just per customer.
select customer_id, count(distinct customer_key) as distinct_key_count
from {{ ref('test_generate_dimension_type2') }}
where customer_id = 2
group by customer_id
having count(distinct customer_key) != 2
