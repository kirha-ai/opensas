/* BUG-filenameconcatnoop (Language Reference: Concepts Table 21.5, p.517: "FILENAME statement with
   concatenation, wildcard, or piping"): `filename ref ('a.txt' 'b.txt');` was
   silently accepted and registered NOTHING — the later INFILE then errored
   "expected an infile path" byte-identically to an UNDEFINED fileref, pointing
   the user at the wrong statement two lines down. The sibling `pipe` device on
   the same table row already failed loud. No concatenation engine exists, so
   the FILENAME statement itself now refuses clearly:
   "ERROR(L1): FILENAME concatenation (a parenthesised list of files) is not
   supported" (stderr). stdout pins that nothing runs after the bad statement.
   expect-rc: 2 */
data _null_;
  put "BEFORE: runs";
run;

filename both ('nonexistent_a.txt' 'nonexistent_b.txt');

data _null_;
  infile both;
  input k $ v;
run;

data _null_;
  put "AFTER: must not print";
run;
