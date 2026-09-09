/* BUG-tabulaterowdim: a crossed/stacked ROW dimension used to silently keep
   only the FIRST row var (undetectable — output looked like a valid single-var
   table). It must FAIL LOUD instead (mirrors PROC REPORT ACROSS). The valid
   single-row TABULATE below still renders; the 2nd proc (`table reg*sex,`)
   prints nothing to stdout and reports UNSUPPORTED to stderr (exit 2). If the
   silent-drop regresses, the 2nd proc would append a table here and mismatch.
   The "(exit 2)" above is now PINNED. This is the OTHER end of the contract
   from the rc-1 fixtures: an unsupported feature is an opensas GAP, and if a
   later sweep demotes the gap paths to 1 (audit-exitcodecontract §5 proposes
   moving 99 sites the other way) rc 2 must not silently stop being reachable.
   expect-rc: 2 */
data d;
  input reg $ sex $ age;
  datalines;
E M 10
E F 20
W M 30
W F 40
E M 15
;
run;
proc tabulate data=d;
  class reg sex;
  var age;
  table reg, age*mean;
run;
proc tabulate data=d;
  class reg sex;
  var age;
  table reg*sex, age*mean;
run;
