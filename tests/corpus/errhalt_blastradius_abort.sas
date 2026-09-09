/* SEV-errhaltblastradius (D-009a corollary) — ABORT OUTRANKS ONLY WHAT IT
   REACHES. `abort return 3` would exit 3 if its step ran (pinned by
   abort_rc.sas), but the earlier `format c 8.2` user error put the run into
   syntax-check mode, so the ABORT step is SKIPPED and the process exits
   with the earlier error's rc: 1, NOT 3. A REGRESSION looks like: the rc
   moves to 3 (skip lost — ABORT reached) or stdout appears; the
   reached-direction pin stays with abort_rc.sas. expect-rc: 1 */
data a; c='ab'; n=1; run;
proc print data=a; format c 8.2; run;
data _null_; abort return 3; run;
