/* expect-rc: 2
 * STAT-RMSTREG-001: valid PROC RMSTREG requests outside this ticket stay
 * loud D-009 gaps and print nothing: estimates that did not converge
 * (MAXITER=1; SAS prints them with "Iteration limit exceeded."), the CLASS
 * statement and METHOD=IPCW; all-censored data (default TAU= is the
 * largest observed time, SAS prints a degenerate DF 0 fit owned by
 * STAT-RMSTREG-005). The other gaps (ITHISTORY, OUTPV=, COVB,
 * CORRB, NOFIT, CONVH=, effect syntax, LSMEANS, ...) are pinned in
 * src/stat/rmstreg_tests.zig through the captured reporter. Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data d;
do id=1 to 60;
age=25+mod(id*7,40);
x=mod(id,2);
time=exp(0.5+0.15*x+0.01*age+0.7*sin(id*1.7));
status=(mod(id,4) ne 0);
output;
end;
run;
proc rmstreg data=d tau=4; model time*status(0)=age x / maxiter=1 converge=1e-8; run;
proc rmstreg data=d tau=4; class x; model time*status(0)=age x; run;
proc rmstreg data=d tau=4; model time*status(0)=age x / method=ipcw; run;
data cens; set d; status=0; run;
proc rmstreg data=cens; model time*status(0)=age x / link=linear; run;
