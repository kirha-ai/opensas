/*=============================================================================
* Synthetic data. Regression guard for BUG-ordercase: PROC SQL ORDER BY a CASE
* expression must sort by the CASE key (not fall back to unsorted order).
* Rows with x>20 get key 1 (first), others key 2; ties keep input order.
*============================================================================*/
libname source "inputs" access=readonly;
libname target "output";

data d; set source.d; run;

proc sql;
    create table target.sql_ordercase as
    select x, case when x > 20 then 1 else 2 end as k
    from d
    order by case when x > 20 then 1 else 2 end, x;
quit;
