/* BUG-putdsdnewline: DATA-step `file ... dsd; put` wrote a char value with an
   embedded newline RAW, splitting ONE field across two output records and
   corrupting the delimited file (write-side twin of BUG-importdelimread). The
   DSD quote-trigger now also fires on \n / \r (mirroring appendCsvField /
   PROC EXPORT): the value is wrapped in quotes so the embedded LF stays
   inside ONE quoted field. The file lands in .zig-cache and is read back raw
   via INFILE / _INFILE_ so the expected .txt pins the bytes exactly: records
   1-2 are the quoted field's two physical halves (`"line1` / `line2",7`),
   record 3 is the embedded-comma control (still quoted, unchanged). (no PHI) */
data _null_;
  file ".zig-cache/put_dsd_newline_out.csv" dsd;
  length s $20;
  s = 'line1' || byte(10) || 'line2'; x = 7;
  put s x;
  c = "with,comma"; p = "plain";
  put c p;
run;
data _null_;
  infile ".zig-cache/put_dsd_newline_out.csv";
  input;
  put _infile_;
run;
