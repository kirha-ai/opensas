/* Floating-point sum displays cleanly under BEST (0.1+0.2 -> 0.3) */
data d;
  s = 0.1 + 0.2;
  t = 0.3;
  equal_display = (s = t);
  diff = s - t;
  put "s=" s " equal=" equal_display;
run;
