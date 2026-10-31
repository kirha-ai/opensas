/* GAP-macrooptfamily — HONOURED: NOMREPLACE (Macro Ref ch.20 p.478, default
   MREPLACE) refuses to REDEFINE an already-compiled macro. Oracle probe
   2026-10-31 (real SAS 9.4): the second %macro draws
     ERROR: The macro M1 will not be compiled because the NOMREPLACE option
     is set.  Source code will be discarded until a corresponding %MEND
     statement is encountered.
   the ORIGINAL definition stays in effect — %m1 runs the FIRST body ("one",
   never "two") — and execution CONTINUES (a macro-scope error, not an
   errhalt). rc 1: the program asked for protection and then violated it.
   MREPLACE (the default) allows the redefinition — see the unit tests.
   expect-rc: 1 */
%macro m1;
  data _null_; put "one"; run;
%mend m1;
options nomreplace;
%macro m1;
  data _null_; put "two"; run;
%mend m1;
%m1
data _null_; put "after"; run;
