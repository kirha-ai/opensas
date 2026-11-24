/* STAT-MIXED-011: MIXED — LSMESTIMATE
 * Source: S154 / Chapter 84 / `LSMESTIMATE Statement` (PDF pp. 6652–6653).
 * Discriminates: Example 84.10: Isotonic Contrasts for Ordered Mean Values; explicit statements: LSMESTIMATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data FerriteCores;
do Temp = 1 to 4;
do rep = 1 to 5;
drop rep;
input MagneticForce @@;
output;
end;
end;
datalines;
10.8 9.9 10.7 10.4 9.7
10.7 10.6 11.0 10.8 10.9
11.9 11.2 11.0 11.1 11.3
11.4 10.7 10.9 11.3 11.7
;
proc mixed data=FerriteCores;
class Temp;
model MagneticForce = Temp;
lsmestimate Temp
'avg(1:1)<avg(2:4)' -3 1 1 1 divisor=3,
'avg(1:2)<avg(3:4)' -1 -1 1 1 divisor=2,
'avg(1:3)<avg(4:4)' -1 -1 -1 3 divisor=3
/ adjust=simulate(seed=1) cl upper;
ods select LSMestimates;
run;
