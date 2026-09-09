/* BUG-sqlgroupremerge: a GROUP BY select mixing a NON-group detail column with an
   aggregate REMERGES in SAS 9.4 — the group aggregate is broadcast across every
   detail row of its group, so all N rows come back (one per input row), not the
   single collapsed row per group. `gtot` = each row's group total.
   Guards: a pure GROUP BY select whose only bare column IS the group key still
   collapses to one row per group; a GROUP BY + HAVING with no detail column
   still collapses. */
data t; input dept $ sal; datalines;
A 100
A 200
B 300
B 100
B 200
;
run;
proc sql; select dept, sal, sum(sal) as gtot from t group by dept; quit;
proc sql; select dept, sum(sal) as s from t group by dept; quit;
proc sql; select dept, sum(sal) as s from t group by dept having sum(sal) > 500; quit;
