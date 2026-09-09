/* BUG-fmtnumoverflow: HEX/BINARY/E numeric renderers aborted (SIGABRT) on valid
   finite doubles — |x| >= 2^64 for HEX(w<16)/BINARY, and the tiniest denormals
   for Ew. Guarded now: cap the field / finite-safe mantissa, never crash. */
data _null_;
  a = 1e300;  put "hex8:    [" a hex8. "]";
  b = -1e250; put "hex10:   [" b hex10. "]";
  c = 1e300;  put "bin16:   [" c binary16. "]";
  e = 1e100;  put "bin20:   [" e binary20. "]";
  f = 5e-324; put "e8.5:    [" f e8.5 "]";
  g = 1e-323; put "e15.10:  [" g e15.10 "]";
  h = 255;    put "hex8@255:[" h hex8. "]";
  i = 36.6;   put "hex16:   [" i hex16. "]";
run;
