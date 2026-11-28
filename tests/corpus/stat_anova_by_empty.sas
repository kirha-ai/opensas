/* expect-rc: 1 */
/* STAT-ANOVA-001 close-out: a BY group with no valid observation is an
 * ERROR for that group only; other groups and later steps still run.
 * Invented data; tokens checked in order against the SAS 9.4 listing. */
ods graphics off;
title 'Q15 BY group with no valid obs';
data b; input u g y; datalines;
1 1 1
1 2 3
1 1 2
1 2 6
2 1 .
2 2 .
3 1 5
3 2 9
3 1 4
3 2 7
;
proc anova data=b; by u; class g; model y=g; run; quit;
title 'Q16 after';
proc print data=b(obs=1); run;
