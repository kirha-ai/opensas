/* BUG-dsddoublequote: the FILE DSD writer escapes an embedded quote as "" and
   quotes a value containing the delimiter (Language Reference: Concepts Table 21.4 p.509) — so the
   INFILE DSD reader must collapse "" back to one " and keep every following
   field aligned. The file opensas writes, opensas reads back unchanged.
   (PROC IMPORT's reader already had this rule; INFILE DSD was the lone holdout.) */
data src;
  length s q $12;
  s = 'a"b'; q = 'x,"y",z'; n = 5; output;
  s = 'plain'; q = ''; n = 7; output;
run;
data _null_;
  set src;
  file ".zig-cache/dsd_quote_roundtrip.csv" dsd;
  put s n q;
run;
data back;
  infile ".zig-cache/dsd_quote_roundtrip.csv" dsd truncover;
  length s2 q2 $12;
  input s2 $ n2 q2 $;
run;
data _null_;
  set back;
  put 's2=[' s2 '] n2=' n2 ' q2=[' q2 ']';
run;
