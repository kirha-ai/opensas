/* BUG-wherefunc (where= option half): a where= predicate calling a function
   silently misfiltered — no call_fn wired, errors sunk into a local diags, so
   upcase(...) evaluated to missing (char compares passed EVERY row, numeric
   compares dropped every row), exit 0. A real SDTM DD program's
   `where strip(upcase(AEOUT))="FATAL"` returned 2294 rows instead of 2. */
data src;
  length out $12;
  out = "Fatal";    output;
  out = "RECOVERED"; output;
run;
data a; set src(where=(strip(upcase(out)) = "FATAL")); run;
proc print data=a noobs; run;
data b; set src(where=(length(out) > 6)); run;
proc print data=b noobs; run;
