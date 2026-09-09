/* CALL SYMPUT var is NOT visible to &ref compiled in the SAME data step (the var
   does not exist until the step runs); it IS visible in the NEXT step. corpus-macroedge. */
data _null_;
  call symput("n", "42");
  x = "&n";
  put "same-step=[" x "]";
run;
data _null_;
  put "next-step=[&n]";
run;
