/* Asymptotic BY oracle; exact families remain with dev3. */
options nosyntaxcheck; ods graphics off;
data observed;
input site $ stratum r c n;
datalines;
A 1 1 1 2
A 1 1 2 0
A 1 2 1 0
A 1 2 2 2
A 2 1 1 0
A 2 1 2 2
A 2 2 1 2
A 2 2 2 0
B 1 1 1 16
B 1 1 2 11
B 1 2 1 5
B 1 2 2 20
B 2 1 1 12
B 2 1 2 16
B 2 2 1 7
B 2 2 2 19
;
proc freq data=observed;
by site;
tables stratum*r*c / cmh(bdt mf) agree commonriskdiff(cl=(mh score) test printwts) noprint;

weight n / zeros;
run;
