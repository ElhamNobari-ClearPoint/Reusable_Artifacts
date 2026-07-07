{% test surrogate_key_is_deterministic(model, business_key, surrogate_key_column) %}
{#-
    Generic dbt test for dimension tables: asserts each distinct business_key
    value maps to exactly one surrogate_key_column value. Catches a
    surrogate key generation bug -- e.g. a column left out of the hash
    inputs, a non-deterministic expression accidentally used, or a type-cast
    inconsistency -- that a plain `unique` test on the surrogate key column
    would miss (unique only proves no duplicates; it says nothing about
    whether the same input consistently produces the same output).

    IMPORTANT for Type-2 (SCD2) dimensions: business_key here must be the
    SAME composite key used to generate the surrogate key (e.g.
    ['customer_id', 'dbt_valid_from']), not just the natural key alone.
    Passing only the natural key against a Type-2 dimension will falsely
    fail this test, since each historical version legitimately has a
    different surrogate key for the same natural key -- that's the whole
    point of including a version discriminator (see generate_dimension()'s
    Type-2 guidance). This test is about internal consistency of whatever
    key you pass it, not about natural-key uniqueness.

    Args:
        business_key (string or list, required): the exact key (or
            composite key) used to generate the surrogate key.
        surrogate_key_column (string, required): the surrogate key column to check.

    Usage:
        models:
          - name: dim_customer
            tests:
              - clearpoint_dbt_utils.surrogate_key_is_deterministic:
                  arguments:
                    business_key: customer_id
                    surrogate_key_column: customer_key
-#}
{%- set business_keys = business_key if (business_key is iterable and business_key is not string) else [business_key] -%}
{%- set key_cols = business_keys | join(', ') -%}

select {{ key_cols }}, count(distinct {{ surrogate_key_column }}) as distinct_key_count
from {{ model }}
group by {{ key_cols }}
having count(distinct {{ surrogate_key_column }}) > 1
{% endtest %}
