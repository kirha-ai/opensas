/* BUG-retainspecial / BUG-keepdropspecial: `_ALL_`/`_NUMERIC_`/`_CHARACTER_` in
   RETAIN and KEEP/DROP are special name lists resolved against the PDV (the same
   expansion ARRAY uses, GH#48) — not literal variable names. Was: a bogus
   `_numeric_` column with the intended vars unretained, `keep _numeric_` keeping
   NOTHING plus a misleading "never referenced" warning, `drop _character_`
   dropping nothing. */

/* retain _numeric_ 0: x/t accumulate (retained + seeded 0), the char var s is
   NOT retained, and no `_numeric_` column may appear. */
data a;
  retain _numeric_ 0;
  input c $ x;
  t = t + x;
  s = cats(s, c);
  datalines;
p 1
q 2
;
run;

proc print data=a; run;

/* retain _all_ 0: every var retained and seeded (numeric-only PDV here). */
data a2;
  retain _all_ 0;
  x = x + 1;
  y = y + 2;
  output;
run;

proc print data=a2; run;

/* keep _numeric_: keeps the numerics only — c/s dropped, no bogus warning. */
data b;
  set a;
  keep _numeric_;
run;

proc print data=b; run;

/* drop _character_: drops c/s, keeps the numerics. */
data d;
  set a;
  drop _character_;
run;

proc print data=d; run;

/* keep _character_: the char mirror. */
data e;
  set a;
  keep _character_;
run;

proc print data=e; run;
