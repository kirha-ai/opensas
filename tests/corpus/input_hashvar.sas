/* GAP-inputpointerguard: `#numeric-variable` is a valid SAS 9.4 INPUT line
   pointer (Statements Table 2.3, printed p.174) opensas doesn't implement —
   a gap → rc 2 (same fall-through-to-`expected ';'` defect as `+var`).
   expect-rc: 2 */
data _null_;
  input #x a;
run;
