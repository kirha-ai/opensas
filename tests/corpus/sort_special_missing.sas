/* BUG-sortspecialmiss: SORT and NODUPKEY use ._ < . < .A < ... < .Z.
   FREQ / MISSING lists the distinct missing levels in display order: . A B _. */
data m; input id x; datalines;
1 .Z
2 .
3 ._
4 .A
5 .B
;
run;
proc sort data=m out=s; by x; run;
data _null_; set s; put "id=" id " x=" x; run;

data d; input x; datalines;
.A
.B
.
._
.A
;
run;
proc sort data=d out=u nodupkey; by x; run;
data _null_; set u; put "dup x=" x; run;

proc freq data=d; tables x / missing; run;
