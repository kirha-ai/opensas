/* QA tick153 BUG-sortspecialmiss: SORT, DESCENDING and NODUPKEY preserve
   numeric missing ranks. FREQ / MISSING orders missing display values first
   (. A M Z _), followed by the ascending nonmissing numbers. */
data d; input x @@; datalines;
5 -3 .Z 0 . ._ .A -100 .M 2 .A 5 -3
;
run;

proc sort data=d out=asc; by x; run;
data _null_; set asc; put "asc x=" x; run;

proc sort data=d out=desc; by descending x; run;
data _null_; set desc; put "desc x=" x; run;

proc sort data=d out=u nodupkey; by x; run;
data _null_; set u; put "distinct x=" x; run;

proc freq data=d; tables x / missing; run;
