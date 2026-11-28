/* STAT-CORRESP-001: negative WEIGHT values mark supplementary rows (p.2579,
 * p.2601): the default listing adds the supplementary row coordinates,
 * quality and squared cosines; SHORT DIMENS=1 without ID labels rows by
 * observation number. Invented data. Expected listing: SAS 9.4 (SAS/STAT
 * 15.4) output.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data S; input nm $ a b c w; datalines;
x1 3 5 7 1
x2 4 1 2 1
s1 1 1 1 -1
x3 9 2 5 1
s2 2 6 1 -2
;
title "S1"; proc corresp data=S out=o1; var a b c; weight w; id nm; run;
title "S2"; proc corresp data=S short dimens=1; var a b c; weight w; run;
