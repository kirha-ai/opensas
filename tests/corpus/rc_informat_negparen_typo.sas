/* NOTE-informatlow-tick245 #14 re-verified STALE (D-019) and pinned at process
   level: NEGPARENw.d exists in SAS 9.4 ONLY as a FORMAT (Formats & Informats
   Reference p.255) — the informat dictionary has no NEGPAREN entry (it jumps
   MSECw.d -> NUMXw.d), so READING with it is the user's typo -> rc 1, never
   the gap arm's rc 2. Direction-sensitive twin of rc_informat_bogus_typo.sas:
   YEN is in NEITHER dictionary, so a future merge of the two dictionaries
   would flip NEGPAREN loud->silent while YEN stays loud — this name is the
   one that reddens. Read-side loudness landed at baa603c5/67c0be92/988e114b,
   the rc split at cf91f6ea; the NEGPAREN write FORMAT keeps working
   (fmt_commax_negparen.sas). The PROC PRINT proves the guard discriminates
   (BUG-errhalt). expect-rc: 1 */
data b;
  x = 1;
run;
proc print data=b;
run;
data _null_;
  input x negparen10.;
datalines;
1234
;
