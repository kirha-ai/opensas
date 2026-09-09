/* QA tick397 cross-landing sweep — D-009a's ABORT override, composed with the
   gap direction that landed all around it.

   D-009a: `abort return n` propagates n, deliberately outside {0,1,2}.
   `main.processExitCode` checks `g_abort_rc` ABOVE `gap or user_err`, and five
   landings in this batch touched that path (userErr, markGap, rcErr,
   recoverable, the wasm alias). `abort_rc.sas` pins the ABORT rc ALONE; nothing
   pinned it against a competing signal. This program raises a GAP as well —
   "system option NOREPLACE is not supported", rc 2 on its own
   (rc_opt_noreplace.sas) — and the ABORT rc must still win: 3, not 2.

   The gap is a whole-program OPTIONS pre-pass, so it is reached even though the
   ABORT halted the session; both ERROR lines appear in the log and only the rc
   discriminates. The clean PROC PRINT above proves the run got that far.

   expect-rc: 3 */

data a;
  x = 1;
run;

proc print data=a noobs;
run;

data _null_;
  abort return 3;
run;

options noreplace;
