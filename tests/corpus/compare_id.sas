/* QA regression (BUG-compareid fixed): PROC COMPARE matches obs BY the ID key,
   not positionally — same data in different row order compares EQUAL. */
data base; input id v; datalines;
1 10
2 20
3 30
;
run;
data comp; input id v; datalines;
3 30
1 10
2 20
;
run;
proc compare base=base compare=comp; id id; run;
