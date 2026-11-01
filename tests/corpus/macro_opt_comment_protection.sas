/* BUG-macrooptcommentalias: a commented MREPLACE is not an option. SAS 9.4
   oracle (2026-11-01): NOMREPLACE refuses the second definition, %m prints
   ONE, and the run returns nonzero.
   expect-rc: 1 */
options nomreplace;
options /* mreplace */ nonotes;
%macro m;
  data _null_; put 'ONE'; run;
%mend;
%macro m;
  data _null_; put 'TWO'; run;
%mend;
%m
