/* VS: n and mean BP per visit (SQL group by, aggregates) */
data vs;
  input VISIT $ VSSTRESN;
  datalines;
BASELINE 120
BASELINE 130
WEEK4 125
WEEK4 128
WEEK8 122
;
run;

proc sql;
  select VISIT, count(*) as n, avg(VSSTRESN) as mean_bp
  from vs
  group by VISIT
  order by VISIT;
quit;
