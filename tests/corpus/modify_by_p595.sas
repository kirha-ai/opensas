/* Language Reference: Concepts Ch.23's flagship MODIFY program (p.595, "Example 4: Updating a Master
   Data Set By Adding Observations"; result narrated at p.596 and Figure 23.10)
   VERBATIM — only today() replaced by a fixed date so the output is diffable.
   p.596: "The REPLACE statement updates observations 4, 7, and 8" (figure
   positions = K89R/KJ66/BV1E) and "The OUTPUT statement adds observations 1, 2,
   and 5" (transaction positions = AA11/BB22/CC33) — 3+3 = 6 iterations = the
   6 TRANSACTION rows (BUG-modifybymasterdriven).  The SEVEN master rows with
   no transaction (BC85 JD03 LK43 M4J7 MN21 NCF3 UYN7) must come out
   BYTE-IDENTICAL — UPDATE's master-driven driver used to hand each a _SOK
   iteration, so the _SOK branch ran Amount_in_Stock + (missing) -> missing
   and REPLACE wiped them IN PLACE.  (p.596 par.4's "Price updated /
   ReceivedDate not updated" prose contradicts the doc's own printed program,
   which sets ReceivedDate=today() and never assigns Price in the _SOK branch;
   the fixture follows the PROGRAM, as transcribed.  The transaction-only
   columns Add_New_Stock/New_Price still land in the rebuilt descriptor —
   BUG-modifydescriptor, queued — so the print names the 5 master columns.) */
data Inventory;
input PartNumber $ PartName $ Amount_in_Stock Price ReceivedDate date9. ;
format Price comma12.2 ReceivedDate mmddyy10.;
datalines;
K89R seal    34  245.00 07jul1998
M4J7 sander  98   45.88 20jun1998
LK43 filter 121   10.99 19may1999
MN21 brace   43   27.87 10aug1999
BC85 clamp   80    9.55 16aug1999
NCF3 valve  198   24.50 20mar1999
KJ66 cutter   6   19.77 18jun1999
UYN7 rod    211   11.55 09sep1999
JD03 switch 383   13.99 09jan2000
BV1E timer   26   34.50 03aug2000
;
run;
proc sort data=inventory; by PartNumber; run;
data add_Inventory;
input PartNumber $ PartName $ Add_New_Stock New_Price;
format New_Price comma12.2;
datalines;
K89R seal    6 247.50
AA11 hammer 55  32.26
BB22 wrench 21  17.35
KJ66 cutter 10  24.50
CC33 socket  7  22.19
BV1E timer  30  36.50
;
run;
proc sort data=add_Inventory; by PartNumber; run;
data Inventory;
   modify Inventory add_Inventory;
      by PartNumber;
      select (_iorc_);
          when (%sysrc(_sok)) do;
             Amount_in_Stock = Amount_in_Stock + Add_New_Stock;
             ReceivedDate = '01jan2020'd;
             replace;
          end;
          when (%sysrc(_dsenmr)) do;
             Amount_in_Stock=Add_New_Stock;
             ReceivedDate='01jan2020'd;
             Price=New_Price;
             output;
             _error_=0;
          end;
      otherwise do;
         put "An unexpected I/O error has occurred.";
         _error_ = 0;
         stop;
      end;
   end;
run;
proc sort data=Inventory; by PartNumber; run;
proc print data=Inventory;
   var PartNumber PartName Amount_in_Stock Price ReceivedDate;
   title "Updated Inventory Data Set Sorted by PartNumber";
run;
