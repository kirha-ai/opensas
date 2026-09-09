/* Multiset intersection with duplicates (SQL INTERSECT ALL) */
data a; input dose; datalines;
50
50
100
150
;
run;
data b; input dose; datalines;
50
100
100
;
run;
proc sql;
  select dose from a intersect all select dose from b order by dose;
quit;
