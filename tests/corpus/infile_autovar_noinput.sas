/* BUG-infilebufvar (fail-loud half): `_INFILE_` in a step with NO INPUT
   statement has no input buffer to hold — referencing it must ERROR loudly,
   not silently fabricate a numeric missing. The error aborts the step and
   poisons downstream (syntax-check mode), so the trailing REGRESSED marker
   must never print: expected stdout is empty.
   expect-rc: 1 */
data a;
  x = 1;
run;

data b;
  set a;
  r = _infile_;
run;

data _null_;
  set b;
  put "REGRESSED: _INFILE_ in a no-INPUT step did not abort; r=" r;
run;
