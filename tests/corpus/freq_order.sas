data d; input g $; datalines;
C
C
C
A
B
B
;
run;
proc freq data=d order=freq; tables g; run;
proc freq data=d order=data; tables g; run;
