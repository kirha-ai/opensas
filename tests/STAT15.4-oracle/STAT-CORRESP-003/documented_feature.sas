/* STAT-CORRESP-003: CORRESP — SUPPLEMENTARY / TABLES / Using the TABLES
 * Source: S154 / Chapter 41 / `SUPPLEMENTARY Statement` (PDF p. 2590); S154 / Chapter 41 / `TABLES Statement` (PDF pp. 2590–2591); S154 / Chapter 41 / `Using the TABLES Statement` (PDF pp. 2592–2600).
 * Discriminates: Example 41.2: Simple Correspondence Analysis of U.S. Population; explicit statements: SUPPLEMENTARY
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'United States Population, 1920-1970';
data USPop;
* Regions:
* New England - ME, NH, VT, MA, RI, CT.
* Great Lakes - OH, IN, IL, MI, WI.
* South Atlantic - DE, MD, DC, VA, WV, NC, SC, GA, FL.
* Mountain - MT, ID, WY, CO, NM, AZ, UT, NV.
* Pacific - WA, OR, CA.
*
* Note: Multiply data values by 1000 to get populations.;
length Region $14;
input Region :$14. y1920 y1930 y1940 y1950 y1960 y1970;
label y1920 = '1920' y1930 = '1930' y1940 = '1940'
y1950 = '1950' y1960 = '1960' y1970 = '1970';
if region = 'Hawaii' or region = 'Alaska'
then w = -1000;
/* Flag Supplementary Observations */
else w = 1000;
datalines;
New_England 7401 8166 8437 9314 10509 11842
NY,_NJ,_PA 22261 26261 27539 30146 34168 37199
Great_Lakes 21476 25297 26626 30399 36225 40252
Midwest 12544 13297 13517 14061 15394 16319
South_Atlantic 13990 15794 17823 21182 25972 30671
KY,_TN,_AL,_MS 8893 9887 10778 11447 12050 12803
AR,_LA,_OK,_TX 10242 12177 13065 14538 16951 19321
Mountain 3336 3702 4150 5075 6855 8282
Pacific 5567 8195 9733 14486 20339 25454
Alaska 55 59 73 129 226 300
Hawaii 256 368 423 500 633 769
;
ods graphics on;
* Perform Simple Correspondence Analysis;
proc corresp data=uspop print=percent observed cellchi2 rp cp chi2p
short plot(flip);
var y1920 -- y1970;
id Region;
weight w;
run;
