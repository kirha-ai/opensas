/* expect-rc: 1
 * STAT-CANDISC-001: BY groups (PDF p.2159) with a WHERE= data set option and
 * SHORT: the second group has only two classes (S=1, exact F statistics and
 * the exact-F note), each group repeats the missing-value warnings with its
 * own counts. Invented data; expected listing is the SAS 9.4 output, minus
 * the blank line SAS writes at the top of each page (opensas convention).
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'Invented Plants';
data plants;
  input grp $ x1 x2 x3 f w;
  if grp = "." then grp = " ";
  datalines;
A 2.1 3.5 1.0 1 1.0
A 2.5 3.1 1.4 2 0.5
A 1.9 3.9 0.8 1 1.5
A 2.8 3.3 1.9 1 1.0
A 2.2 . 1.1 1 1.0
B 3.9 2.2 2.5 1 2.0
B 4.4 2.0 2.9 3 1.0
B 3.6 2.9 2.1 1 1.0
B 4.1 2.4 3.3 1 0.5
C 5.2 4.1 1.2 2 1.0
C 5.9 4.6 0.7 1 1.0
C 6.3 3.8 1.6 1 1.5
C 5.5 4.9 1.1 1 1.0
. 4.0 3.0 2.0 1 1.0
;
data two; set plants; do b=1 to 2; output; end; run;
proc sort data=two; by b; run;
proc candisc data=two(where=(grp ne 'C' or b=1)) short;
  by b;
  class grp;
  var x1 x2;
run;
