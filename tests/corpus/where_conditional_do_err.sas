/* BUG-whereconditional — the DO-body twin of where_conditional_err.sas: a
   WHERE statement inside a DO block was silently HOISTED and applied
   UNCONDITIONALLY (and the hoist even leaked the loop variable into the
   output). Language Reference: Concepts printed p.232 Table 11.6 reserves "Execute the selection
   conditionally" for the subsetting IF, so real SAS refuses the program:
   ERROR 180-322 "Statement is not valid or it is used out of proper order."
   opensas fails loud at compile time (exit 1), printing NOTHING from the
   failing step.
   expect-rc: 1 */
data d; input x; datalines;
1
2
3
;
run;
data r; set d; do i=1 to 1; where x<3; end; run;
