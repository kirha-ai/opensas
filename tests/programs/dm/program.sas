/*=============================================================================
* Study: DEMO-001
* Domain: DM (Demographics)
* Description: SDTM DM domain derived from the raw SUBJECTS enrolment listing.
*============================================================================*/

libname source "inputs" access=readonly;
libname target "output";

data target.dm;
    length STUDYID  $10
           DOMAIN   $2
           USUBJID  $20
           SUBJID   $4
           RFSTDTC  $10
           RFENDTC  $10
           RFXSTDTC $10
           RFXENDTC $10
           RFICDTC  $10
           SITEID   $4
           BRTHDTC  $10
           AGE       8
           AGEU     $5
           SEX      $1
           RACE     $60
           ETHNIC   $40
           ARMCD    $8
           ARM      $40
           ACTARMCD $8
           ACTARM   $40
           COUNTRY  $3;

    set source.subjects;

    STUDYID = "DEMO-001";
    DOMAIN  = "DM";
    SUBJID  = PATNO;
    SITEID  = CENTER;
    USUBJID = catx("-", STUDYID, SITEID, SUBJID);

    /* ISO 8601 dates: re-emit the raw text through a numeric date so a bad
       value fails at input() instead of passing through unchanged */
    if FIRSTDOSE ne "" then RFSTDTC = put(input(FIRSTDOSE, yymmdd10.), yymmdd10.);
    if LASTDOSE  ne "" then RFENDTC = put(input(LASTDOSE,  yymmdd10.), yymmdd10.);
    if CONSENT   ne "" then RFICDTC = put(input(CONSENT,   yymmdd10.), yymmdd10.);
    if DOB       ne "" then BRTHDTC = put(input(DOB,       yymmdd10.), yymmdd10.);
    RFXSTDTC = RFSTDTC;
    RFXENDTC = RFENDTC;

    /* Age at first dose, whole years; unknown when either date is missing */
    if DOB ne "" and FIRSTDOSE ne "" then do;
        AGE  = floor(yrdif(input(DOB, yymmdd10.), input(FIRSTDOSE, yymmdd10.), "ACT/ACT"));
        AGEU = "YEARS";
    end;

    SEX     = upcase(strip(GENDER));
    RACE    = upcase(strip(RACE));
    ETHNIC  = upcase(strip(ETHN));
    COUNTRY = upcase(strip(CTRY));

    /* Planned arm decoded from the randomisation code; actual arm equals planned
       in this listing (no treatment switches) */
    ARMCD = upcase(strip(ARMCODE));
    select (ARMCD);
        when ("PBO") ARM = "Placebo";
        when ("ACT") ARM = "Active 10 mg";
        otherwise    ARM = "";
    end;
    ACTARMCD = ARMCD;
    ACTARM   = ARM;

    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          SUBJID   = 'Subject Identifier'
          RFSTDTC  = 'Subject Reference Start Date/Time'
          RFENDTC  = 'Subject Reference End Date/Time'
          RFXSTDTC = 'Referent Start Date/Time of Treatment'
          RFXENDTC = 'Referent End Date/Time of Treatment'
          RFICDTC  = 'Date of Informed Consent'
          SITEID   = 'Study Site Identifier'
          BRTHDTC  = 'Date/Time of Birth'
          AGE      = 'Age'
          AGEU     = 'Age Units'
          SEX      = 'Sex'
          RACE     = 'Race'
          ETHNIC   = 'Ethnic Group'
          ARMCD    = 'Planned Arm Code'
          ARM      = 'Description of Planned Arm'
          ACTARMCD = 'Actual Arm Code'
          ACTARM   = 'Description of Actual Arm'
          COUNTRY  = 'Country';

    drop PATNO CENTER CTRY DOB CONSENT FIRSTDOSE LASTDOSE GENDER ETHN ARMCODE;
run;
