/* BUG-fileopts: FILE options were silently swallowed — `file "x" dlm="," dsd;`
   wrote space-separated output with NO diagnostic. Now DLM sets the PUT list
   separator and DSD quotes values containing the delimiter (SAS DSD semantics).
   The file lands in .zig-cache and is read back via INFILE into the log so the
   expected .txt pins the bytes exactly. */
data _null_;
  file ".zig-cache/file_dlm_dsd_out.csv" dlm="," dsd;
  a = 1; b = 2; c = 3;
  put a b c;
  x = "with,comma"; y = "plain";
  put x y;
run;
data _null_;
  infile ".zig-cache/file_dlm_dsd_out.csv";
  input;
  put _infile_;
run;
