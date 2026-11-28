/* STAT-LATTICE-001: PROC LATTICE balanced square lattice listings: two VAR
 * responses in one step (the second follows without a new procedure title),
 * the Treatmnt alias with the default response list, and a numeric BY
 * variable excluded from the default response list. Data: the published
 * Getting Started sample of the SAS/STAT 15.4 LATTICE chapter (W2 is a
 * derived column). The expected listing is a SAS 15.4 reference run of this
 * program; the blank line SAS writes before each new page title is dropped
 * (opensas starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Q';
data Pigs;
input Group Block Treatment Weight @@;
W2 = Weight*2 + Treatment/7;
datalines;
1 1 1 2.20 1 1 2 1.84 1 1 3 2.18 1 2 4 2.05 1 2 5 0.85
1 2 6 1.86 1 3 7 0.73 1 3 8 1.60 1 3 9 1.76
2 1 1 1.19 2 1 4 1.20 2 1 7 1.15 2 2 2 2.26 2 2 5 1.07
2 2 8 1.45 2 3 3 2.12 2 3 6 2.03 2 3 9 1.63
3 1 1 1.81 3 1 5 1.16 3 1 9 1.11 3 2 2 1.76 3 2 6 2.16
3 2 7 1.80 3 3 3 1.71 3 3 4 1.57 3 3 8 1.13
4 1 1 1.77 4 1 6 1.57 4 1 8 1.43 4 2 2 1.50 4 2 4 1.60
4 2 9 1.42 4 3 3 2.04 4 3 5 0.93 4 3 7 1.78
;
title2 'A: two responses';
proc lattice data=Pigs; var Weight W2; run;
title2 'B: Treatmnt alias';
data old; set Pigs(rename=(Treatment=Treatmnt)); drop W2; run;
proc lattice data=old; run;
title2 'G: numeric BY in default list';
data g; set Pigs; bb=1; drop W2; run;
proc lattice data=g; by bb; run;
