/* QA regression: @intFromFloat / loop-overflow guards must return missing
   (or empty/0), never panic or hang, on huge/non-finite args. Sites once
   crashed: juldate/gcd/fact/anyalnum/choosen/scan/find (functions.zig). */
data _null_;
  a = juldate(1e300);
  b = gcd(1e300, 6);
  c = fact(1e300);
  d = fact(1e6);
  e = comb(5, 1e300);
  f = choosen(1e300, 1, 2);
  g = datejul(1e300);
  h = week(1e300);
  i = anyalnum("hello", 1e300);
  j = find("hi", "i", 1e300);
  k = scan("a b c", 1e300);
  put "a=" a;
  put "b=" b;
  put "c=" c;
  put "d=" d;
  put "e=" e;
  put "f=" f;
  put "g=" g;
  put "h=" h;
  put "i=" i;
  put "j=" j;
  put "k=[" k "]";
run;
