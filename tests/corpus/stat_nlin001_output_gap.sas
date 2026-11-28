/* expect-rc: 2
   STAT-NLIN-001 boundary: the OUTPUT statement (STAT-NLIN-012) is recognised
   but not implemented; ID is accepted as a role for it. The step must fail
   visibly (D-009 gap) and print nothing. Data: invented. */
options nocenter;
title;
data growth;
input id x y @@;
datalines;
1 1 2.1 2 2 3.9 3 3 6.2 4 4 7.8 5 5 10.1
;
proc nlin data=growth method=marquardt;
parms a=1 b=0.5;
model y = a*x**b;
id id;
output out=pred predicted=p;
run;
