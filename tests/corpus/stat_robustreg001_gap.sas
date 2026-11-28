/* expect-rc: 2
 * STAT-ROBUSTREG-001: valid PROC ROBUSTREG requests outside this ticket stay
 * loud D-009 gaps and print nothing: LEVERAGE (MCD robust distances), the
 * TEST statement, METHOD=LTS and PLOTS=. The other gaps are pinned in src/stat/robustreg_tests.zig. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data d;
do i=1 to 30;
x=mod(i*7,11);
z=mod(i*5,13);
y=2+0.5*x-0.3*z+mod(i*3,5)/2;
w=1+mod(i,3);
output;
end;
run;
proc robustreg data=d; model y = x z / diagnostics leverage; id i; run;
proc robustreg data=d; model y = x z; test z; run;
proc robustreg data=d method=lts; model y = x z; run;
proc robustreg data=d plots=all; model y = x z; run;
