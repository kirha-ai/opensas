/* Multiset difference keeping duplicates (SQL EXCEPT ALL) */
data planned; input VISIT $; datalines;
SCREEN
WEEK4
WEEK4
WEEK8
;
run;
data done; input VISIT $; datalines;
SCREEN
WEEK4
;
run;
proc sql;
  select VISIT from planned except all select VISIT from done order by VISIT;
quit;
