/* GAP-mortnonote: out-of-range MORT args now log the invalid-argument NOTE
   (doc p.1215) and return missing — the NOTE is on stderr, so it is asserted
   via captured diagnostics in finfns.zig's test block; this fixture pins that
   the RESULTS are missing and valid calls are unchanged. */
data _null_;
  x = mort(100000, 500, 0.10, .);   /* payment < per-period interest: NOTE + . */
  y = mort(50000, ., 0.10/12, 360); /* p.1215's printed result: payment=438.79 */
  z = mort(1000, ., -2, 12);        /* rate <= -1: NOTE + . */
  w = mort(1000, ., 0.01, -5);      /* n < 0: NOTE + . */
  put x= y= z= w=;
run;
