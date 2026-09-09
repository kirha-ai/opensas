/* GAP-lengthc-declared: LENGTHC of a declared-width var returns the DECLARED
   width (incl. trailing blanks); LENGTH returns the trimmed used length. */
data _null_;
  length s $5;
  s='ab';
  lc = lengthc(s);        /* 5 — declared width */
  ln = length(s);         /* 2 — trimmed used length (unaffected) */
  le = lengthc('abc');    /* 3 — value-based (non-var arg) */
  x='hello';
  lx = lengthc(x);        /* 5 — no declared LENGTH, value width */
  put "lengthc_var=" lc " length_var=" ln " lengthc_expr=" le " lengthc_nolen=" lx;
run;
