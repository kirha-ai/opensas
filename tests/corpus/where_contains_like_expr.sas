/* BUG-wherecontainslikeexpr (doc-finder tick291 F2): CONTAINS and LIKE consumed
   only ONE token of the right operand, so a computed pattern silently matched
   ZERO rows on all four WHERE routes. Language Reference: Concepts p.223: a LIKE pattern is "a SAS
   character expression" (concatenation is legal); p.221-222: CONTAINS takes
   variables and TRIM on the right. The `?` synonym (parser_expr) was already
   correct — every route must agree with it. */
%let pfx=John;
data t; length s $20; input s $; datalines;
JohnSmith
MaryJones
;
run;
/* LIKE with a concatenated pattern — the macro idiom, all four WHERE routes */
data a; set t(where=(s like "&pfx" || '%')); run;
proc print data=a noobs; run;
data b; set t; where s like "&pfx" || '%'; run;
proc print data=b noobs; run;
proc print data=t noobs; where s like "&pfx" || '%'; run;
proc sql; select * from t where s like "&pfx" || '%'; quit;
/* CONTAINS with a concatenated substring, all four routes */
data c; set t(where=(s contains 'John'||'Sm')); run;
proc print data=c noobs; run;
data d; set t; where s contains 'John'||'Sm'; run;
proc print data=d noobs; run;
proc print data=t noobs; where s contains 'John'||'Sm'; run;
proc sql; select * from t where s contains 'John'||'Sm'; quit;
/* p.222 verbatim: "the TRIM function is helpful when you search on a macro
   variable" — CONTAINS admits a function on the right (LIKE may not, p.223) */
%let lname=Smith;
data u; length fullname $20 lastname $10; input fullname $ lastname $; datalines;
JohnSmith Smith
JohnSmith Jones
MaryJones Jones
;
run;
proc print data=u noobs; where fullname contains trim("&lname"); run;
proc print data=u noobs; where fullname contains trim(lastname); run;
/* the `?` synonym control — the pre-existing CORRECT path both must match */
proc print data=u noobs; where fullname ? trim(lastname); run;
/* wildcard control: '_' is a single-char wildcard, so 'a'||'_b' is 'a?b' */
data x; length x $3; input x $; datalines;
abc
a_b
axb
;
run;
proc print data=x noobs; where x like 'a'||'_b'; run;
proc sql; select * from x where x like 'a'||'_b'; quit;
