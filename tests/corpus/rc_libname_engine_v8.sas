/* BUG-rcsplitmembership F5 — the versioned base engines. QA flagged this as an
   OPEN QUESTION because the Statements Ref's LIBNAME section is a "has moved to
   SAS Global Statements" stub with no engine-name value list. It is settled in
   the Base SAS 9.4 Procedures Guide instead, twice:
     * printed p.1577 (`=== pdf 1626 ===`), PROC MIGRATE, a worked statement —
       `libname MyLib v8 'source-library-pathname' shortfileext;`
     * printed p.1566 (`=== pdf 1615 ===`), Overview: MIGRATE Procedure — "The
       migration must occur within the same engine family. For example, V6, V7,
       or V8 can migrate to V9, but V6TAPE must migrate to V9TAPE."
   Real SAS 9.4 FINDS V6/V7/V8/V6TAPE/V9TAPE; opensas implements only the
   V9/BASE on-disk format, so these are gaps → rc 2, not rc 1 "cannot be found",
   which told the agent to fix valid SAS. V9 stays honoured (it is the
   documented BASE alias, p.1032) and SAS/ACCESS names stay on the rc-1 arm.
   LIBNAME validation is a whole-program PRE-PASS, so the ERROR trips
   syntax-check mode before any step runs: the empty golden is honest.
   Twin rc_libname_engine_bogus.sas holds the rc-1 typo arm.
   expect-rc: 2 */
libname t v8 "nowhere";
