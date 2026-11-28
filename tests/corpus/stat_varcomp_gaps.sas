/* expect-rc: 2
 * STAT-VARCOMP-001: methods other than METHOD=REML (here the default,
 * MIVQUE0) are owned by later VARCOMP tickets and must fail visibly with no
 * listing. Invented data.
 */
data v;
input g $ y @@;
datalines;
a 1 a 2 b 4 b 6 c 3 c 3
;
proc varcomp data=v;
class g;
model y=g;
run;
