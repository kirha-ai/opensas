/* QA tick152 — regression lock for BUG-percentfit reduce-then-asterisk ladder.
   PERCENT/NEGPAREN/E must fit the field: reduce decimals, else fill with `*`;
   in-width forms stay byte-identical. Pins the re-pinned denormal E outputs. */
data _null_;
  /* PERCENT: zero, negatives, reduce-to-fit, overflow-to-stars */
  p0=0;       put "p0["   p0  percent6.1  "]";
  pn=-0.05;   put "pn["   pn  percent8.1  "]";
  pnr=-0.05;  put "pnr["  pnr percent5.1  "]";
  pov=123.456;put "pov["  pov percent6.2  "]";
  povn=-123.456; put "povn[" povn percent6.2 "]";
  /* NEGPAREN: zero, negative in-width, positive reserved blank, stars */
  z0=0;       put "z0["   z0  negparen8.2 "]";
  zn=-1234;   put "zn["   zn  negparen10. "]";
  zp=1234;    put "zp["   zp  negparen10. "]";
  zov=12345678; put "zov[" zov negparen6.  "]";
  /* E across magnitudes incl the two re-pinned denormals + explicit-d reduce */
  e0=0;       put "e0["   e0  e10.3  "]";
  ebig=12345.678; put "ebig[" ebig e12.4 "]";
  edn1=5e-324;    put "edn1[" edn1 e8.5 "]";
  edn2=1e-323;    put "edn2[" edn2 e15.10 "]";
  ered=3.14159;   put "ered[" ered e6.2 "]";
  estar=-1234;    put "estar[" estar e5. "]";
run;
