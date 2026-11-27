/* Independent exact calculations. RMD deviations (2,0,2)/(1,0,1) have
   20 fixed-size labelings; upper mass6, multiplicative two-sided12, point4.
   Tied KS values(1,1,2,2) have6 labelings; D,D+,D- upper masses2,1,6. */
ods graphics off;
data scale;
input g $ x;
datalines;
A 1
A 3
A 5
B 2
B 3
B 4
;
run;
proc npar1way data=scale rmd; class g; var x; exact rmd / point midp; run;
data tied;
input g $ x;
datalines;
A 1
A 1
B 2
B 2
;
run;
ods select KSExactTest;
proc npar1way data=tied edf; class g; var x; exact ks; run;
