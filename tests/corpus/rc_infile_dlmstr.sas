/* GAP-ebnfholes-tick356 — INFILE DLMSTR= is a documented SAS 9.4 option
   (DATA Step Statements: Reference, printed p.128, marker "=== pdf 139 ===";
   the doc self-confirms "DLMSTR= on page 128"): one multi-character
   delimiter string, where DLM= is a LIST of single-char delimiters
   (BUG-dlmmultichar). opensas has not implemented it. Valid SAS refused →
   an opensas GAP, exit 2 ("file an opensas issue", D-009/D-009b(i)) — it
   used to take the rc-1 typo catch-all. Split, not re-tagged: a
   misspelling like `dlmstrr` still lands on the same ERROR text at rc 1
   (pinned in-source, parser.zig D-009 test), and the message text is
   byte-identical on both arms — only the rc signal moves.

   Parse-time failure → no step runs → the golden is empty; the rc is the
   pin, checked through the real CLI exit path (fixture_rc.zig).
   expect-rc: 2 */
data _null_;
  infile "f" dlmstr='~!';
  input a $ b $;
run;
