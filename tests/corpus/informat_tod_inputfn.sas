/* BUG-todinputfn: the INPUT() FUNCTION half of BUG-todinformat. readInformat
   routes a fixed name list to format.readNumeric and 'tod' was not on it, so
   `input("10:30:00", tod18.)` returned MISSING while the STATEMENT `input a
   tod18.;` read 37800 — the same two-ends-of-one-feature disagreement the
   statement fix closed, one layer up. (tod was the LAST such split: every other
   name in format.isKnownInformat already had a route.)
   Each row reads the SAME raw text twice — once by the statement, once by the
   function off _infile_ — and prints SAME/DIFFER, so a re-divergence between the
   two entry points cannot pass silently. Every row must say SAME. */
data _null_;
  infile datalines truncover;
  length agree $6;
  input a tod18.;
  fn = input(_infile_, tod18.);
  if a = fn then agree = 'SAME'; else agree = 'DIFFER';
  put a= fn= agree=;
datalines;
10:30:00
14:45
7
1:30 PM
12:00 AM
25DEC2024:10:30:00
not a time
;
run;
