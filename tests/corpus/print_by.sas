/* PROCBY-printfreq regression guard: plain PROC PRINT BY keeps sectioning the
   listing per group now that its BY routes through the shared parseProcBy
   (which fails loud on DESCENDING/NOTSORTED). */
data d;
  do g = 1 to 2;
    do i = 1 to 2;
      x = g * 10 + i;
      output;
    end;
  end;
  drop i;
run;

proc print data=d; by g; run;
