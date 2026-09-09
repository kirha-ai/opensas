/* BUG-formatremoval: a FORMAT/INFORMAT statement name with NO following spec
 * is SAS's removal form — `format x;` CLEARS x's format (reverts to default),
 * it is not a no-op. The parser used to drop spec-less names, silently keeping
 * the old format. FORMAT is declarative, so within a step the LAST statement
 * wins for the whole step (both PUTs below show the cleared default). */
data a;
  x = 3.14159;
  c = "abc";
  format x 8.2 c $10.;
  format x c;        * clear both;
  put x "|" c;
run;
proc print data=a noobs; run;
/* grouped spec still applies to its group; only the trailing spec-less name
 * is cleared */
data b;
  a = 1.5; b = 2.5; c = 9.75;
  format a b 8.2 c;
  put a "|" b "|" c;
run;
/* INFORMAT removal: `informat d;` reverts to a default (plain numeric) read */
data c;
  informat d date9.;
  input d;
  put d date9.;
datalines;
15JAN2020
;
run;
data d;
  informat d;
  input d;
  put d;
datalines;
21929
;
run;
