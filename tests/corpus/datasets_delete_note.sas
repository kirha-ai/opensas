/* GAP-vtabledisk #2 (grade alignment): DELETE of a never-existed member is a
   NOTE-class event in real SAS, not an error — the run continues and exits 0.
   (A zero-match `pfx:` family delete already behaved this way.) */
proc datasets lib=work nolist; delete nosuch; quit;
data _null_; put 'after=ok'; run;
