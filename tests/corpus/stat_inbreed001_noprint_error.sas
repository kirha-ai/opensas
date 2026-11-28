/* expect-rc: 1
   STAT-INBREED-001 negative: NOPRINT without OUTCOV= is an ERROR in SAS 9.4
   ("The NOPRINT option was specified without OUTCOV= option. ...
   Computations will not be performed.", reference run 2026-11-28); nothing
   is printed. Data: invented. */
options nocenter;
title;
data ped;
input animal $ sire $ dam $;
datalines;
A . .
B . .
C A B
;
proc inbreed data=ped covar matrix noprint;
var animal sire dam;
run;
