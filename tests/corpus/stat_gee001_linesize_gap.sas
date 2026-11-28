/* expect-rc: 2
 * STAT-GEE-001: without DESCENDING the listing carries the DESCENDING hint
 * wrapped at LINESIZE; with no explicit OPTIONS LINESIZE= (default line size
 * not verified) the step must fail visibly (D-009 gap) without a partial
 * listing. Invented data.
 */
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
proc gee data=visits;
class id grp;
model y = grp t / dist=bin link=logit;
repeated subject=id / type=exch;
weight w;
run;
