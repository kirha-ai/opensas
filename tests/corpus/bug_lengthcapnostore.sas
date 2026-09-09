/* BUG-lengthcapnostore: a declared character length over 32767 was silently
   accepted when nothing was ever stored into the variable — the 67a3c834 cap
   sits at pdv.setAt (STORE time), so `length y $40000; run;` slipped through.
   Real SAS rejects the LENGTH statement itself at compile time, store or no
   store (LENGTH Statement, SAS 9.4 DATA Step Statements: Reference printed
   p.217 — pdf 228 at the volume's +11 offset, verified by the "LENGTH
   Statement 217" footer closing pdf 228: "For character variables, 1 to
   32767 bytes under all operating environments"). The declaration is now
   rejected AT THE STATEMENT (parser.zig checkDeclLen, shared with ATTRIB);
   setAt's check stays for lengths arriving by non-parser routes (SET-source
   carries, XPORT/sas7bdat reader lens). ERROR/NOTE are on the log, exit 1.
   BOUNDARY OK pins the legal edge (32766/32767, numeric 8) and proves the
   run is healthy up to the bad statement; the last step must never print.
   expect-rc: 1 */
data ok; length a $32766 b $32767; run;
data ok2; attrib c length=$32767; run;
data _null_; length n 8; put 'BOUNDARY OK'; run;
data b; length y $40000; run;
data _null_; put 'SILENT ACCEPT REGRESSED'; run;
