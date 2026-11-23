data d;input x y;datalines;
.123456789012355 1
.123456789045678 2
.123456789144444 2
.123456789944444 2
.123456789012345 2
-10 1
2 2
12 1
-2 2
;
run;
proc freq data=d order=internal;format x best16.;tables x / out=o;run;data _null_;set o;file print;put 'COUNT ' count 3.;if count=3 then do;ismin=(x < .12345678901235);put 'MINIMUM' ismin 1.;end;run;
