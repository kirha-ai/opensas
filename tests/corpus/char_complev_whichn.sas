/* BUG-complev-modifiers + BUG-whichnmissing + GAP-collate (charfns.zig).
   COMPLEV must honor its modifier arg (i ignore-case, l trim-leading-blanks,
   : truncate to shorter) exactly like COMPGED, and still accept a numeric
   cutoff in any position. WHICHN/WHICHC must return missing when the search key
   is missing. COLLATE single-arg runs to the end of the sequence, and the
   3-arg (start,,length) form is supported. */
data _null_;
  /* --- COMPLEV modifiers --- */
  ci = complev('CAT','cat','i');       put "ci="   ci;   /* 0: ignore case */
  cl = complev('  cat','cat','l');     put "cl="   cl;   /* 0: trim leading blanks */
  cil= complev('CAT','cat',5,'i');     put "cil="  cil;  /* 0: cutoff 5 + i */
  cn = complev('cat','cot');           put "cn="   cn;   /* 1: no modifier, one sub */
  cc = complev('baboon','baby',2);     put "cc="   cc;   /* 2: cutoff caps 3 */

  /* --- WHICHN / WHICHC missing key --- */
  xn = whichn(., 1492, 1066, ., 1450); put "xn="   xn;   /* . : missing key */
  xc = whichc('', 'a', '', 'b');       put "xc="   xc;   /* . : missing key */
  yn = whichn(1066, 1492, 1066, 1450); put "yn="   yn;   /* 2: real hit */

  /* --- COLLATE --- */
  length k $10 ka $200;
  k = collate(48,,10);                 put "k=[" k "]"; /* 0123456789 */
  ka = collate(65);                                     /* A..end of sequence */
  kalen = length(ka);                  put "kalen=" kalen;      /* 191 */
  put "kahead=" ka $char3.;                                     /* ABC */
run;
