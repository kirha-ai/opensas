/* QA value-verification: SAS 32-bit bitwise ops, exact results incl the
   one's-complement wrap gotcha (BNOT(0)=2^32-1). Args are u32 in [0,2^32-1];
   out-of-domain (negative / >2^32-1 / non-finite) -> missing.

   NOTE-bitrangenote: those two out-of-domain rows (bandneg, bnotinf) also emit
   a NOTE and set _ERROR_=1 now — SAS 9.4 Functions and CALL Routines: Reference
   p.265–266 gives BAND "Range: An integer value between 0 and (2^32)-1 inclusive",
   and p.6 makes an argument outside a printed range invalid: note + _ERROR_=1 +
   missing. NOTE-bitshiftcount: the shift COUNT's documented range is 0–31
   (BLSHIFT p.278, BRSHIFT p.280), so blshift32/brshift33 below are missing +
   NOTE too (they used to silently mask & 31 into a plausible wrong shift).
   The VALUES above are unchanged and the diagnostics go to stderr, so this
   file's expected stdout only grows the two new missing rows — the flag is
   asserted in numfns.zig's test instead. */
data _null_;
  a=band(12,10); b=bor(12,10); c=bxor(12,10);
  d=bnot(0); e=bnot(15);
  f=blshift(1,31); g=brshift(4294967295,28);
  h=band(4294967295,255); i=bxor(4294967295,4294967295);
  j=band(-1,255); k=bnot(1e300);
  l=blshift(1,32); m=brshift(8,33);
  put "band=" a;
  put "bor=" b;
  put "bxor=" c;
  put "bnot0=" d;
  put "bnot15=" e;
  put "blshift=" f;
  put "brshift=" g;
  put "bandmax=" h;
  put "bxormax=" i;
  put "bandneg=" j;
  put "bnotinf=" k;
  put "blshift32=" l;
  put "brshift33=" m;
run;
