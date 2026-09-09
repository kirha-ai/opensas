/* QA regression (BUG-sqlaggouter fixed): an aggregate nested in an outer
   expression collapses to one row and aggregates first, then applies the op. */
data d; input g $ v; datalines;
a 2
a 4
b 6
b 8
;
run;
proc sql; select sum(v)+10 as sp, sum(v)/count(*) as avg1, max(v)-min(v) as rng, avg(v)/2 as ah from d; quit;
proc sql; select g, sum(v)+100 as gsp from d group by g; quit;
