/* expect-rc: 2
 * STAT-HPMIXED-001: the default REML fit. Data step and PROC step are the
 * HPMIXED Getting Started simulation (S154 Chapter 62, p.4808, published
 * sample program, seed 12345). Expected words: the SAS 9.4 reference listing
 * of this program up to and including Optimization Information; the
 * estimation tables (Iteration History onward) are a loud gap owned by
 * STAT-HPMIXED-002/008 (one ERROR, rc 2).
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;

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
