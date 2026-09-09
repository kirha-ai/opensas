/* GAP-gapsexitingone §5b re-verdict — FW= is a documented SAS 9.4 PROC
   MEANS option (Procedures Guide, 7th ed., printed pp. 1482-1484) opensas
   does not implement — an opensas gap, exit 2; the message body is
   byte-identical to the typo arm's. Typo twin: rc_means_option_typo.sas.
   expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc means data=h fw=8;
  var x;
run;
