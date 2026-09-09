/* GAP-gapsexitingone §5c — the rc-1 half of the CALL-routine SPLIT.

   `SYMPTU` is not a SAS 9.4 CALL routine (the user meant SYMPUT), so real SAS
   rejects this program too: the user's error, rc 1. The guard text is the
   same "CALL {s}() is not supported" as the gap arm in
   rc_call_routine_gap.sas — the MESSAGE is byte-identical on both arms and
   only the rc distinguishes them, which is the whole point of D-009.
   expect-rc: 1 */
data _null_;
  call symptu("a", "b");
run;
