/* GAP-gapsexitingone §5f — the typo arm of the write-side format SPLIT:
   YEN is in NO SAS 9.4 Formats and Informats Reference entry (checked the
   dictionary; ab17c60f DECLINED it under D-015), so real SAS 9.4 also errors
   "format not found" — the user's SAS is wrong → rc 1 ("fix your SAS"),
   never the gap arm's rc 2. The message is byte-identical either way; the
   split is in the rc signal only. Twin of rc_fmt_unimpl_gap.sas.
   expect-rc: 1 */
data b;
  x = 1;
run;
proc print data=b;
run;
data _null_;
  x = 0.5;
  put x yen8.;  /* not a SAS format at all → user error, raw fallback on stdout */
run;
