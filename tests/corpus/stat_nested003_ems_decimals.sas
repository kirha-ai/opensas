/* expect-rc: 1
 * STAT-NESTED-003: EMS coefficient display: fewest exact decimals (2 here) and widths driven by a coefficient above 10.
 * Invented data (D-011). The expected listing is a SAS 15.4 reference run of
 * this program (every case logs "WARNING: The design is not balanced--F tests
 * cannot be computed.", hence rc 1 as SAS); the blank line SAS writes before
 * each new page title is dropped (opensas starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data d2;
input A B y @@;
datalines;
1 1 3 1 1 5 1 2 4 1 2 7 2 1 6 2 2 2 2 2 8 2 2 5
;
title 'S1 two decimals';
proc nested data=d2; class A B; var y; run;
data big;
do i=1 to 23;
  A = 1 + (i > 12);
  if i <= 6 then B = 1; else if i <= 12 then B = 2; else if i <= 18 then B = 1; else B = 2;
  y = mod(i*7, 13) + i/4;
  output;
end;
drop i;
run;
title 'S2 coefficient above ten';
proc nested data=big; class A B; var y; run;
