/* GAP-gapsexitingone §5d — ODS OUTPUT (capture a PROC table to a dataset)
   is documented valid SAS 9.4 that opensas does not model: valid SAS
   refused → gap → rc 2, not 1. The guard matches the OUTPUT keyword itself
   (a typo'd sub-statement is the accepted listing no-op), so no typo arm.
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
ods output Summary=s;
