/* expect-rc: 1
 * STAT-SURVEYPHREG-001: documented invalid input is a user error: no MODEL
 * statement, two MODEL or WEIGHT statements, an unknown variable, a
 * character censoring or WEIGHT variable, and an unknown option.
 * Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data s;
input st psu w t c x f k $;
datalines;
1 1 2 5.1 1 1.2 1 a
1 2 3 2.2 1 0.3 2 b
2 1 4 8.1 1 1.6 1 a
2 2 2 3.7 0 2.2 3 b
;
proc surveyphreg data=s; strata st; cluster psu; weight w; run;
proc surveyphreg data=s; weight w; model t*c(0)=x; model t*c(0)=x; run;
proc surveyphreg data=s; weight w; weight f; model t*c(0)=x; run;
proc surveyphreg data=s; weight w; model t*c(0)=nosuch; run;
proc surveyphreg data=s; weight w; model t*k(0)=x; run;
proc surveyphreg data=s; weight k; model t*c(0)=x; run;
proc surveyphreg data=s bogus; weight w; model t*c(0)=x; run;
