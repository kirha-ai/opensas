/* BUG-macrooptescapedquotealias — a SAS doubled quote inside an OPTIONS value
   does not close the value. Oracle probe (real SAS 9.4, 2026-11-01):
   `options sysparm="a""nomreplace";` is valid and does not set NOMREPLACE.
   Both %MACRO definitions compile, the second replaces the first, and the call
   prints TWO. Before the fix the raw OPTIONS scan stopped at the escaped quote,
   saw `nomreplace` as a separate option, refused the redefinition, exited 1,
   and ran the first body.
   expect-rc: 0 */
options sysparm="a""nomreplace";
%macro m;
  data _null_; put "ONE"; run;
%mend;
%macro m;
  data _null_; put "TWO"; run;
%mend;
%m
