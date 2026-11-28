/* STAT-ROBUSTREG-001: BY groups. Two BY groups hold identical copies of the
 * published stack-loss data (SAS/STAT User's Guide Chapter 107), so each
 * group repeats the single-data-set result. Expected listing: the BY line
 * and page layout of the SAS 9.4 reference for the ticket's BY program
 * (tests/STAT15.4-oracle/STAT-ROBUSTREG-001/statement_by) with the tables
 * SAS 9.4 prints for this MODEL/ID request without LEVERAGE and TEST.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data Stack;
input x1 x2 x3 y exp $ @@;
datalines;
80 27 89 42 e1 80 27 88 37 e2
75 25 90 37 e3 62 24 87 28 e4
62 22 87 18 e5 62 23 87 18 e6
62 24 93 19 e7 62 24 93 20 e8
58 23 87 15 e9 58 18 80 14 e10
58 18 89 14 e11 58 17 88 13 e12
58 18 82 11 e13 58 19 93 12 e14
50 18 89 8 e15 50 18 86 7 e16
50 19 72 8 e17 50 19 79 8 e18
50 20 80 9 e19 56 20 82 15 e20
70 20 91 15 e21
;
data _oracle_input; set stack; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc robustreg data=_oracle_input;
by _oracle_by;
model y = x1 x2 x3 / diagnostics;
id exp;
run;
