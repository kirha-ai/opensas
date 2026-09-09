/* NOTE-substrlenpastend: SUBSTR (read) with a positive LENGTH that runs past the
   end of the string is invalid in SAS 9.4 — it logs a NOTE (3rd arg invalid) and
   sets _ERROR_=1, while still returning the clamped remainder. Sibling of
   NOTE-substrpastend (position past end). Exact fit and no-length stay clean.
   Ref: SAS 9.4 Functions Reference, SUBSTR (p.1533). */
data _null_;
  x = substr('abc', 2, 5);  /* length past end: bc, NOTE, _ERROR_=1 */
  e1 = _error_;
  put "x=[" x "]";
  put "e1=" e1;
run;
data _null_;
  y = substr('abc', 2, 2);  /* exact fit: bc, _ERROR_ stays 0 */
  e2 = _error_;
  z = substr('abc', 2);     /* no length: bc, _ERROR_ stays 0 */
  e3 = _error_;
  put "y=[" y "]";
  put "e2=" e2;
  put "z=[" z "]";
  put "e3=" e3;
run;
