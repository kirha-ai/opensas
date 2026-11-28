/* expect-rc: 2
 * STAT-GLMMOD-003: valid SAS that opensas does not implement must fail
 * visibly (D-009 gap) and print no partial listing: OUTDESIGN= with a
 * repeated dependent (SAS renames the copy, y1 -> y12; rule not established)
 * and OUTDESIGN= for passes whose design columns differ (STAT-GLMMOD-004).
 * (CLASS / TRUNCATE, formerly gapped here, is implemented:
 * stat_glmmod003_model.sas.) Invented data.
 */
options nosyntaxcheck;
data a;
input g $ y1 y3;
datalines;
a 4 6
a 5 7
b 6 8
c 8 .
;
proc glmmod data=a outdesign=d1;
class g;
model y1 y1 = g;
run;
proc glmmod data=a outdesign=d2;
class g;
model y1 y3 = g;
run;
