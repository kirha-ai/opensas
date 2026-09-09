/* GAP-gapsexitingone §5d — the JSON LIBNAME engine is a documented base
   SAS 9.4 engine (Statements Ref; the parseLibnames comment cites p.221):
   real SAS finds it and runs, so opensas's refusal is a gap → rc 2 with a
   named "not supported" message — not SAS's rc-1 "engine cannot be found",
   which mis-describes a documented engine and told the agent to fix valid
   SAS. LIBNAME option validation is a whole-program PRE-PASS, so the ERROR
   trips syntax-check mode before any step runs: the empty golden is honest.
   Twin rc_libname_engine_bogus.sas holds the rc-1 typo arm.
   expect-rc: 2 */
libname t json "nowhere";
