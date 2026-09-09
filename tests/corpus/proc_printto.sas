/* GH#67 ISS-printto: PROC PRINTTO is a named no-op under the harness
   (log/output redirection is irrelevant — the runner captures stdout/stderr).
   The data step must still run; clean exit, no ERROR. */
proc printto log="x.log"; run;
data a; x=1; y=2; run;
proc printto; run;
proc print data=a noobs; run;
