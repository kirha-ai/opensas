/* QA tick356 F4: INPUT(c, 8.) logged a bogus "Numeric values have been converted
   to character values" NOTE — the unfixed twin of BUG-putbarenumnote. The bare `8.`
   informat is a SPEC, not data, so coercing it must be silent; the NOTE was a false
   positive on the one function whose entire purpose is an explicit conversion.
   Only the BARE spelling tripped it — a named informat (best8.) was always silent —
   so both spellings are pinned here, for INPUT and its INPUTN/INPUTC variants and
   for the PUT side that was already fixed.
   The corpus compares stdout and the NOTE goes to stderr, so the values below are
   the regression guard; the log itself is asserted in functions.zig's
   `test "QA tick356 F4"` via the captured diagnostics reporter (D-003). */
data _null_;
  bare  = input("123", 8.);      /* the reported shape */
  named = input("123", best8.);  /* always silent — must stay identical */
  n     = inputn("456", 8.);
  c     = inputc("xy", $2.);
  pbare = put(789, 8.);          /* BUG-putbarenumnote, already fixed */
  pname = put(789, best8.);
  put bare= named= n= c= pbare= $quote. pname= $quote.;
run;
