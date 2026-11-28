/* expect-rc: 2
   STAT-SURVEYIMPUTE-001 boundary: imputation-adjusted jackknife replicate
   weights (OUTPUT with VARMETHOD=JACKKNIFE), hot-deck and FHDI random donor
   selection and CELLS imputation cells are not implemented. The first step
   must fail visibly (D-009 gap) and print no listing; later steps are not
   run after it (each gap also has a unit test in
   src/stat/surveyimpute_tests.zig). Data: invented. */
options nodate nonumber nocenter linesize=160;
title;
data s;
input h c w x y;
datalines;
1 1 2 0 0
1 1 2 0 .
1 2 3 0 1
1 2 3 1 1
2 3 1 . 1
2 3 1 1 0
2 4 4 1 1
2 4 4 . .
;
proc surveyimpute data=s method=fefi varmethod=jackknife;
class x y; var x y; strata h; cluster c; weight w;
output out=imp outjkcoefs=jk;
run;
proc surveyimpute data=s method=hotdeck(selection=srswor) seed=1;
var x y; weight w;
run;
proc surveyimpute data=s;
class x y; var x y; cells h; weight w;
run;
