/* GAP-modzerror: MODZ with a zero divisor takes the shared invalid-arg path
   (domErr): NOTE + _ERROR_=1 + missing, same as MOD (misc_sqrtmoderror.sas)
   — was a silent missing, so the `if _error_ then …` validation idiom never
   fired (docs/findings/qa-findings-tick138.md). Valid calls leave _ERROR_
   untouched. NOTEs go to stderr (off the diff). */
data _null_;
  z = modz(5, 0);          /* zero divisor: NOTE + _ERROR_=1, missing */
  if _error_ then put 'caught-modz';
  put "z=[" z "]";

  _error_ = 0;             /* reset, as the executor does per iteration */
  a = modz(5, 2);          /* valid: no NOTE, no _ERROR_, exact remainder */
  if _error_ then put 'BAD-flag';
  else put 'clean';
  put "a=[" a "]";
run;
