/* GAP-gapsexitingone §5f — the typo arm of the read-side informat SPLIT:
   YEN is in NO SAS 9.4 informat dictionary entry, so real SAS 9.4 also
   rejects it — the user's SAS is wrong → rc 1 ("fix your SAS"), never the
   gap arm's rc 2. Same message as the gap arm; only the rc signal moved.
   Twin of rc_informat_unimpl_gap.sas.
   expect-rc: 1 */
data b;
  x = 1;
run;
proc print data=b;
run;
data _null_;
  input x yen8.;
datalines;
1234
;
