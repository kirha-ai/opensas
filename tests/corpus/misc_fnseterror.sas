/* MISC-fnseterror: an invalid function argument sets the automatic _ERROR_=1
   (SAS 9.4), live in-step, so the validation idiom `if _error_ then …` fires —
   the log NOTE is kept. Covers functions.zig's own sites: SUBSTR nonpositive
   position / length and the shared domErr helper (LOG of a nonpositive).
   Valid calls leave _ERROR_ untouched. NOTEs go to stderr (off the diff). */
data _null_;
  a = substr('hello', 0, 2);   /* invalid 2nd arg: NOTE + _ERROR_=1, remainder */
  if _error_ then put 'caught-pos';
  put "a=[" a "]";

  _error_ = 0;                 /* reset, as the executor does per iteration */
  b = substr('hello', 2, -1);  /* invalid 3rd arg: NOTE + _ERROR_=1, remainder */
  if _error_ then put 'caught-len';
  put "b=[" b "]";

  _error_ = 0;
  c = log(-1);                 /* domErr: NOTE + _ERROR_=1, missing */
  if _error_ then put 'caught-dom';
  put "c=[" c "]";

  _error_ = 0;
  d = substr('hello', 2, 3);   /* valid: no NOTE, no _ERROR_ */
  if _error_ then put 'BAD-flag';
  else put 'clean';
  put "d=[" d "]";
run;
