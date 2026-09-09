/* GAP-infileoptrc (3b) — INFILE UNBUFFERED is a documented SAS 9.4 option
   (DATA Step Statements: Reference, printed p.138, marker "=== pdf 149 ===";
   alias UNBUF, "UNBUFFERED on page 138" cross-referenced from p.130) that
   opensas has not implemented. Valid SAS refused → an opensas GAP, exit 2
   ("file an opensas issue", D-009/D-009b(i)) — it used to take the rc-1
   typo catch-all ("fix your SAS" about SAS that is fine). Split, not
   re-tagged: a misspelling like `unbuff` still lands on the same ERROR text
   at rc 1 (pinned in-source, parser.zig D-009 test), and the message text
   itself is byte-identical on both arms — only the rc signal moves.

   Parse-time failure → no step runs → the golden is empty; the rc is the
   pin, checked through the real CLI exit path (fixture_rc.zig).
   expect-rc: 2 */
data _null_;
  infile "f" unbuffered;
  input a $1.;
run;
