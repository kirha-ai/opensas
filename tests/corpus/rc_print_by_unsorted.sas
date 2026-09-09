/* DEC-abortrcvsD009 (2a57cc33, main.zig 2577) — the strongest of the six rows,
   and it needed no SAS doc: the SAME single ERROR line exited 2 from PROC PRINT
   and 1 from PROC MEANS.

     proc print data=a; by x;        ERROR: Data set a is not sorted...   was rc 2
     proc means data=a; by x; var y; ERROR: Data set a is not sorted...      rc 1

   `Data set X is not sorted in Y sequence.` has SIX twins already at rc 1
   (proc.zig 1411/4013/5501/6174/6363/8010) and is SAS's own ERROR text, so real
   SAS rejects this program too. rc 1. means_by_unsorted.sas pins the twin; this
   pins the site that moved, so the two surfaces cannot drift apart again.
   expect-rc: 1 */
data a;
  input x y;
  datalines;
2 1
1 2
;
run;
proc print data=a noobs;
  var x y;
run;
proc print data=a;
  by x;
run;
