/* GAP-gapsexitingone §5f — the gap arm of the read-side informat SPLIT:
   PDw.d is a documented SAS 9.4 informat (Formats & Informats Reference,
   packed-decimal dictionary entry) that opensas does not implement, so the
   INPUT-statement refusal (io.zig's checkInputInformats) is an opensas gap →
   rc 2, not rc 1. Same message as the typo arm; only the rc signal moved.
   The PROC PRINT above proves the guard discriminates (BUG-errhalt).
   Twin rc_informat_bogus_typo.sas holds the rc-1 typo arm.
   expect-rc: 2 */
data b;
  x = 1;
run;
proc print data=b;
run;
data _null_;
  input x pd8.;
datalines;
1234
;
