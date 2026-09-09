/* BUG-lcmoverflow + BUG-convxfreq (doc-finder tick277 F2/F1).
   LCM: lcm(8999999999999999, 8999999999999998) — consecutive ints are coprime,
   so LCM = a*b ~= 8.1e31. The u64 a/gcd*b multiply OVERFLOWED and PANICKED the
   interpreter (safe build: abort/core dump; the DATA step died mid-PUT).
   Now a checked multiply returns MISSING and the step RUNS TO COMPLETION.
   Small args unchanged: lcm(4,6)=12. GCD unaffected: gcd of the same pair = 1.
   CONVX: doc p.561 numerator weight is k(k+f), not k(k+1). Hand arithmetic for
   convx(0.1, 2, 100, 100):
     P   = 100*1.1^(-0.5) + 100*1.1^(-1)          = 186.2553498
     num = 1*3*100*1.1^(-0.5) + 2*4*100*1.1^(-1)  = 1013.3115040
     C   = 1013.3115040 / (186.2553498*1.1^2*2^2) = 1.1240583489
   f=1 is unchanged (k(k+1) == k(k+f)): convx(0.05,1,100) = 2/1.05^2. */
data _null_;
  big = lcm(8999999999999999, 8999999999999998);
  put big=;         /* missing — and this PUT is REACHED (no abort) */
  g = gcd(8999999999999999, 8999999999999998);
  put g=;           /* 1 */
  small = lcm(4, 6);
  put small=;       /* 12 */
  c2 = convx(0.1, 2, 100, 100);
  put c2= best12.;  /* 1.1240583489 */
  c1 = convx(0.05, 1, 100);
  put c1= best12.;  /* 1.8140589569 (f=1 unchanged) */
run;
