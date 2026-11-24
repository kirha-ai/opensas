/* STAT-HPMIXED-010: HPMIXED — LSMEANS
 * Source: S154 / Chapter 62 / `LSMEANS Statement` (PDF pp. 4825–4827).
 * Discriminates: Example 62.3: Using PROC GLIMMIX for Further Analysis of PROC HPMIXED Fit; explicit statements: LSMEANS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Sim;
keep Species Farm Animal Yield;
array AnimalEffect{3000};
array AnimalSpecies{3000};
array AnimalFarm{3000};
do i = 1 to 3000;
AnimalEffect{i} = sqrt(4.0)*rannor(12345);
AnimalSpecies{i} = 1 + int(5*ranuni(12345));
AnimalFarm{i} = 1 + int(10 *ranuni(12345));
end;
do i = 1 to 40000;
Animal = 1 + int(3000 *ranuni(12345));
Species = AnimalSpecies{Animal};
Farm = AnimalFarm{Animal};
Yield = 1 + Species + int(Farm/2) + AnimalEffect{Animal}
+ sqrt(8.0)*rannor(12345);
output;
end;
run;
proc hpmixed data=Sim;
class Species Farm Animal;
model Yield = Farm|Species;
random Animal;
test Species Species*Farm;
ods output CovParms=HPMEstimate;
run;
ods graphics on;
proc glimmix data=Sim;
class Species Farm Animal;
model Yield = Farm|Species;
random int/sub=Animal;
parms /pdata=HPMEstimate hold=1,2 noiter;
lsmeans Farm / pdiff=all plot=diffplot;
run;
