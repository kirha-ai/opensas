/* F7(b) multi-member XPORT READ: a transport file is a LIBRARY — the V5
   format allows repeated MEMBER sections. tests/corpus/includes/
   xport_multimember.xpt is two single-member files concatenated (member
   FIRST = 5 rows, member SECOND = 1 row). Member 1 must read back with
   EXACTLY its own 5 rows — before the fix the walk stopped only at an
   all-blank record or EOF, so member 2's header records decoded as garbage
   OBSERVATION rows appended to member 1 (the doc-finder's 100-row member
   came back with 109 rows). Later members are not exposed as datasets (one
   member per libref file); correctness of member 1 is the requirement.
   Cites docs/findings/doc-finder-tick220.md F7. */
libname i xport "tests/corpus/includes/xport_multimember.xpt";
data back; set i.first; run;
proc print data=back; run;
