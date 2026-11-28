/* expect-rc: 1
 * STAT-ORTHOREG-001: user errors are rc 1 with no listing: NAMELEN= outside
 * 20..2000 (PROC ORTHOREG statement, PDF p.7288), a second MODEL statement
 * ("Only one MODEL statement is allowed", p.7296), a character dependent
 * variable, a character WEIGHT variable and a duplicated effect. Invented data.
 */
options nosyntaxcheck;
data v;
input c $ x y;
datalines;
a 1 3
b 2 5
c 3 4
d 4 8
;
proc orthoreg data=v namelen=10;
model y = x;
run;
proc orthoreg data=v;
model y = x;
model y = x;
run;
proc orthoreg data=v;
model c = x;
run;
proc orthoreg data=v;
weight c;
model y = x;
run;
proc orthoreg data=v;
model y = x x;
run;
