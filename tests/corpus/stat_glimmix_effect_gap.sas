/* STAT-GLIMMIX-003: a valid model with main, interaction and nested effects
   and NOINT builds its non-full-rank design and then stops at the estimation
   gap (rc 2) without a listing. Invented data. expect-rc: 2 */
data trial;
input site arm $ n events dose;
datalines;
1 A 12 4 1
1 B 10 3 2
2 A 9 2 3
2 B 11 5 4
3 A 8 1 5
;
run;
proc glimmix data=trial;
class site arm;
model events/n = arm arm*site dose(arm) / noint solution;
random intercept / subject=site;
run;
