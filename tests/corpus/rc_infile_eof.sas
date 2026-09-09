/* GAP-infileoptrc (3c) — INFILE EOF=variable is a documented SAS 9.4 option
   (printed p.130, marker "=== pdf 141 ===") opensas has not implemented, and
   it is the doc's own prescribed substitute where END= is invalid ("Use the
   option EOF= on page 130 when END= is invalid"). Valid SAS refused → an
   opensas GAP, exit 2 (D-009/D-009b(i)); it used to exit 1 via the typo
   catch-all. Message text byte-identical to the rc-1 arm; only the rc moves.

   ORDERING (from docs/findings/oracle-unblocked-readings.md item 3): the
   future revert of BUG-infileendmultirec (3a — END= never set to 1 for
   instream DATALINES, exec.zig, NOT this commit) must not land before this
   one does, or instream data would have no working end-of-file idiom at
   all (END= dead, EOF= still rc-1-rejected). This commit lands 3b/3c first,
   so that constraint is satisfied and 3a is unblocked.

   Parse-time failure → empty golden; the rc is the pin.
   expect-rc: 2 */
data _null_;
  infile datalines eof=done;
  input a $6.;
  datalines;
r1aaaa
;
run;
