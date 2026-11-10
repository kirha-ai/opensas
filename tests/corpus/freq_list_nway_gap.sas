/* GAP-freq-table-complete: supported table syntax regression. */
data d;
  input g h;
  datalines;
1 7
2 7
2 8
3 8
;
run;
proc freq data=d;
  tables g*h / list;
run;
