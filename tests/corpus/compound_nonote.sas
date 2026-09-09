/* GAP-compoundnonote: out-of-range COMPOUND args now log the invalid-argument
   NOTE (Functions and CALL Routines: Reference p.544) and return missing — the
   NOTE is on stderr, so it is asserted via captured diagnostics in numfns.zig's
   test block; this fixture pins that the RESULTS are missing and valid calls are
   unchanged. The valid call keeps the manual's printed arguments because its
   result (1225.68) is the oracle. */
data _null_;
  badrate = compound(1000, ., -0.05, 12);  /* negative rate: NOTE + . */
  future  = compound(500, ., 0.09/12, 120); /* manual's printed result: f=1225.68 */
  badamt  = compound(-1000, ., 0.05, 12);  /* negative amount: NOTE + . */
  badn    = compound(1000, ., 0.05, -2);   /* negative n: NOTE + . */
  zeroamt = compound(0, ., 0.05, 12);      /* a=0 is valid: 0 */
  put badrate= future= badamt= badn= zeroamt=;
run;
