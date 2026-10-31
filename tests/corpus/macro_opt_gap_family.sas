/* GAP-macrooptfamily — the documented-but-absent family (Macro Ref ch.20,
   every option "Valid in: … OPTIONS statement"; membership re-derived IN FULL
   from the chapter's index per D-018). Every one of these exits as a NAMED
   rc-2 gap ("file an opensas issue") that is RECOVERABLE: real SAS runs them
   clean, so errhalt-skipping the rest of the run — the old rc-1 "not
   recognized" behavior — was the MED run-killer this ticket files. The
   stdout below is the proof the run continued: BOTH later steps print, and
   the OBS= in the same statement still applies.
   The honoured/stay-put halves of the family are NOT here: MPRINT/SYMBOLGEN/
   MLOGIC (implemented), MINOPERATOR/MINDELIMITER (implemented), MAUTOSOURCE/
   SASAUTOS=/MREPLACE/NOMREPLACE/MCOMPILENOTE= (this ticket, own fixtures);
   MERROR/MRECALL/MSTORED/SASMSTORE=/SERROR (settled inert); MACRO/NOMACRO and
   BLOTKEYWORDS (Valid-in EXCLUDES the OPTIONS statement — own fixture); and a
   TYPO like `mautocomp` stays rc 1 (unit test).
   expect-rc: 2 */
options nomcompile mcoverage nomcoverage mcoverageloc=covlib
        mexecnote nomexecnote mexecsize=64k mfile nomfile
        mlogicnest nomlogicnest mprintnest nomprintnest
        msymtabmax=2m mvarsize=1m
        cmdmac nocmdmac implmac noimplmac
        mautocomploc nomautocomploc mautolocdisplay nomautolocdisplay
        mautolocindes nomautolocindes obs=1;
data _null_; put "STEP-RAN"; run;
data _null_; put "SECOND-STEP-RAN"; run;
