/* CALL SYMPUT keeps trailing blanks; CALL SYMPUTX trims them. Classic scope/format edge. corpus-macroedge. */
data _null_;
  call symput("padded", "  hi  ");
  call symputx("trimmed", "  hi  ");
run;
data _null_;
  put "[&padded]";
  put "[&trimmed]";
run;
