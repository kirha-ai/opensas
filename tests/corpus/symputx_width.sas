/* BUG-symputxwidth: CALL SYMPUTX of a NUMERIC converts via BEST32. — values
   past 12 significant digits keep full precision (no BEST12. truncation, no
   E-notation). CALL SYMPUT keeps BEST12. + leading blanks (BUG-symputnumfmt). */
data _null_;
  call symputx('b', 123456789012345);
  call symputx('p', 3.14159265358979);
  call symputx('n', 1);
  call symput('o', 42);
run;
data _null_;
  b = symget('b');
  p = symget('p');
  n = symget('n');
  o = symget('o');
  put '>' b '<';
  put '>' p '<';
  put '>' n '<';
  put '>' o $char12. '<';
run;
