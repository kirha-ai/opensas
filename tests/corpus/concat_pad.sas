/* BUG-concatnopad: `||` on a fixed-length char VARIABLE pads the operand to
   its declared length (trailing blanks included) before concatenating —
   Language Reference: Concepts p.49: that padding is exactly why TRIM is needed. A literal keeps its
   own width; only declared char variables pad. */
data _null_;
  length t $5; t = "fox";
  c = t || "!"; n = length(c); nc = lengthc(c);
  put "len=" n " lenC=" nc " val=<" c ">";
  length a $3 b $3; a = "x"; b = "y";
  d = a || b; e = length(d); ec = lengthc(d);
  /* d stores "x  y  " (6 bytes incl. padding); LENGTH() trims trailing blanks
     (4), LENGTHC() counts them (6) — both observe the padding. */
  put "abcat=<" d "> len=" e " lenC=" ec;
  /* literal operands are NOT padded; explicit blanks survive as-is */
  lit = "a " || "b"; m = length(lit);
  put "lit=<" lit "> len=" m;
  /* an undeclared-width char var keeps its raw stored value */
  plain = "xy"; p = plain || "!"; q = length(p);
  put "plain=<" p "> len=" q;
  /* trim() still strips the padding — the SAS idiom keeps working */
  tr = trim(t) || "!"; z = length(tr);
  put "trim=<" tr "> len=" z;
run;
