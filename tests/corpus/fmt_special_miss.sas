/* BUG-fmtspecialmissletter: a special missing .a-.z renders as the uppercase
   LETTER A-Z, ._ as _, and plain . stays . — in the default list PUT (BEST.)
   AND in an explicit Fw.d format, right-justified in the field. Regression
   guard for the render root that BUG-tabulatespecialmiss builds on. */
data _null_;
  x = .a; y = ._; z = .;
  put x= y= z=;
  put x 4.;
  put y 4.;
  put z 4.;
  put x 6.2;
run;
