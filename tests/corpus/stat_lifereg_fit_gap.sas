/* expect-rc: 2
 * STAT-LIFEREG-001: PROC LIFEREG declarations, CLASS/WEIGHT/BY roles and
 * observation selection are accepted, but maximum-likelihood estimation and
 * the listing are not implemented; the step must fail visibly (D-009 gap)
 * without printing a partial analysis. Invented data.
 */
data relief;
input site minutes censor arm $ w;
datalines;
1 11 0 A 1
1 14 1 B 2
1 19 0 A 1
2 16 0 B 0.5
2 21 1 A 1
2 23 0 B 1
;
run;
proc lifereg data=relief order=internal namelen=30;
by site;
class arm;
model minutes*censor(1) = arm / dist=weibull;
weight w;
run;
