/* STAT-LIFETEST-002: product-limit listing and two-sample tests with tied
 * event times inside each stratum. Invented data. Every number in the
 * expected listing was recomputed independently (exact rationals for the
 * estimates, scores and covariances); the layout is that of the SAS listing
 * in stat_lifetest_strata_default.txt.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data tied; input time status group $; datalines;
1 1 A
1 1 A
3 1 A
4 1 A
5 0 A
2 1 B
2 1 B
4 1 B
6 1 B
7 0 B
;
run;
proc lifetest data=tied; time time*status(0); strata group; run;
