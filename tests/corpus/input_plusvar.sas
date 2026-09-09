/* GAP-inputpointerguard: `+numeric-variable` is a valid SAS 9.4 INPUT column
   pointer (Statements Table 2.3, printed p.174) opensas doesn't implement —
   a gap → rc 2. It used to fall through the guard to `expected ';'`, an rc-1
   message blaming punctuation for documented syntax. `+n` stays supported.
   expect-rc: 2 */
data _null_;
  input +x a;
run;
