/* STAT-CANDISC-001: a numeric CLASS variable; without a VAR statement the
 * analysis uses every numeric variable not named elsewhere (p.2160); with
 * two CLASS statements the first is used (SAS 9.4); NCAN= above the number
 * of variables is capped. One quantitative variable gives S=1. Invented
 * data; expected listing is the SAS 9.4 output of this program, minus the
 * blank line SAS writes at the top of each page (opensas convention).
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'Invented Plants';
data nums; input g y1 y2 @@; datalines;
1 1 2 1 2 3 1 3 3 1 2 1 2 5 4 2 6 6 2 5 5 2 7 4 3 9 1 3 8 2 3 9 3 3 10 2
;
proc candisc data=nums;
  class g;
run;
proc candisc data=nums; class g; class y1; var y2; run;
proc candisc data=nums ncan=5 short; class g; var y1 y2; run;
