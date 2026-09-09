/* GAP-putptrslice: `@'string'` string search is an INPUT-only pointer control
   (Statements Table 2.3) — NOT in PUT's Table 2.5 — so real SAS 9.4 rejects
   this program: a USER error, rc 1 ("fix your SAS"), the same decision
   GAP-atexpression-put made for `@(character-expression)`. The split at this
   site must NOT re-tag it as a gap: a user with a genuine typo must not be
   told to file an opensas issue.
   expect-rc: 1 */
data _null_;
  put @'ab' a;
run;
