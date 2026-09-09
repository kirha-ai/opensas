/* audit-tick: step_boundary — a DATA step is also implicitly ended by the next
   DATA/PROC statement (no explicit RUN; required). */
data a; x = 1;
proc print data=a; run;
