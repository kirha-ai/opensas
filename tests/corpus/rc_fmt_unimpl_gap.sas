/* GAP-gapsexitingone §5f — the gap arm of the write-side format SPLIT:
   PVALUEw.d is a documented SAS 9.4 format (Formats & Informats Reference
   printed p.449 — the NLPCTN entry's own See Also points at it) that opensas
   does not implement, so the refusal is an opensas gap → rc 2 ("file an
   opensas issue"), never rc 1 ("fix your SAS" about valid SAS). The message
   is byte-identical to the pre-split one; only the rc signal moved. The PROC
   PRINT above proves the guard discriminates (BUG-errhalt): one error, last
   step. Twin rc_fmt_bogus_typo.sas holds the rc-1 typo arm.
   expect-rc: 2 */
data b;
  x = 1;
run;
proc print data=b;
run;
data _null_;
  x = 0.5;
  put x pvalue8.3;  /* documented, unimplemented → gap, raw fallback on stdout */
run;
