/* GAP-infileeov — INFILE EOV=variable is a documented SAS 9.4 option
   (printed p.130, marker "=== pdf 141 ===": "specifies a variable that SAS
   sets to 1 when the first record in a file in a series of concatenated
   files is read") opensas has not implemented. Valid SAS refused → an
   opensas GAP, exit 2 (D-009/D-009b(i)); it used to exit 1 via the typo
   catch-all. Message text byte-identical to the rc-1 arm; only the rc
   moves. The typo control (`eovv=`) keeps rc 1 — pinned in the parser.zig
   D-009 test. Parse-time failure → empty golden; the rc is the pin.
   expect-rc: 2 */
data _null_;
  infile datalines eov=v;
  input a $6.;
  datalines;
r1aaaa
;
run;
