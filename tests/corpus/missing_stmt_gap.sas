/* BUG-missingstmtwrongclass: the MISSING statement declares the characters raw
   numeric input reads as special missing values (.A-.Z/._) — VALID SAS 9.4
   (Language Reference: Concepts printed p.519 shows a worked example TWICE) that opensas does not
   implement. Both refusal sites must be a NAMED rc-2 gap (D-009/D-009b(i)) —
   "file an opensas issue" — never rc 1 "your SAS is broken":
     - DATA step:  was "expected '=' in assignment" (wrong construct, rc 1)
     - open code:  was "statement missing is not valid in open code" (rc 1)
   The DATA-step site fires first (step 1 fails to parse); the open-code site
   then reports from the segment scan in the same run. Both say:
     the MISSING statement (special missing values) is not supported
   `missing = 5;` is an ordinary assignment everywhere (the `=` guard).
   expect-rc: 2 */
data d;
  missing A;
  x = .A;
run;
missing B;
