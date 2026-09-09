/* BUG-percentfit: PERCENT/NEGPAREN/E overflowed the field when the natural
   form was wider than w. SAS reduces decimals to fit, then fills with `*`. */
data _null_;
  b = 123.456;  put "pct_over=[" b percent6.2 "]";  /* 12345.60% → 12346% */
  d = 12345678; put "negp_over=[" d negparen6. "]"; /* 12,345,678 → ****** */
  x = 5e-324;   put "e_over=[" x e8.5 "]";          /* 4.94066E-324 → 4.9E-324 */
  y = -1234;    put "e_stars=[" y e5. "]";          /* no E-body fits → ***** */
  a = 0.1234;   put "pct_in=[" a percent6.1 "]";    /* in-width: unchanged */
  n = -1234;    put "negp_in=[" n negparen10. "]";  /* in-width: unchanged */
run;
