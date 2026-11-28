/* expect-rc: 1
 * STAT-VARCOMP-001: user errors are rc 1 with no listing: a second MODEL
 * statement ("Only one MODEL statement is allowed", p.10717), an effect
 * variable missing from CLASS, and FIXED= larger than the effect count.
 * Invented data.
 */
options nosyntaxcheck;
data v;
input g $ h $ y @@;
datalines;
a x 1 a y 2 b x 4 b y 6 c x 3 c y 3
;
proc varcomp method=reml data=v;
class g;
model y=g;
model y=g;
run;
proc varcomp method=reml data=v;
class g;
model y=g h;
run;
proc varcomp method=reml data=v;
class g h;
model y=g h / fixed=3;
run;
