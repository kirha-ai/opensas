/* FEAT-univ-inference: manual pp.300-306,417-421,444-447.
   Independent SAS evidence core.txt and qualifications.txt under
   /tmp/opensas-stat-batch2/FEAT-univ-inference. */
options nodate nonumber;
data d;do x=1 to 8;output;end;run;
proc univariate data=d normal cibasic cipctldf cipctlnormal robustscale loccount trimmed=.1 .25 winsorized=.25 nextrobs=0;
var x;
run;
