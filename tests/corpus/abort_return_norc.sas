/* GAP-ebnfholes-tick356 — `abort return;` with NO return code is legal SAS:
   the ABORT syntax's <n> is optional (DATA Step Statements: Reference,
   printed p.16, marker "=== pdf 27 ==="), the doc's own z/OS example runs
   `if errcode=16 then abort return;` (printed p.19, marker "=== pdf 30 ==="),
   and RETURN without n "returns ... a condition code that indicates an
   error" (printed p.18, marker "=== pdf 29 ===") — an ERROR-class exit,
   default rc 1, the same default ABEND-no-n takes (D-009a: the ABORT rc IS
   the process exit). Was REFUSED: "ABORT RETURN requires a return code".
   A stray word after RETURN stays a loud typo (pinned in-source, parser.zig
   "abort variants" test); NOLIST after it is still unimplemented and loud.
   The 'before abort' line proves the step ran; the ABORT ERROR poisons
   every later step (BUG-errhalt), so 'AFTER ABORT' must never print.
   expect-rc: 1 */
data _null_;
  put 'before abort';
  abort return;
  put 'unreachable';
run;
data b;
  y = 1;
  put 'AFTER ABORT — must not run';
run;
