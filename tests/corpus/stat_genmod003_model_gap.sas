/* expect-rc: 2
   STAT-GENMOD-003 boundary: the binomial events/trials model with a CLASS
   effect is fitted, but the ZEROMODEL statement (zero-inflated models,
   STAT-GENMOD-006) is not implemented. The step must fail visibly (D-009 gap)
   and print no table at all. The following steps (a documented MODEL option
   that is not implemented, CLASS options, and a CLASS level without any event,
   whose estimate is infinite) must print nothing either; their own gap
   classification is asserted by the STAT-GENMOD-003 Zig tests in
   src/stat/genmod_binomial_tests.zig, because steps after the first error are
   not executed. Data: invented. */
options nocenter;
title;
data t;
input g $ x r n;
datalines;
a 1 0 10
a 2 0 12
b 1 4 10
b 2 6 12
c 1 3 10
c 2 7 12
;
proc genmod data=t;
class g;
model r/n = x g / dist = bin;
zeromodel x;
run;
proc genmod data=t;
class g;
model r/n = x g / dist = bin type3;
run;
proc genmod data=t;
class g / param=ref;
model r/n = x g / dist = bin;
run;
proc genmod data=t;
class g;
model r/n = x g / dist = bin;
run;
