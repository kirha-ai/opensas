/* BUG-macroquotemask: the &/% MASKING that macro quoting fns perform.
   F1 %SUPERQ masks EVERY &/% in the fetched value (same sentinels as %nrstr) so a
      later reference can never re-resolve them; a value w/o specials is verbatim.
   F2 %QSYSFUNC masks its RESULT (Q = quote) so a returned &/% survives a later
      reference; %SYSFUNC UNMASKS masked &/% in its args so the real function sees
      the true characters. Plain %sysfunc of plain args is unchanged.
   All three are SILENT-WRONG re-resolution / mask-leak defects. Expected values
   are SAS 9.4. %put lines land in the log; the DATA step puts hit stdout for the
   diff. Synthetic. macro-quotemask. */

%let inner = WORLD;

/* F1 — %SUPERQ masks a raw (unmasked) & fetched from the symbol table, so the
   later &g reference does NOT re-resolve &inner to WORLD. */
data _null_; call symput('raw', '&inner'); run;
%let g = %superq(raw);

/* F1 — %SUPERQ of a value WITHOUT specials returns it verbatim (preserve). */
%let plain = HELLO;
%let gp = %superq(plain);

/* F2 — %QSYSFUNC masks its result: byte(38) returns '&', which must stay masked
   so the trailing x is NOT read as a macro reference (&x would give ZZZ). */
%let x = ZZZ;
%let q = %qsysfunc(byte(38))x;

/* F2 — %SYSFUNC unmasks a %nrstr-masked arg so rank() sees the real '&' (=38),
   not the mask sentinel byte. Plain upcase of plain args is unchanged. */
%let ra = %sysfunc(rank(%nrstr(&)));
%let up = %sysfunc(upcase(abc));

data _null_;
  length s $20;
  s = "&g";  put "SUPERQ_MASK=[" s "]";
  s = "&gp"; put "SUPERQ_PLAIN=[" s "]";
  s = "&q";  put "QSYSFUNC_MASK=[" s "]";
  s = "&ra"; put "SYSFUNC_UNMASK=[" s "]";
  s = "&up"; put "SYSFUNC_PLAIN=[" s "]";
run;
