data m;
  input id v;
  datalines;
1 10
2 20
;
run;
data _null_; set m; put "before id=" id " v=" v; run;
data t;
  input id v;
  datalines;
1 99
9 90
;
run;
/* Language Reference: Concepts p.600: MODIFY … BY with no master match is an ERROR ("No matching
   observation was found in m data set.", _ERROR_=1, _IORC_=1230015) and the
   unmatched row is NOT written — "0 observations added" (adding is UPDATE's
   job). The step ERROR puts later steps in syntax-check mode (BUG-errhalt),
   so the after-print is skipped; the master keeps its 2 obs (asserted in the
   exec.zig BUG-modifybynomatch test). The step ERROR is a USER error in
   valid-SAS terms — real SAS rejects this program too — so rc 1, D-009.
   expect-rc: 1 */
data m;
  modify m t;
  by id;
run;
data _null_; set m; put "after id=" id " v=" v; run;
