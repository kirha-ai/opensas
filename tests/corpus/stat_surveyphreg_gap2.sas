/* expect-rc: 2
   STAT-SURVEYPHREG-001 boundary, second set: NOMCAR, ATRISK, DATA= data set
   options, a MODEL without covariates, FREQ with an observation excluded by
   its WEIGHT, an all-excluded input by missing covariates, and an empty BY
   input must fail visibly (D-009 gap) and print no table. Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data s;
input st psu w t c x f;
datalines;
1 1 2 5.1 1 1.2 1
1 1 . 3.4 0 0.5 2
1 2 3 2.2 1 0.3 1
1 2 3 9.0 1 1.9 1
2 1 4 8.1 1 1.6 1
2 1 4 2.9 1 0.2 2
2 2 2 3.7 1 2.2 1
2 2 2 6.8 1 0.9 1
;
data mx; set s; x=.; run;
data e; set s; stop; run;
proc surveyphreg data=s nomcar; strata st; cluster psu; weight w; model t*c(0)=x; run;
proc surveyphreg data=s atrisk; strata st; cluster psu; weight w; model t*c(0)=x; run;
proc surveyphreg data=s(where=(x>0)); strata st; cluster psu; weight w; model t*c(0)=x; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; model t*c(0)=; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; freq f; model t*c(0)=x; run;
proc surveyphreg data=mx; strata st; cluster psu; weight w; model t*c(0)=x; run;
proc surveyphreg data=e; by st; strata st; cluster psu; weight w; model t*c(0)=x; run;
