-- Fails if any customer's deduped row is not the one with the latest _loaded_at
-- from the raw seed (bronze_raw_customers_seed.csv).
select *
from {{ ref('test_dedupe_latest_record') }}
where (customer_id = 1 and email != 'alice_new@example.com')
   or (customer_id = 2 and email != 'bob_updated@example.com')
   or (customer_id = 3 and email != 'carol@example.com')
