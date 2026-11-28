/* STAT-GLIMMIX-001: a character FREQ variable is a user error (rc 1), not an
   implementation gap, and produces no listing. Invented data. expect-rc: 1 */
data trial;
input site arm $ n events;
datalines;
1 A 12 4
1 B 10 3
2 A 9 2
2 B 11 5
;
run;
proc glimmix data=trial;
class site arm;
model events/n = arm;
random intercept / subject=site;
freq arm;
run;
