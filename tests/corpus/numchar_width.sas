/* BUG-numcharwidth: SAS AUTOMATIC num->char conversion renders BEST12.
   (expression context) / BESTn. (assignment to a length-n char var),
   RIGHT-JUSTIFIED in the field (Language Reference: Concepts p.124). Brackets expose the padding.
   Explicit conversions (put with a format) keep their current behavior;
   the conversion NOTEs go to stderr (not this stdout diff). */
data _null_;
  length c20 $20 c8 $8;
  n = 5;
  s = n || "x";           put "concat=[" s "]";
  c20 = n;                put "assign20=[" c20 "]";
  c8 = n;                 put "assign8=[" c8 "]";
  big = 123456789012;     b1 = big || "!";   put "big=[" b1 "]";
  huge = 1234567890123;   b2 = huge || "!";  put "huge=[" b2 "]";
  small = 0.000123;       b3 = small || "!"; put "small=[" b3 "]";
  tiny = 1e-11;           b4 = tiny || "!";  put "tiny=[" b4 "]";
  neg = -42;              b5 = neg || "!";   put "neg=[" b5 "]";
  dec = 3.25;             b6 = dec || "!";   put "dec=[" b6 "]";
  third = 1/3;            b7 = third || "!"; put "third=[" b7 "]";
  m = .;                  b8 = m || "!";     put "miss=[" b8 "]";
  k = .K;                 b9 = k || "!";     put "special=[" b9 "]";
  l = length(n);          put "lengthfn=" l;
  t = trim(n);            put "trim=[" t "]";
  lft = left(n);          put "left=[" lft "]";
  ep = put(n, 8.);        put "explicit_put=[" ep "]";
  eb = put(n, best12.);   put "explicit_best=[" eb "]";
run;
