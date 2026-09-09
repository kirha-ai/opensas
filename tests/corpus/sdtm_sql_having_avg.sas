/* Arms whose mean BP exceeds a threshold (GROUP BY + HAVING avg) */
data vs; input ARM $ AVAL; datalines;
DRUG 120
DRUG 130
PLACEBO 150
PLACEBO 160
;
run;
proc sql;
  select ARM, avg(AVAL) as mean_bp
  from vs
  group by ARM
  having avg(AVAL) > 140
  order by ARM;
quit;
