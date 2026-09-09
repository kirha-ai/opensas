/* BUG-charfmtonnum: a `$` (character) format applied to a NUMERIC value must
   FAIL LOUD — SAS 9.4 raises a compile-time error (a character format cannot
   be used with a numeric variable) where opensas silently coerced the number
   to text (D-002). The ERROR goes to stderr (+ non-zero exit); stdout keeps
   the loud-then-fallback raw render, so the 3rd PUT prints the raw value.
   No false positives: the SAME $ format on a CHAR value renders its label,
   and a numeric format on the numeric value works.
   The "+ non-zero exit" above is now PINNED, not just asserted in prose: a
   format/type clash is the user's SAS being wrong, so D-009 says 1, not 2
   (2a57cc33, main.zig 2374/2376).
   expect-rc: 1 */
proc format;
  value $ny 'N'='No' 'Y'='Yes';
run;
data _null_;
  x = 5;
  c = 'Y';
  put c $ny.;   /* char value + char format: label renders, no error */
  put x 8.2;    /* numeric format on numeric: fine */
  put x $ny.;   /* char format on NUMERIC: ERROR to stderr, exit 1 */
run;
