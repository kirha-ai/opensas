/* BUG-macropow: %eval/%sysevalf support `**` (exponentiation) in SAS 9.4 —
   it used to parse as `* <garbage>` and degrade to 0. Binds tighter than
   unary minus (-2**2 = -4), right-associative (2**3**2 = 512), saturating. */
%put a=%eval(2**10);
%put b=%eval(-2**2);
%put c=%eval(2**3**2);
%put d=%eval(2*3**2);
%put e=%eval(2**-1);
%put f=%sysevalf(2**0.5);
%put g=%sysevalf(2**-1);
%if %eval(2**10) = 1024 %then %put IF-OK;
