/* BUG-lengthcapnostore (ATTRIB spelling): `attrib z length=$40000;` is the
   other spelling of the same declaration and took the same silent-accept
   hole. ATTRIB Statement, same volume, printed p.34 (pdf 45 — "34 Chapter 2"
   footer closes pdf 45): "LENGTH=<$>length ... Range For character
   variables, the range is from 1 to 32767 bytes for all operating
   environments." Rejected at the statement by the same parser.zig
   checkDeclLen. ERROR/NOTE on the log, exit 1. CONTROL proves the run is
   healthy up to the bad statement; the last step must never print.
   expect-rc: 1 */
data _null_; put 'CONTROL'; run;
data c; attrib z length=$40000; run;
data _null_; put 'SILENT ACCEPT REGRESSED'; run;
