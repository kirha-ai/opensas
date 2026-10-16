/* The BOUNDARY of BUG-procmissingfilerc (GH#21), pinned so the reclassification
   cannot creep: a workbook that READS fine and then fails to PARSE is a genuine
   opensas gap, exit 2 — the minimal XLSX reader is the thing that cannot cope,
   not the user's path (D-009b(i): a gap stays 2). Only the io.readFileRaw
   failure moved to the user's exit 1 (rc_import_missing_file.sas).

   The payload starts with the ZIP magic, so the not-an-XLSX guard passes it
   through to the reader, which then finds no workbook.xml. stdout stays empty
   and the UNSUPPORTED line goes to stderr.
   expect-rc: 2 */
data _null_;
  file "/tmp/opensas_rc_import_xlsx_parse_gap.xlsx";
  put "PK this is not a workbook";
run;

proc import datafile="/tmp/opensas_rc_import_xlsx_parse_gap.xlsx" out=z dbms=xlsx replace;
run;
