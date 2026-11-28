/* STAT-QUANTREG-001: BY groups. Two BY groups hold identical copies of the
 * Getting Started simulation, so each group repeats the published listing.
 * Known whitespace-only difference: opensas centers the BY line even under
 * NOCENTER (shared BY-line helper); SAS prints it flush left.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data a (drop=i);
do i=1 to 1000;
x1=rannor(1234);
x2=rannor(1234);
e=rannor(1234);
if i > 950 then y=100 + 10*e;
else y=10 + 5*x1 + 3*x2 + 0.5 * e;
output;
end;
run;
data _oracle_input; set a; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc quantreg data=_oracle_input;
by _oracle_by;
model y = x1 x2 / seed=314159;
run;
