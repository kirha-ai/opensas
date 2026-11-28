/* STAT-GLIMMIX-001: the PROC dispatcher reaches GLIMMIX declarations, roles
   (BY, FREQ, WEIGHT, ID) and observation selection, then must stop visibly at
   the estimation boundary instead of fabricating a fit. Invented data.
   expect-rc: 2 */
data trial;
input block site arm $ n events f w;
datalines;
1 1 A 12 4 1 0.5
1 1 B 10 3 2.9 1
1 2 A 9 2 1 1
1 2 B 11 5 2 1
2 3 A 8 1 1 2
2 3 B 8 2 1 1
2 4 A 7 2 3 1
2 4 B 7 3 1 1
;
run;
proc glimmix data=trial method=rspl order=data namelen=30 maxopt=10 pconv=1e-6;
by block;
class site arm;
model events/n = arm / solution;
random intercept / subject=site;
freq f;
weight w;
id site arm;
run;
