/* STAT-INBREED-001: BY groups are separate populations (names restart);
   numeric identifiers; character names recognized on their first 12
   characters (numeric and long-name listings checked against a SAS 9.4
   reference run). Hand mathematics, group g=2: f_AP = (f_PP + .)/2 = 1/4,
   F_B = 1/4, F_C = f_BB = (1 + 1/4)/2 = 0.625; group g=1: F_B = f_AA = 1/2.
   Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data grp;
input g id $ p1 $ p2 $;
datalines;
1 A . .
1 B A A
2 A P .
2 B A P
2 C B B
;
proc inbreed data=grp ind;
by g;
run;
data numped;
input i p q;
datalines;
1 . .
2 . .
3 1 2
. 1 2
;
proc inbreed data=numped matrix covar;
run;
data longn;
input animal :$20. sire :$20. dam :$20.;
datalines;
ABCDEFGHIJKLMNO1 . .
ABCDEFGHIJKLMNO2 . .
KID ABCDEFGHIJKLMNO1 ABCDEFGHIJKLMNO2
;
proc inbreed data=longn matrix covar;
var animal sire dam;
run;
data emp;
set grp;
stop;
run;
proc inbreed data=emp matrix covar;
by g;
run;
