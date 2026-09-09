/* BUG-whereconditional — a WHERE statement nested in an IF branch was silently
   HOISTED and applied UNCONDITIONALLY: `if x>10 then where x<3;` filtered
   every row even though x>10 is never true — a conditional filter that
   always fires is a silent wrong answer. Language Reference: Concepts printed p.232 Table 11.6
   reserves "Execute the selection conditionally" for the subsetting IF (a
   WHERE expression tests the condition BEFORE an observation is read into
   the PDV, p.231), so real SAS refuses the program outright: ERROR 180-322
   "Statement is not valid or it is used out of proper order." opensas now
   fails loud at compile time (exit 1). The first step proves a TOP-LEVEL
   WHERE still filters; the failing step runs last because a step ERROR puts
   the run in syntax-check mode (BUG-errhalt). where_conditional_do_err.sas
   pins the DO-body nest.
   expect-rc: 1 */
data d; input x; datalines;
1
2
3
;
run;
data ok; set d; where x<3; run;
proc print data=ok noobs; run;
data r; set d; if x>10 then where x<3; run;
