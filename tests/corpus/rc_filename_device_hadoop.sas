/* BUG-rcsplitmembership F3 — the gap arm of the FILENAME-device split, after
   re-deriving the device list from the Statements reference in full. HADOOP
   is a documented device type (FILE statement `device-type`, printed p.88;
   INFILE statement, printed p.125) AND a documented access method ("FILENAME
   Statement: Hadoop Access Method", printed p.110). The first cut of the list
   held 14 names and omitted twelve documented ones — HADOOP, SFTP, ZIP,
   CLIPBOARD, DATAURL, S3, AZURE, FILESRVC, DUMMY, PLOTTER, ACTIVEMQ, JMS — so
   valid SAS got rc 1 "fix your SAS". Real SAS runs these; opensas has no engine
   for them, so they are gaps → rc 2 "is not supported".
   Twin rc_filename_baddevice.sas holds the rc-1 typo arm (`bogusdev`), and
   rc_filename_pipe.sas the arm that was already right.
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
filename f hadoop "x";
