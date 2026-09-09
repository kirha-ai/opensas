/* BUG-sqlorderexpr: ORDER BY a bare expression (not a plain column/positional/
   CASE/agg) must evaluate the expression per row and sort on it. Previously each
   operand token became a phantom sort key, so the order came out wrong. */
data s;
  input x;
  datalines;
3
1
2
;
run;
data n;
  input x;
  datalines;
-5
3
-1
;
run;
proc sql;
  create table o1 as select x from s order by 10-x;   /* keys 7,9,8 -> 3,2,1 */
  create table o2 as select x from n order by abs(x);  /* abs 5,3,1 -> -1,3,-5 */
quit;
proc print data=o1 noobs; run;
proc print data=o2 noobs; run;
