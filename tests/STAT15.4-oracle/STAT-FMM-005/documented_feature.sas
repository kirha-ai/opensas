/* STAT-FMM-005: FMM — RANDSTART / The Form of the Finite Mixture Model / Mixture Models Contrasted with Mixing and Mixed Models: Untangling the Terminology Web
 * Source: S154 / Chapter 46 / `RANDSTART Statement` (PDF pp. 3011–3013); S154 / Chapter 46 / `The Form of the Finite Mixture Model` (PDF pp. 3015–3016); S154 / Chapter 46 / `Mixture Models Contrasted with Mixing and Mixed Models: Untangling the Terminology Web` (PDF pp. 3016–3018).
 * Discriminates: Example 46.1: Modeling Mixing Probabilities: All Mice Are Equal, but Some Mice Are More Equal Than Others
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data ossi;
length tx $8;
input tx$ n @@;
do i=1 to n;
input y m @@;
output;
end;
drop i;
datalines;
Control 18 8 8 9 9 7 9 0 5 3 3 5 8 9 10 5 8 5 8 1 6 0 5
8 8 9 10 5 5 4 7 9 10 6 6 3 5
Control 17 8 9 7 10 10 10 1 6 6 6 1 9 8 9 6 7 5 5 7 9
2 5 5 6 2 8 1 8 0 2 7 8 5 7
PHT 19 1 9 4 9 3 7 4 7 0 7 0 4 1 8 1 7 2 7 2 8 1 7
0 2 3 10 3 7 2 7 0 8 0 8 1 10 1 1
TCPO 16 0 5 7 10 4 4 8 11 6 10 6 9 3 4 2 8 0 6 0 9
3 6 2 9 7 9 1 10 8 8 6 9
PHT+TCPO 11 2 2 0 7 1 8 7 8 0 10 0 4 0 6 0 7 6 6 1 6 1 7
;
data ossi;
set ossi;
array xx{3} x1-x3;
do i=1 to 3;
xx{i}=0;
end;
pht = 0;
tcpo = 0;
if (tx='TCPO') then do;
xx{1} = 1;
tcpo = 100;
end;
else if (tx='PHT') then do;
xx{2} = 1;
pht = 60;
end;
else if (tx='PHT+TCPO') then do;
pht = 60;
tcpo = 100;
xx{1} = 1;
xx{2} = 1;
xx{3}=1;
end;
run;
proc fmm data=ossi seed=314159;
class pht tcpo;
model y/m = / dist=binomcluster;
probmodel pht tcpo pht*tcpo;
run;
proc fmm data=ossi seed=314159;
class pht tcpo;
model y/m = pht tcpo pht*tcpo / dist=binomcluster;
probmodel pht tcpo pht *tcpo;
run;
proc fmm data=ossi seed=314159;
model y/m = x1-x3 / dist=binomcluster;
probmodel x1-x3;
run;
proc fmm data=ossi seed=314159;
model y/m = x1-x3 / dist=binomial;
run;
proc fmm data=ossi seed=314159;
model y/m = x1-x3 / dist=betabinomial;
run;
