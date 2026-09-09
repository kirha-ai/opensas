/* BUG-symputnumfmt: CALL SYMPUT of a NUMERIC converts via BEST12. — right-
   justified in a 12-char field (leading blanks), stored UNtrimmed, plus a
   num→char NOTE in the log. Only CALL SYMPUTX trims. (%put writes to the
   log, so the width is shown via PUT + length().) */
data _null_;
  call symput('m', 42);
  call symputx('x', 42);
run;
data _null_;
  v = symget('m');
  put '>' v $char12. '<';
  l = length(v);
  put l=;
  w = symget('x');
  put '>' w $char12. '<';
  lw = length(w);
  put lw=;
run;
