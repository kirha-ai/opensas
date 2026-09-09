/* GAP-inputpointerguard: rc-1 CONTROL on the same guard — Table 2.3 has no
   `+'string'` pointer form (only `@'character-string'` exists, and opensas
   implements that one), so real SAS 9.4 rejects this program: a USER error,
   rc 1. The split must NOT re-tag garbage as a gap (D-009b).
   expect-rc: 1 */
data _null_;
  input +'ab' a;
run;
