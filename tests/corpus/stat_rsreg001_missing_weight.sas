/* STAT-RSREG-001: observation selection (S154 pp.8878-8879, 8881-8882).
 * Unweighted: a missing response (x1=9) and a missing factor are excluded,
 * also from the coding range; rows whose would-be weight is 0 or missing
 * are used (no WEIGHT statement). Weighted with LACKFIT: WEIGHT 0 and
 * missing rows are excluded (coding range shrinks to 1..3), the response
 * mean and pure error are weighted. Invented data; every token was checked
 * against a SAS 9.4 reference run of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'P1 missing response row widens factor range';
data a; input y x1 x2 w @@; datalines;
10 1 1 1  12 1 2 2  15 2 1 1  11 2 2 1  20 3 3 2  18 1 3 1  14 3 1 1  16 2 3 3  13 3 2 1  17 2 2 1
. 9 9 1  19 -5 2 0  21 2 2 .  22 . 1 1
;
proc rsreg data=a; model y = x1 x2; run;
title 'P2 weighted with lackfit';
proc rsreg data=a; model y = x1 x2 / lackfit; weight w; id x1 x2; run;
