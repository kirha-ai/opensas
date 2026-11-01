/* BUG-macrooptvarnamealias — a macro-variable NAME inside another option's
   value is not a standalone macro option. Oracle probe (real SAS 9.4,
   2026-11-01): `&nomreplace` below is the MCOMPILENOTE= value `all`; it does
   not set NOMREPLACE. Both %MACRO definitions compile, the second replaces the
   first, and the call prints TWO. Before the fix the raw OPTIONS scan saw the
   name in `&nomreplace`, falsely enabled NOMREPLACE, refused the redefinition,
   exited 1, and ran the first body.
   expect-rc: 0 */
%let nomreplace=all;
options mcompilenote=&nomreplace;
%macro m;
  data _null_; put "ONE"; run;
%mend;
%macro m;
  data _null_; put "TWO"; run;
%mend;
%m
