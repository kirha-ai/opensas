/* STAT-HPMIXED-008: HPMIXED — CONTRAST / ESTIMATE / TEST
 * Source: S154 / Chapter 62 / `CONTRAST Statement` (PDF pp. 4819–4821); S154 / Chapter 62 / `ESTIMATE Statement` (PDF pp. 4822–4824); S154 / Chapter 62 / `TEST Statement` (PDF p. 4842).
 * Discriminates: Getting Started: HPMIXED Procedure; explicit statements: CONTRAST, TEST
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
array AnimalFarm{3000};
array AnimalSpecies{3000};
do i = 1 to dim(AnimalEffect);
AnimalEffect{i} = sqrt(4.0) *rannor(12345);
AnimalFarm{i} = 1 + int(100 *ranuni(12345));
AnimalSpecies{i} = 1 + int(5*ranuni(12345));
end;
do i = 1 to 40000;
Animal = 1 + int(3000 *ranuni(12345));
Species = AnimalSpecies{Animal};
Farm = AnimalFarm{Animal};
Yield = 1 + Species + Farm/10 + AnimalEffect{Animal}
+ sqrt(8.0)*rannor(12345);
output;
end;
run;
proc hpmixed data=Sim;
class Species Farm Animal;
model Yield = Species Species*Farm;
random Animal;
test Species*Farm;
contrast 'Species1 = Species2 = Species3'
Species 1 0 -1,
Species 0 1 -1;
run;
