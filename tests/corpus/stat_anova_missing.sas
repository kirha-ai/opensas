/* STAT-ANOVA-001 close-out: Missing Values (S154 pp.1138-1139) and FREQ
 * (p.1119). Invented data. Every printed token was checked in order
 * against the SAS 9.4 listing of this same program (ODS Graphics off):
 * dependent-variable groups by missing-value pattern, union class levels,
 * pages grouped by pattern, MEANS per group, FREQ rows and heading. */
ods graphics off;
data s;
  input g y1 y2 y3;
  datalines;
1 1 10 4
1 2 11 5
2 3 . 6
2 5 13 7
1 . 12 .
2 4 15 8
1 6 14 2
3 8 . 1
3 9 . 3
;
title 'Q17 y1 y3 share pattern';
proc anova data=s; class g; model y1 y2 y3=g; run; quit;
title 'Q18 level absent for y2';
proc anova data=s; class g; model y1 y2=g; run; quit;
title 'Q19 patterns with means';
proc anova data=s; class g; model y1 y2=g; means g; run; quit;
data s2;
  input g y1 y2 y3 f;
  datalines;
1 1 10 4 1
1 2 11 5 -2
2 3 . 6 .
2 5 13 . 1.5
. 9 9 2 1
1 . 12 7 1
2 4 15 8 3
1 6 14 2 0
2 8 . 1 1
;
title 'Q12 freq with missing and negative';
proc anova data=s2; class g; model y3=g; freq f; run; quit;
title 'Q13 patterns with freq';
proc anova data=s2; class g; model y1 y2=g; freq f; run; quit;
title 'Q14 three responses, y1 and y3 share pattern';
data t; set s2; if _n_ ne 4; run;
proc anova data=t; class g; model y1 y2 y3=g; run; quit;
