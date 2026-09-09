/* BUG-sqlemptyaggexpr: no GROUP BY, aggregate wrapped in an expression or CASE,
   over a physically zero-row table — SAS returns ONE row (aggregates missing,
   count(*) = 0); opensas indexed a bogus rep row and crashed (OOB/SIGSEGV). */
data w; x=1; if 0 then output; run;
proc sql; select mean(x)+1 from w; quit;
proc sql; select case when count(*)>0 then mean(x) else . end as c from w; quit;
proc sql; select mean(x)+1 as m, count(*) as n, sum(x)*2 as s from w; quit;
proc sql; select case when mean(x)>0 then mean(x) else . end as c from w; quit;
proc sql; select mean(x) as m from w having count(*)>0; quit;
proc sql; select mean(x) as m from w having count(*)=0; quit;
proc sql; select mean(x)+1 as m from w order by case when count(*)>0 then 1 else 0 end; quit;
