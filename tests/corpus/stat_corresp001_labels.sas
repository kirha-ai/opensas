/* STAT-CORRESP-001: row-label column width (longest ID value rounded up to a
 * multiple of 8), a numeric ID variable, and the six-significant-digit
 * chi-square column for large tables. Invented data. Expected listing:
 * SAS 9.4 (SAS/STAT 15.4) output.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data S;
length n10 $10 n12 $12 n30 $30;
input n10 n12 n30 a b c;
datalines;
abcdefghij abcdefghijkl x 3 5 7
b b y 4 1 2
c c z 9 2 5
;
title "L10"; proc corresp data=S short; var a b c; id n10; run;
title "L12"; proc corresp data=S short; var a b c; id n12; run;
title "L30"; proc corresp data=S short; var a b c; id n30; run;
data B; input id a b c; datalines;
1 3000 5000 7000
2 4000 1000 2000
3 9000 2000 5000
;
title "BIG"; proc corresp data=B short; var a b c; id id; run;
data B2; set B; a=a*10; b=b*10; c=c*10; run;
title "BIG2"; proc corresp data=B2 short; var a b c; run;
