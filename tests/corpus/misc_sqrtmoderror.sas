/* BUG-sqrtmoderror: SQRT of a negative argument and MOD with a zero divisor
   take the shared invalid-arg path (domErr): NOTE + _ERROR_=1 + missing, same
   as LOG of a nonpositive (misc_fnseterror.sas). The `if _error_ then …`
   validation idiom must fire; valid calls leave _ERROR_ untouched.
   NOTEs go to stderr (off the diff). */
data _null_;
  x = sqrt(-1);            /* invalid: NOTE + _ERROR_=1, missing */
  if _error_ then put 'caught-sqrt';
  put "x=[" x "]";

  _error_ = 0;             /* reset, as the executor does per iteration */
  y = mod(5, 0);           /* zero divisor: NOTE + _ERROR_=1, missing */
  if _error_ then put 'caught-mod';
  put "y=[" y "]";

  _error_ = 0;
  a = sqrt(16);            /* valid: no NOTE, no _ERROR_ */
  b = mod(5, 2);
  if _error_ then put 'BAD-flag';
  else put 'clean';
  put "a=[" a "] b=[" b "]";
run;
