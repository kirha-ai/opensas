/* NOTE-overflownonote (tick183): numeric overflow collapsed to missing with NO
   NOTE while 6/0 noted — inconsistent. Overflow now emits the same math-domain
   NOTE domErr uses ("<op>: argument out of domain (result set to missing)") on
   stderr — asserted via captured diagnostics in the functions.zig/eval.zig
   test blocks; this fixture pins that the RESULTS stay missing and that normal
   values are unchanged (no spurious NOTE path is taken). */
data _null_;
  ex = exp(710);     /* fn overflow: NOTE + . */
  ov = 2**1024;      /* pow overflow: NOTE + . */
  om = 1e308*10;     /* mul overflow: NOTE + . */
  q  = 6/0;          /* div-by-zero: its own NOTE + . (unchanged) */
  e1 = exp(1);       /* control: 2.7182818285, no NOTE */
  p  = 2**10;        /* control: 1024, no NOTE */
  d  = 6/2;          /* control: 3, no NOTE */
  put ex= ov= om= q= e1= p= d=;
run;
