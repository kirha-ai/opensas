/* STAT-CORRESP-001: NOROW suppresses the row points (p.2572) and CHI2P adds
 * the chi-square p-value (p.2569) in its "= .dddd" form. Invented data.
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) output.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data S;
input a b c;
datalines;
3 5 7
4 1 2
9 2 5
;
ods graphics off;
title "E";
proc corresp data=S short norow chi2p;
var a b c;
run;
