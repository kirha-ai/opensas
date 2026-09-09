/* BESTFMT-edge — premise-audit pin. The ticket claimed: "a non-integer
   rounding up to exactly 1e12 prints 13 chars vs `1E12`".
   Verdict: ALREADY FIXED BY 29cdfb55 (BUG-eformat) — fixedStr in format.zig
   falls back to E-notation when the rounded whole overflows w
   (999999999999.9 best12. -> 1E12, not 1000000000000), with unit tests at
   format.zig's bestNum. 54f92bba later kept the same behaviour through the
   i64-overflow-safe rewrite. This fixture pins the same through the PUT
   surface so a regression is visible end-to-end, not only in the unit test. */
data _null_;
  x = 999999999999.9; put x best12.;  /* rounds up to 1e12 -> 1E12   */
  y = 999999999999.5; put y best12.;  /* boundary            -> 1E12 */
  z = 999999999999.4; put z best12.;  /* control: fits, stays fixed  */
  w = 1e12;           put w best12.;  /* control: whole 1e12 -> 1E12 */
run;
