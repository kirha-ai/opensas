/* GAP-ebnfholes-tick356 — INFILE PAD is a documented SAS 9.4 option
   (DATA Step Statements: Reference, printed p.135, marker "=== pdf 146 ===":
   "PAD | NOPAD controls whether SAS pads the records that are read ... with
   blanks to the length that is specified in the LRECL= option") that opensas
   has not implemented. Valid SAS refused → an opensas GAP, exit 2 ("file an
   opensas issue", D-009/D-009b(i)) — it used to take the rc-1 typo catch-all
   ("fix your SAS" about SAS that is fine). Split, not re-tagged: a
   misspelling like `padd` still lands on the same ERROR text at rc 1, and
   NOPAD — the documented DEFAULT of the same entry — is accepted-inert
   (rc 0), all three arms pinned in-source (parser.zig D-009 test). PAD stays
   loud rather than accept-and-ignore on purpose: it pads to LRECL=, which
   is itself an accept-and-ignore no-op here, so there is nothing to pad TO
   (BUG-infilepadinert — loud beats lying).

   Parse-time failure → no step runs → the golden is empty; the rc is the
   pin, checked through the real CLI exit path (fixture_rc.zig).
   expect-rc: 2 */
data _null_;
  infile "f" pad;
  input a $1.;
run;
