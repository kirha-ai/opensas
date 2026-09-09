/* BUG-combcallcrash: a huge / non-finite count or k passed to a combinatorics
   CALL routine used to panic (`integer part of floating point value out of
   bounds`) on the unguarded `@intFromFloat`. Now routed through fns.toInt: an
   out-of-range count clamps to the last item, k to a no-op — no crash. A normal
   small call in the same step proves the guard didn't break the happy path. */
data _null_;
  /* out-of-range counts: must not crash, clamp to the last arrangement */
  a=1; b=2; c=3;
  call allcomb(1e300, 2, a, b, c);
  put "allcomb-big " a= b= c=;

  x1=1; x2=2; x3=3;
  call allperm(1e300, x1, x2, x3);
  put "allperm-big " x1= x2= x3=;

  p=1; q=2; r=3;
  call lexperk(1e300, 2, p, q, r);
  put "lexperk-big " p= q= r=;

  /* huge k is a no-op (k>n), not a trap */
  m=5; n=6;
  call allcomb(1, 1e300, m, n);
  put "allcomb-bigk " m= n=;

  /* happy path unchanged: 1st 2-combination of {7,8,9} is {7,8} */
  s=7; t=8; u=9;
  call allcomb(1, 2, s, t, u);
  put "allcomb-ok " s= t= u=;
run;
