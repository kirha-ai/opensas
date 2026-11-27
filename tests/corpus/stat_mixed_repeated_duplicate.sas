/* STAT-MIXED-007: duplicate repeated CLASS levels make R singular.
   S154 physical p.6680. OpenSAS D-009 invalid-input status: expect-rc: 1 */
data repeated;
input person time y;
datalines;
1 1 2
1 1 3
;
run;
proc mixed data=repeated;
class person time;
model y=;
repeated time / type=un subject=person;
run;
