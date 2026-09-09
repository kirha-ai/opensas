/* QA tick377 cross-landing sweep — GAP-secondsetstmt (837590ea) interaction pins.
   The landing rewired WHICH STATEMENT DRIVES A STEP: a second SET carrying
   POINT= is claimed as a direct-access lookup while the SEQUENTIAL driver keeps
   iteration, EOF and the implicit output (Statements ref p.341 Example 6). The
   landing's own fixture pins Example 6; this one pins the DRIVER COMBINATIONS
   the sweep verified correct, so a later step-driver edit cannot silently move
   them. Every shape below was byte-compared against a baseline binary at
   aeac429a (where all of them were loud) and re-verified on live master.

   Report 1  MERGE driver + POINT= lookup (no BY).
   Report 2  single-dataset MODIFY driver + POINT= lookup.
   Report 3  multi-source (concatenated) sequential driver + POINT= lookup.
   Report 4  NOBS= on the LOOKUP statement reports the LOOKUP's obs count,
             NOBS= on the DRIVER reports the driver's — the two SET statements
             keep their own counts (Statements p.336 NOBS=).
   Report 5  keep=/rename= data set options apply to the claimed lookup.
   Report 6  in= on the driver, and a COMPUTED (non-_N_) POINT= index.
   Report 7  explicit OUTPUT alongside the lookup — the driver still owns
             iteration, so two OUTPUTs per driver row give 2*N rows.

   Report 8  SET driver + a SUM STATEMENT reading the lookup column (QA tick377
             F2 repro A verbatim): the accumulator is first-mentioned AT the sum
             statement, AFTER the lookup's columns, and reading b provokes NO
             false `uninitialized` NOTE (the NOTE half is pinned by the
             captured-diagnostics tests in src/exec.zig — this surface is
             stdout-only).
   Report 9  the report-1 MERGE shape through PROC EXPORT CSV — first-mention
             PDV order is equally user-visible in the exported header row.

   COLUMN ORDER is the SAS first-mention rule and is pinned CORRECT in every
   report: the driver's columns own the early slots and the second-SET POINT=
   lookup's columns land at the SET statement that carries the option
   (Statements ref p.341 Example 6 makes the second SET an ordinary
   compile-time source). Reports 1 and 2 used to pin the lookup FIRST and
   report 8's accumulator ahead of the lookup — QA tick377 F2; fixed by
   seeding the lookup's PDV columns at the carrying node. */

data drv; input a; datalines;
1
2
;
run;

data lk; input b; datalines;
10
20
30
40
;
run;

/* 1: MERGE drives, the second SET is a direct read */
data mA; input k p; datalines;
1 9
2 8
;
run;
data mB; input k q; datalines;
1 7
2 6
;
run;
data r1; merge mA mB; set lk point=_n_; run;
proc print data=r1; run;

/* 2: single-dataset MODIFY drives an in-place rewrite, the lookup rides along */
data mast; input k v; datalines;
1 10
2 20
;
run;
data mast; modify mast; set lk point=_n_; v = v + b; run;
proc print data=mast; run;

/* 3: concatenated sequential driver + lookup */
data d1; input a; datalines;
1
2
;
run;
data d2; input a; datalines;
3
4
;
run;
data r3; set d1 d2; set lk point=_n_; run;
proc print data=r3; run;

/* 4: NOBS= belongs to the statement that carries it */
data r4a; set drv; set lk point=_n_ nobs=n; put "NOBS_ON_LOOKUP=" n; run;
proc print data=r4a; run;
data r4b; set drv nobs=n; set lk point=_n_; put "NOBS_ON_DRIVER=" n; run;
proc print data=r4b; run;

/* 5: keep= / rename= on the claimed lookup */
data lk2; input p x; datalines;
1 5
2 6
;
run;
data r5a; set drv; set lk2(keep=x) point=_n_; run;
proc print data=r5a; run;
data r5b; set drv; set lk2(rename=(x=xx)) point=_n_; run;
proc print data=r5b; run;

/* 6: in= on the driver + a computed POINT= index (reverse order) */
data r6; set drv(in=ind); f = ind; p = 3 - _n_; set lk point=p; run;
proc print data=r6; run;

/* 7: explicit OUTPUT — the DRIVER still owns iteration */
data r7; set drv; set lk point=_n_; output; output; run;
proc print data=r7; run;

/* 8: QA tick377 F2 repro A — a sum statement reading the lookup column:
   b is first-mentioned at the SET that carries POINT=, tot at the sum
   statement → a b tot (was a tot b + a false "Variable b is uninitialized.").
   The plain-second-SET control from the same QA report: same order, same sums. */
data r8; set drv; set lk point=_n_; tot + b; run;
proc print data=r8; run;
data r8c; set drv; set lk; tot + b; run;
proc print data=r8c; run;

/* 9: the report-1 MERGE shape through PROC EXPORT CSV — the header row pins
   k,p,q,b through a second user-visible surface. */
proc export data=r1 outfile="tests/corpus/includes/spsld_r1.csv" dbms=csv replace; run;
data r9;
  infile "tests/corpus/includes/spsld_r1.csv" truncover;
  length line $40;
  input line $char40.;
run;
proc print data=r9 noobs; run;
