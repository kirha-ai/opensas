/* GAP-putnumliteral: a bare NUMERIC literal is a valid PUT value operand and may
   carry a trailing format (SAS formats/writes it). Was ParseError. Regressions:
   variable+format and a plain string literal still work. Verified vs SAS 9.4:
   best8. right-justifies in width 8; 5.2 gives " 3.14". (no PHI) */
data _null_;
  x = 7;
  put 42 best8.;
  put 3.14 5.2;
  put 42;
  put x best8.;
  put "hi";
run;
