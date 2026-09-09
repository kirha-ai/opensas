/* BUG-infilepadinert (D-002): INFILE ... PAD was parsed, stored, and never read
   — the lone silent no-op in the fail-loud option wall (all 16 other unsupported
   INFILE options error). PAD blank-pads a short record out to LRECL=, but LRECL=
   is itself a documented accept-and-ignore no-op (ISS-infilelrecl), so PAD has
   nothing to pad TO; loud-unsupported is the honest behavior until both land
   together. The first step is the positive control; the PAD step must fail LOUD
   ("INFILE option pad is not supported", exit 1) and print nothing — if PAD
   silently regresses, "PAD RAN" appears below and the golden mismatches.
   expect-rc: 2 */
data _null_;
  put 'CONTROL OK';
run;
data _null_;
  infile datalines pad;
  input x;
  put 'PAD RAN — silent no-op regressed';
datalines;
1
;
run;
