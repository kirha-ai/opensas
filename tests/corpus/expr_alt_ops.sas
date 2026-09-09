/* GAP-whereorbang (+ not_expr sibling): `!` / `¦` are alternate spellings of
   the OR operator `|` and `¬` an alternate NOT (Language Reference: Concepts Table 6.6 Groups VI/VII)
   — previously not lexed at all, so legal SAS failed loud. Lexer aliases them
   to the existing pipe/caret tokens; the DOUBLES (`!!`, `¦¦`) stay concat. */
data _null_;
  a = 1; b = 0;
  if a ! b then put "bang-or";
  if a ¦ b then put "brokenbar-or";
  if a | b then put "pipe-or";
  if ¬b then put "notsign-not";
  if ^b then put "caret-not";
  if ~b then put "tilde-not";
  /* doubles are still the concatenation operator */
  x = "p" !! "q";  put "bangconcat " x=;
  y = "p" ¦¦ "q";  put "bbconcat " y=;
  z = "p" || "q";  put "pipeconcat " z=;
run;

/* same spellings in a WHERE filter */
data d;
  input a b c;
  datalines;
1 0 5
0 0 9
;
run;

data _null_;
  set d;
  where a ! b;
  put "w-bang " c=;
run;

data _null_;
  set d;
  where a ¦ b;
  put "w-bb " c=;
run;

data _null_;
  set d;
  where ¬(a = 9);
  put "w-not " c=;
run;
