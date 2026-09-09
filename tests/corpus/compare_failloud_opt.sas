/* BUG-comparesilentopts: PROC COMPARE used to swallow an unknown option with
   no diagnostic — a typo'd `criterionn=0.01` vanished, the default 1e-8 fuzz
   was re-armed, and the verdict could flip (silent-wrong clinical result).
   It must FAIL LOUD instead (D-002, mirrors PROC CONTENTS). The valid compare
   below still prints its "no differences" summary; the 2nd proc prints
   nothing to stdout and reports UNSUPPORTED to stderr (exit 2). If the
   silent swallow regresses, the 2nd proc would append a report here and
   mismatch.
   expect-rc: 1 */
data base; input id v; datalines;
1 10
2 20
3 30
;
run;
data comp; input id v; datalines;
1 10
2 20
3 30
;
run;
proc compare base=base compare=comp;
run;
proc compare base=base compare=comp criterionn=0.01;
run;
