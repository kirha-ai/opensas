/* BUG-sysevalfmissingzero: %SYSEVALF coerced a missing operand to 0, so
   %sysevalf(10+.) printed 10 — a silently wrong number. Macro Language
   Reference printed pp.353-354 (pdf 368-369, offset +15 verified against the
   "%SYSEVALF Macro Function 353" / "354 Chapter 17" footers):
     - plain result:   "%sysevalf(10+.)   returns  ."  (missing PROPAGATES)
     - CEIL:           "An expression containing a missing value returns a
                        missing value" (it also emits "a message noting that
                        fact" whose wording the doc never quotes — DOC-SILENT,
                        not invented here)
     - FLOOR:          "%sysevalf(.,floor)  returns  ."
     - INTEGER:        "An expression with a missing value produces a missing
                        value"
     - BOOLEAN:        "0 if the result of the expression is 0 or missing" —
                        %sysevalf(10+.,boolean) returns 0 (the ONE conversion
                        that maps missing to a number)
   Comparisons are NOT arithmetic: printed pp.91-92 (the COMPFLT macro) pin
   missing as the SMALLEST value — "%compflt(-.1,.)" logs "-.1 is greater
   than .", "%compflt(0,.)" logs "0 is greater than ." — so a comparison with
   a missing operand yields 1/0, never missing. `.=.` itself is DOC-SILENT;
   pinned to SAS's missing-equals-missing DATA-step semantics (1).
   %EVAL control: the two surfaces are DOCUMENTED to differ — ch.6 p.91
   assigns floating-point/missing operands to %SYSEVALF ("You must use the
   %SYSEVALF function to evaluate logical expressions containing
   floating-point or missing values"), and p.354 has %EVAL integer-only. So
   %eval(10+.) is the loud character-operand ERROR (on stderr; the corpus
   diffs stdout only) while %sysevalf(10+.) is `.` — do NOT "reconcile" them.
   DATA-step put (the listing, stdout) is what the corpus diffs — %put goes
   to the log (stderr) and would pin nothing.
   Synthetic. coder tick396 (BUG-sysevalfmissingzero).
   expect-rc: 1 */
%let m=.;
data _null_; length s $12;
  s = "%sysevalf(10+.)";          put "ADD_R=[" s "]";
  s = "%sysevalf(.+10)";          put "ADD_L=[" s "]";
  s = "%sysevalf(10-.)";          put "SUB_R=[" s "]";
  s = "%sysevalf(.-10)";          put "SUB_L=[" s "]";
  s = "%sysevalf(3*.)";           put "MUL_R=[" s "]";
  s = "%sysevalf(.*3)";           put "MUL_L=[" s "]";
  s = "%sysevalf(10/.)";          put "DIV_R=[" s "]";
  s = "%sysevalf(./2)";           put "DIV_L=[" s "]";
  s = "%sysevalf(./0)";           put "DIV_Z=[" s "]";
  s = "%sysevalf(2**.)";          put "POW_R=[" s "]";
  s = "%sysevalf(-.)";            put "NEG=[" s "]";
  s = "%sysevalf(.)";             put "BARE=[" s "]";
  s = "%sysevalf(10+.,boolean)";  put "BOOL_M=[" s "]";
  s = "%sysevalf(10+.,ceil)";     put "CEIL_M=[" s "]";
  s = "%sysevalf(.,floor)";       put "FLOOR_M=[" s "]";
  s = "%sysevalf(5-.,integer)";   put "INT_M=[" s "]";
  s = "%sysevalf(.<5)";           put "LT_M=[" s "]";
  s = "%sysevalf(0>.)";           put "GT_M=[" s "]";
  s = "%sysevalf(-.1>.)";         put "NEG_GT=[" s "]";
  s = "%sysevalf(.=.)";           put "EQ_MM=[" s "]";
  s = "%sysevalf(&m*2)";        put "VAR_M=[" s "]";
  s = "%eval(10+.)";              put "EVAL_ADD=[" s "]";
  s = "%eval(.<5)";               put "EVAL_CMP=[" s "]";
run;
