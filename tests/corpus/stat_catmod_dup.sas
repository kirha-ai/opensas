/* STAT-CATMOD-001: duplicate declarations. "If you specify more than one BY
 * statement, only the last one specified is used" (p.2180), and a later
 * WEIGHT replaces an earlier one, so this program prints exactly the
 * stat_catmod_by listing (checked token-for-token against the SAS
 * reference for the published Chapter 36 cold-incidence data). Data: the
 * published example rows. */
options nodate nonumber nocenter linesize=160;
title;
data colds;
input sex $ residence $ periods count @@;
datalines;
female rural 0 45 female rural 1 64 female rural 2 71
female urban 0 80 female urban 1 104 female urban 2 116
male rural 0 84 male rural 1 124 male rural 2 82
male urban 0 106 male urban 1 117 male urban 2 87
;
run;
data grouped; set colds; do cohort=1 to 2; output; end; one = 1; run;
proc sort data=grouped; by cohort; run;
proc catmod data=grouped;
by sex;
weight one;
by cohort;
weight count;
response means;
model periods=sex residence sex*residence / design;
run;
quit;
