/* BUG-doblocksourceinert (QA tick307 F1c — the WORST variant): with an ARRAY
   statement in the block, the fabricated row carried the ARRAY's column NAMES
   in the array's order with all-missing values, so a downstream PROC saw a
   well-formed 1-obs dataset and could not tell anything went wrong — the
   silent-wrong failure class CLAUDE.md names the worst. With the .do_ arm the
   SET really reads, so the array references see real values: 2 obs with the
   source's data, not 1 fabricated all-missing obs. */
data a; input k x c $; datalines;
1 10 aa
2 20 bb
;
run;

data o;
  if 1 then do;
    set a;
    array ar{2} k x;
    ar{1} = ar{1}; /* touch the array, like QA's repro */
  end;
run;
proc print data=o noobs; run;
