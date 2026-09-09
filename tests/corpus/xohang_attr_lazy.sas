/* BUG-xohang: applyAttrs was re-stamped before EVERY statement (O(attrs×vars)),
   which timed out a large SDTM program. Now it re-runs only when a new var appears. This must
   still stamp a FORMAT/LABEL onto variables defined AFTER the statement. */
data _null_;
  format early late $6.;
  label late = "Late one";
  early = "aa";              /* defined after FORMAT -> attrs re-applied */
  filler1 = 1; filler2 = 2;  /* statements with no new var -> applyAttrs skipped */
  late = "bb";               /* another new var -> attrs re-applied, gets $6. + label */
  ef = vformat(early);
  lf = vformat(late);
  ll = vlabel(late);
  put "ef=[" ef "] lf=[" lf "] ll=[" ll "]";
run;
