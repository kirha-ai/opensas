/* expect-rc: 1 */
/* An unqualified BY statement encounters a decreasing group key. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input g x;
  datalines;
2 1
2 2
1 3
;
run;

proc freq data=sample;
  by g;
  tables x;
run;
