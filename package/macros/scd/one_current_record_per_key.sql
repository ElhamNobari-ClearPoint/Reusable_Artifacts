{% test one_current_record_per_key(model, business_key, current_flag_column='_is_current') %}
{#-
    Generic dbt test for Type-2 (SCD2) dimensions: asserts no business key
    has MORE THAN ONE current row. Catches a duplicate "current" version
    (e.g. a bad snapshot backfill or a hand-rolled Type-2 load bug).

    Deliberately does NOT flag zero current records for a key -- a
    hard-deleted business key (see invalidate_hard_deletes=true in this
    package's documented SCD2 snapshot pattern) legitimately has zero
    current rows, and that is correct, not a bug.

    Args:
        business_key (string or list, required): natural/business key column(s).
        current_flag_column (string, optional): boolean "is current" column.
            Defaults to '_is_current', the column scd2_current_flag() produces.

    Usage:
        models:
          - name: dim_customer
            tests:
              - clearpoint_dbt_utils.one_current_record_per_key:
                  business_key: customer_id
-#}
{%- set business_keys = business_key if (business_key is iterable and business_key is not string) else [business_key] -%}
{%- set key_cols = business_keys | join(', ') -%}

select {{ key_cols }}, count(*) as current_record_count
from {{ model }}
where {{ current_flag_column }} = true
group by {{ key_cols }}
having count(*) > 1
{% endtest %}
