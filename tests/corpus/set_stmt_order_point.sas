/* BUG-setstmtorder regression net: a POINT= driver (BUG-setpoint) keeps
   its executable-at-the-node read — the .once driver has no sequential
   read to split around, so the statement-order split must not touch it.
   The explicit DO loop drives the direct-access reads. */
data d; input v; datalines;
10
20
30
;
run;
data p; do i=1 to 3; set d point=i; output; end; stop; run;
proc print data=p noobs;
   title 'POINT= direct access in a DO loop';
run;
