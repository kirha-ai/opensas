/* M9 EPIC-base-stat-complete/freq_format_order_*: two numeric values share
   one level. Missing sorts first under each of the four ordering modes. */
data sample;
  input code n;
  datalines;
20 1
10 3
11 2
30 4
. 1
;
proc format;
  value bandfmt 10,11='Zulu' 20='Alpha' 30='Middle';
run;
%macro counts(order);
  proc freq data=sample order=&order;
    format code bandfmt.;
    weight n;
    tables code / missing;
  run;
%mend;
%counts(data)
%counts(formatted)
%counts(freq)
%counts(internal)
