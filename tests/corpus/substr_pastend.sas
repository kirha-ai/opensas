/* NOTE-substrpastend: SUBSTR (read direction) with a start position PAST the end
   of the string is invalid in SAS 9.4 — it logs a NOTE (2nd arg invalid) and sets
   _ERROR_=1, while still returning blank. Mirrors the nonpositive-position branch
   (substr_posclamp). Ref: SAS 9.4 Functions Reference, SUBSTR (p.1533). */
data _null_;
  x = substr('hello', 10);   /* past end: blank, NOTE, _ERROR_=1 */
  e1 = _error_;
  put "x=[" x "]";
  put "e1=" e1;
run;
data _null_;
  y = substr('hello', 2, 3); /* valid control: ell, _ERROR_ stays 0 */
  e2 = _error_;
  put "y=[" y "]";
  put "e2=" e2;
run;
