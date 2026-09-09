/* BUG-comboverflow: comb(n,r) returned MISSING when the true binomial fits in an
   f64, because it built the full descending numerator (~10^1150 -> +inf) before
   dividing by r!. comb2 now uses the interleaved product (n-r+i)/i with r=min(r,n-r)
   so partial products never exceed the answer. comb(1000,500) is representable
   (~2.7e299) and must NOT be missing. Small cases stay exact. */
data _null_;
  big = comb(1000,500);
  put big= best20.;        /* representable ~2.7e299, not missing */
  a = comb(5,2);  put a=;  /* 10 */
  b = comb(52,5); put b=;  /* 2598960 */
  c = comb(10,10); put c=; /* 1 */
  d = comb(6,3);  put d=;  /* 20 */
run;
