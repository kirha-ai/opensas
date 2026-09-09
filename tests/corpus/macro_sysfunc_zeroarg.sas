/* %sysfunc with a zero-argument function (today()/date()/time()) — empty parens
   must pass NO args, not one empty arg. Deterministic guard. macro-sysfunc. */
data _null_;
  t = input("%sysfunc(today())", best12.);
  if t > 20000 then put "TODAY_ZEROARG=OK"; else put "TODAY_ZEROARG=FAIL";
  n = input("%sysfunc(datetime())", best12.);
  if n > 1700000000 then put "DATETIME_ZEROARG=OK"; else put "DATETIME_ZEROARG=FAIL";
run;
