/*=============================================================================
* Synthetic data. Regression guard for BUG-sqlbestfmt: a fractional PROC SQL
* aggregate result must render with the BEST12. format (matching the DATA step),
* not Zig's full-precision {d}. avg over each group gives non-integer means.
*============================================================================*/
libname source "inputs" access=readonly;
libname target "output";

data d; set source.d; run;

proc sql;
    create table target.sql_bestfmt as
    select g, avg(v) as m, sum(v) as s, avg(v) / 3 as third
    from d
    group by g
    order by g;
quit;
