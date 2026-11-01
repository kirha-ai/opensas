/* BUG-macrooptcommentalias: a commented NOMREPLACE is not an option. SAS 9.4
   oracle (2026-11-01): the second definition replaces the first, %m prints
   TWO, and the run succeeds.
   expect-rc: 0 */
options /* nomreplace */ nonotes;
%macro m;
  data _null_; put 'ONE'; run;
%mend;
%macro m;
  data _null_; put 'TWO'; run;
%mend;
%m
