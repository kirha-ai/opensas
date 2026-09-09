/* BUG-attrboundssilent (4a, char arm) — LENGTH Statement, SAS 9.4 DATA Step
   Statements: Reference printed p.217 (marker "=== pdf 228 ==="): "For
   character variables, 1 to 32767 bytes under ALL operating environments."
   The floor is universal — the old "minimum is platform-dependent" comment in
   checkDeclLen quoted that very sentence and parked it anyway.

   Measured before the fix (clean build at 9f9958ea): `length c $0` was
   accepted SILENTLY at rc 0 and the descriptor then took the assigned value's
   width — `c='hi'` reported Char 2 in PROC CONTENTS, not even the Char 1
   tick272 recorded. No check PLUS a fabricated width. An out-of-range length
   is a malformed program → rc 1 (D-009b(ii)), never a silent accept.

   The legal edge ($1) is pinned green by attr_bounds_doc.sas, which must not
   move. Parse-time failure → no step runs → the golden is empty; the rc is
   the pin. Message text is pinned in-source (parser.zig test).
   expect-rc: 1 */
data t;
  length c $0;
run;
