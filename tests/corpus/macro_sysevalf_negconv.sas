/* %SYSEVALF conversion-type argument on NEGATIVE and zero operands —
   INTEGER truncates toward zero (-1.5 -> -1), CEIL rounds up (-1), FLOOR rounds
   down (-2), BOOLEAN is 1 for any nonzero and 0 for zero. The existing
   macro_macrofns fixture only pins positive operands, where INTEGER and FLOOR
   agree; the negative case is the one that distinguishes them.
   The NULL_BOOL row CHANGED at NOTE-sysevalfempty: %sysevalf(,boolean) has NO
   expression, and printed p.354 documents the result verbatim — "If expression
   evaluates to a null value ... the following error results:
   ERROR: %SYSEVALF function has no expression to evaluate." — so the call now
   raises that ERROR (stderr; the corpus diffs stdout only) and expands to
   NOTHING, leaving s empty. The old NULL_BOOL=[0] was the silent-0 bug.
   Synthetic. doc-finder tick284 (verified-clean pin); NULL_BOOL re-pinned
   coder tick396 (NOTE-sysevalfempty, p.354).
   expect-rc: 1 */
data _null_; length s $12;
  s = "%sysevalf(-1.5,integer)"; put "NEG_INT=[" s "]";
  s = "%sysevalf(-1.5,ceil)";    put "NEG_CEIL=[" s "]";
  s = "%sysevalf(-1.5,floor)";   put "NEG_FLOOR=[" s "]";
  s = "%sysevalf(1.5,integer)";  put "POS_INT=[" s "]";
  s = "%sysevalf(1.5,ceil)";     put "POS_CEIL=[" s "]";
  s = "%sysevalf(1.5,floor)";    put "POS_FLOOR=[" s "]";
  s = "%sysevalf(-3,boolean)";   put "NEG_BOOL=[" s "]";
  s = "%sysevalf(0,boolean)";    put "ZERO_BOOL=[" s "]";
  s = "%sysevalf(,boolean)";     put "NULL_BOOL=[" s "]"; /* ERROR p.354: no expression — expands to nothing */
run;
