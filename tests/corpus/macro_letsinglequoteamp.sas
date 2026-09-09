/* BUG-letsinglequoteampunresolved (QA F2) — a single quote does NOT mask `&`
   in a macro statement. %LET resolves at ASSIGNMENT time and stores the
   RESOLVED text: masking an ampersand in a macro variable value requires a
   macro quoting function (Macro Language Ref printed p.7; Table 7.2 printed
   p.100: only %NRSTR/%NRBQUOTE/%NRQUOTE mask `%name &name`). printed p.38's
   single-quote rule governs SAS statements (TITLE/DATA-step literals), not
   macro statements.
   The reference path (a = "&q2") rendered right even before the fix, which is
   why the bug survived; the SYMGET path handed the DATA step the literal
   'AT&t' at rc 0 — a silent wrong value crossing into stored data — and a
   later %let t=… retroactively changed &q2. */
%let t=RESOLVED;
%let q2='AT&t';
data _null_;
  a = "&q2";
  b = symget('q2');
  put a= / b=;
run;
%let t=CHANGED;
data _null_;
  c = "&q2";  /* storage-time snapshot: the re-let must NOT retroactively move q2 */
  put c=;
run;
