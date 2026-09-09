/* PICTURE-format: numeric digit-selector pictures + PREFIX/MULT.
   SAS 9.4 selector rule (BUG-picturedigitsel): a `0` selector SUPPRESSES
   leading zeros (prints a blank); a NONZERO selector (e.g. `9`) PRINTS
   leading zeros — "nines print zeros, zeros suppress".
   MULT scales the value first; PREFIX is prepended. */
proc format;
  picture pp 0-999='009';                              /* 42 -> ` 42` (0s suppress) */
  picture zs low-high='999';                           /* 42 -> `042` (9s zero-fill) */
  picture dol low-high='000009' (prefix='$' mult=100); /* 12.5 -> `$  1250` */
  picture pz low-high='0000';                          /* 7 -> `   7`, 700 -> ` 700` */
  picture pn low-high='9999';                          /* 7 -> `0007`, 700 -> `0700` */
run;
data _null_;
  x = 42;
  put x pp.;
  put x zs.;
  y = 12.5;
  put y dol.;
  do x = 7, 70, 700;
    put x pz.;
    put x pn.;
  end;
run;
