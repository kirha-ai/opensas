/* STAT-ANOVA-007: PROC ANOVA MEANS statement issued interactively after RUN
 * (retained model), two dependent variables, one main effect.
 * Data: published SAS/STAT 15.4 ch.29 sample (Randomized Complete Block).
 * Every printed value was checked token-for-token, all fields in order,
 * against the SAS listing of this same program. */
options nodate nonumber nocenter linesize=160;
title1 'Randomized Complete Block';
data RCB;
input Block Treatment $ Yield Worth @@;
datalines;
1 A 32.6 112 1 B 36.4 130 1 C 29.5 106
2 A 42.7 139 2 B 47.1 143 2 C 32.9 112
3 A 35.3 124 3 B 40.1 134 3 C 33.6 116
;
proc anova data=RCB;
class Block Treatment;
model Yield Worth=Block Treatment;
run;
means Treatment;
run;
