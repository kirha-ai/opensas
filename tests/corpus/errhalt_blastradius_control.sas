/* SEV-errhaltblastradius (CONTROL) — the same four-step shape as
   errhalt_blastradius.sas but with NO error anywhere: both PRINT tables
   MUST render and the rc MUST stay 0. Without this control the two error
   twins cannot tell "later steps correctly suppressed" from "everything is
   broken" — if syntax-check mode ever trips on a clean run, THIS fixture
   goes red (stdout truncated/empty or rc 1) while the error twins stay
   green. */
data a; c='ab'; n=1; run;
proc print data=a; run;
data b; set a; m = n + 1; run;
proc print data=b; run;
