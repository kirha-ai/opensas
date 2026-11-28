/* expect-rc: 2
 * STAT-SIMNORMAL-001: CONDITION (conditional simulation, STAT-SIMNORMAL-003/004) is a loud gap.
 * Invented moments. */
data c3(type=cov);
length _TYPE_ $8 _NAME_ $8;
input _TYPE_ $ _NAME_ $ a b c;
datalines;
MEAN . 10 -2 0.5
COV a 4 1.2 -0.6
COV b 1.2 9 2.1
COV c -0.6 2.1 1.5
COND . . . 1
;
run;
proc simnormal data=c3 out=r18 nr=1 seed=987; var a b; cond c; run;
