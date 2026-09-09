/* Build a subject x visit grid with nested DO loops (multi-OUTPUT) */
data grid;
  do subj = 1 to 3;
    do visit = 1 to 2;
      USUBJID = subj;
      VISITNUM = visit;
      output;
    end;
  end;
  keep USUBJID VISITNUM;
run;
proc print data=grid; run;
