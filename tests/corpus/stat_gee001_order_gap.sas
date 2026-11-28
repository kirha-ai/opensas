/* expect-rc: 2
 * STAT-GEE-001: PROC GEE ORDER=DATA without DESCENDING is not verified
 * against SAS output (only ORDER=DATA DESCENDING was replayed); the step
 * must fail visibly (D-009 gap) without a partial listing. Invented data.
 */
options linesize=160;
data visits;
input id grp $ t y w;
datalines;
1 a 1 1 1
1 a 2 0 2
2 b 1 0 1
2 b 2 1 1
3 a 1 1 1
3 a 2 1 1
;
run;
proc gee data=visits order=data;
class id grp;
model y = grp t / dist=bin link=logit;
repeated subject=id / type=exch;
run;
