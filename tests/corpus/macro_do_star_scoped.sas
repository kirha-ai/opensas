/* BUG-macrodoscoped: a %do bound left unresolved errors LOUD (non-zero exit,
   BUG-macrodounresolved) but is MACRO-scoped, as in real SAS ("the macro will
   stop executing") — later independent steps still run. Regression source:
   A real XPT-creation program ends with a star-commented call *%XPT_CREAT(...)
   which real SAS (and opensas) still expands; its &nb is unset at include time.
   Treating that as a STEP error put the whole autoexec in syntax-check mode and
   took the study meter 26/27 -> 0/27 (every dataset "missing").
   expect-rc: 1 */
%macro xptlike;
  %do i=1 %to &nb.;
    %put ITER=&i;
  %end;
%mend xptlike;
*%xptlike;
data a;
  x = 42;
run;
data _null_;
  set a;
  put "AFTER x=" x;
run;
