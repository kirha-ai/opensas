/* QA tick377 F3 — %SYSEVALF dropped EVERY comparison operator and returned the
   left operand, silently (pre-existing: identical on all three tick377
   baselines). The dictionary entry's own summary (Macro Language Reference,
   printed p.352, footer-verified): %SYSEVALF "Evaluates arithmetic and logical
   expressions using floating-point arithmetic", and printed p.91: "You must
   use the %SYSEVALF function to evaluate logical expressions containing
   floating-point or missing values" — comparisons are the function's
   documented reason to exist. The layer shares %EVAL's Cmp enum and Table 6.3
   spellings (matchCmpOp) with an f64 compare action. The loud-leftover half
   (and/or/not gap-classed rc 2; garbage and `in` user-classed rc 1 — SAS
   itself rejects IN in %SYSEVALF, Restriction printed p.353) is pinned by
   unit tests in macro.zig — corpus diffs stdout only. */
data _null_;
  s = "%sysevalf(1.5 ^= 2.5)"; put "NE_CARET=[" s "]";
  s = "%sysevalf(1.5 ne 2.5)"; put "NE_WORD=[" s "]";
  s = "%sysevalf(1.5 <  2.5)"; put "LT=[" s "]";
  s = "%sysevalf(1.5 =  2.5)"; put "EQ=[" s "]";
  s = "%sysevalf(2.5 >= 2.5)"; put "GE=[" s "]";
  s = "%sysevalf(2.5 ¬= 2.5)"; put "NE_GLYPH=[" s "]";
  s = "%sysevalf(1 + 2 = 3)";  put "LOOSER=[" s "]";
  s = "%sysevalf((1.5 < 2.5) + 1)"; put "PAREN=[" s "]";
  s = "%sysevalf(1.5 < 2.5, boolean)"; put "BOOL=[" s "]";
  s = "%sysevalf(1.5 + 2.5)";  put "ARITH=[" s "]";
run;
