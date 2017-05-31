      SUBROUTINE WRCMPS(LUNIX)
 
C$$$  SUBPROGRAM DOCUMENTATION BLOCK
C
C SUBPROGRAM:    WRCMPS
C   PRGMMR: WOOLLEN          ORG: NP20       DATE: 2002-05-14
C
C ABSTRACT: THIS SUBROUTINE PACKS UP THE CURRENT SUBSET WITHIN MEMORY
C   (ARRAY IBAY IN COMMON BLOCK /BITBUF/), STORING IT FOR COMPRESSION.
C   IT THEN TRIES TO ADD IT TO THE COMPRESSED BUFR MESSAGE THAT IS
C   CURRENTLY OPEN WITHIN MEMORY FOR ABS(LUNIX) (ARRAY MESG).  IF THE
C   SUBSET WILL NOT FIT INTO THE CURRENTLY OPEN MESSAGE, THEN THAT
C   COMPRESSED MESSAGE IS FLUSHED TO LUNIX AND A NEW ONE IS CREATED IN
C   ORDER TO HOLD THE CURRENT SUBSET (STILL STORED FOR COMPRESSION).
C   THIS SUBROUTINE PERFORMS FUNCTIONS SIMILAR TO BUFR ARCHIVE LIBRARY
C   SUBROUTINE MSGUPD EXCEPT THAT IT ACTS ON COMPRESSED BUFR MESSAGES.
C
C PROGRAM HISTORY LOG:
C 2002-05-14  J. WOOLLEN -- ORIGINAL AUTHOR
C 2003-11-04  S. BENDER  -- ADDED REMARKS/BUFRLIB ROUTINE
C                           INTERDEPENDENCIES
C 2003-11-04  D. KEYSER  -- MAXJL (MAXIMUM NUMBER OF JUMP/LINK ENTRIES)
C                           INCREASED FROM 15000 TO 16000 (WAS IN
C                           VERIFICATION VERSION); LOGICAL VARIABLES
C                           "WRIT1" AND "FLUSH" NOW SAVED IN GLOBAL
C                           MEMORY (IN COMMON BLOCK /COMPRS/), THIS
C                           FIXED A BUG IN THIS ROUTINE WHICH CAN LEAD
C                           TO MESSAGES BEING WRITTEN OUT BEFORE THEY
C                           ARE FULL; UNIFIED/PORTABLE FOR WRF; ADDED
C                           DOCUMENTATION (INCLUDING HISTORY); OUTPUTS
C                           MORE COMPLETE DIAGNOSTIC INFO WHEN ROUTINE
C                           TERMINATES ABNORMALLY
C 2004-08-18  J. ATOR    -- REMOVE CALL TO XMSGINI (CMSGINI NOW HAS
C                           SAME CAPABILITY); IMPROVE DOCUMENTATION;
C                           CORRECT LOGIC FOR WHEN A CHARACTER VALUE IS
C                           THE SAME FOR ALL SUBSETS IN A MESSAGE;
C                           MAXIMUM MESSAGE LENGTH INCREASED FROM
C                           20,000 TO 50,000 BYTES
C 2004-08-18  J. WOOLLEN -- 1) ADDED SAVE FOR LOGICAL 'FIRST'
C                           2) ADDED 'KMISS' TO FIX BUG WHICH WOULD
C                              OCCASIONALLY SKIP OVER SUBSETS
C                           3) ADDED LOGIC TO MAKE SURE MISSING VALUES
C                              ARE REPRESENTED BY INCREMENTS WITH ALL
C                              BITS ON
C                           4) REMOVED TWO UNECESSARY REFERENCES TO
C                              'WRIT1'
C 2005-11-29  J. ATOR    -- FIX INITIALIZATION BUG FOR CHARACTER
C                           COMPRESSION; INCREASE MXCSB TO 4000;
C                           USE IUPBS01; CHECK EDITION NUMBER OF BUFR
C                           MESSAGE BEFORE PADDING TO AN EVEN BYTE COUNT
C DART $Id: wrcmps.f 4942 2011-06-02 20:51:48Z thoar $
C
C USAGE:    CALL WRCMPS (LUNIX)
C   INPUT ARGUMENT LIST:
C     LUNIX    - INTEGER: ABSOLUTE VALUE IS FORTRAN LOGICAL UNIT NUMBER
C                FOR BUFR FILE (IF LUNIX IS LESS THAN ZERO, THIS IS A
C                "FLUSH" CALL AND THE BUFFER MUST BE CLEARED OUT)
C
C REMARKS:
C    THIS ROUTINE CALLS:        BORT     CMSGINI  IUPBS01  MSGWRT
C                               PKB      PKC      STATUS   UPB
C                               UPC      USRTPL
C    THIS ROUTINE IS CALLED BY: CLOSMG   WRITSA   WRITSB
C                               Normally not called by any application
C                               programs.
C
C ATTRIBUTES:
C   LANGUAGE: FORTRAN 77
C   MACHINE:  PORTABLE TO ALL PLATFORMS
C
C$$$
 
      INCLUDE 'bufrlib.prm'
 
      COMMON /MAXCMP/ MAXCMB,MAXROW,MAXCOL,NCMSGS,NCSUBS,NCBYTS
      COMMON /MSGCWD/ NMSG(NFILES),NSUB(NFILES),MSUB(NFILES),
     .                INODE(NFILES),IDATE(NFILES)
      COMMON /BITBUF/ MAXBYT,IBIT,IBAY(MXMSGLD4),MBYT(NFILES),
     .                MBAY(MXMSGLD4,NFILES)
      COMMON /TABLES/ MAXTAB,NTAB,TAG(MAXJL),TYP(MAXJL),KNT(MAXJL),
     .                JUMP(MAXJL),LINK(MAXJL),JMPB(MAXJL),
     .                IBT(MAXJL),IRF(MAXJL),ISC(MAXJL),
     .                ITP(MAXJL),VALI(MAXJL),KNTI(MAXJL),
     .                ISEQ(MAXJL,2),JSEQ(MAXJL)
      COMMON /USRINT/ NVAL(NFILES),INV(MAXJL,NFILES),VAL(MAXJL,NFILES)
      COMMON /USRBIT/ NBIT(MAXJL),MBIT(MAXJL)
      COMMON /COMPRS/ MATX(MXCDV,MXCSB),CATX(MXCDV,MXCSB),KMIN(MXCDV),
     .                KMAX(MXCDV),KMIS(MXCDV),KBIT(MXCDV),ITYP(MXCDV),
     .                IWID(MXCDV),NROW,NCOL,LUNC,KBYT,WRIT1,FLUSH,
     .                CSTR(MXCDV)
      COMMON /S01CM/  NS01V,CMNEM(MXS01V),IVMNEM(MXS01V)
 
      CHARACTER*128 BORT_STR
      CHARACTER*10  TAG
      CHARACTER*8   CATX,SUBSET,CSTR,CMNEM
      CHARACTER*3   TYP
      DIMENSION     MESG(MXMSGLD4)
 
C     NOTE THE FOLLOWING FLAGS:
C         FIRST - KEEPS TRACK OF WHETHER THE CURRENT SUBSET IS THE
C                 FIRST SUBSET OF A NEW MESSAGE
C         FLUSH - KEEPS TRACK OF WHETHER THIS SUBROUTINE WAS CALLED
C                 WITH LUNIX < 0 IN ORDER TO FORCIBLY FLUSH ANY
C                 PARTIALLY-COMPLETED MESSAGE WITHIN MEMORY (PRESUMABLY
C                 IMMEDIATELY PRIOR TO EXITING THE CALLING PROGRAM!)
C         WRIT1 - KEEPS TRACK OF WHETHER THE CURRENT MESSAGE NEEDS
C                 TO BE WRITTEN OUT
                 
      LOGICAL       FIRST,FLUSH,WRIT1,KMIS,KMISS,EDGE4
      REAL*8        VAL
 
      DATA FIRST/.TRUE./

      SAVE FIRST
 
C-----------------------------------------------------------------------
      RLN2 = 1./LOG(2.)
C-----------------------------------------------------------------------
 
C  GET THE UNIT AND SUBSET TAG
C  ---------------------------
 
      LUNIT = ABS(LUNIX)
      CALL STATUS(LUNIT,LUN,IL,IM)
      SUBSET = TAG(INODE(LUN))
 
C  IF THIS IS A "FIRST" CALL, THEN INITIALIZE SOME VALUES IN
C  ORDER TO PREPARE FOR THE CREATION OF A NEW COMPRESSED BUFR
C  MESSAGE FOR OUTPUT.
 
  1   IF(FIRST) THEN
         KBYT = 0
         NCOL = 0
         LUNC = LUN
         NROW = NVAL(LUN)
         FIRST = .FALSE.
         FLUSH = .FALSE.
         WRIT1 = .FALSE.
 
C        THIS CALL TO CMSGINI IS DONE SOLELY IN ORDER TO DETERMINE
C        HOW MANY BYTES (KBYT) WILL BE TAKEN UP IN A MESSAGE BY
C        THE INFORMATION IN SECTIONS 0, 1, 2 AND 3.  THIS WILL
C        ALLOW US TO KNOW HOW MANY COMPRESSED DATA SUBSETS WILL
C        FIT INTO SECTION 4 WITHOUT OVERFLOWING MAXCMB.  LATER ON,
C        A SEPARATE CALL TO CMSGINI WILL BE DONE TO ACTUALLY
C        INITIALIZE SECTIONS 0, 1, 2 AND 3 OF THE FINAL COMPRESSED
C        BUFR MESSAGE THAT WILL BE WRITTEN OUT.
 
         CALL CMSGINI(LUN,MESG,SUBSET,IDATE(LUN),NCOL,KBYT)

C        CHECK THE EDITION NUMBER OF THE BUFR MESSAGE TO BE CREATED

         EDGE4 = .FALSE.
         IF(NS01V.GT.0) THEN
           II = 1
           DO WHILE ( (.NOT.EDGE4) .AND. (II.LE.NS01V) )
             IF( (CMNEM(II).EQ.'BEN') .AND. (IVMNEM(II).GE.4) ) THEN
               EDGE4 = .TRUE.
             ELSE
               II = II+1
             ENDIF
           ENDDO
         ENDIF

      ENDIF
 
      IF(LUN.NE.LUNC) GOTO 900
 
C  IF THIS IS A "FLUSH" CALL, THEN CLEAR OUT THE BUFFER (NOTE THAT
C  THERE IS NO CURRENT SUBSET TO BE STORED!) AND PREPARE TO WRITE
C  THE FINAL COMPRESSED BUFR MESSAGE.
 
      IF(LUNIX.LT.0) THEN
         IF(NCOL.EQ.0) GOTO 100
         IF(NCOL.GT.0) THEN
            FLUSH = .TRUE.
            WRIT1 = .TRUE.
            ICOL = 1
            GOTO 20
         ENDIF
      ENDIF
 
C  CHECK ON SOME OTHER POSSIBLY PROBLEMATIC SITUATIONS
C  ---------------------------------------------------
 
      IF(NCOL+1.GT.MXCSB) THEN
         GOTO 50
      ELSEIF(NVAL(LUN).NE.NROW) THEN
         GOTO 50
      ELSEIF(NVAL(LUN).GT.MXCDV) THEN
         GOTO 901
      ENDIF
 
C  STORE THE NEXT SUBSET FOR COMPRESSION
C  -------------------------------------
 
C     WILL THE CURRENT SUBSET FIT INTO THE CURRENT MESSAGE?
C     (UNFORTUNATELY, THE ONLY WAY TO FIND OUT IS TO ACTUALLY
C     RE-DO THE COMPRESSION BY RE-COMPUTING ALL OF THE LOCAL
C     REFERENCE VALUES, INCREMENTS, ETC.)
 
 10   NCOL = NCOL+1
      ICOL = NCOL
      IBIT = 16
      DO I=1,NVAL(LUN)
      NODE = INV(I,LUN)
      ITYP(I) = ITP(NODE)
      IWID(I) = IBT(NODE)
      IF(ITYP(I).EQ.1.OR.ITYP(I).EQ.2) THEN
         CALL UPB(MATX(I,NCOL),IBT(NODE),IBAY,IBIT)
      ELSEIF(ITYP(I).EQ.3) THEN
         CALL UPC(CATX(I,NCOL),IBT(NODE)/8,IBAY,IBIT)
      ENDIF
      ENDDO
 
C  COMPUTE THE MIN,MAX,WIDTH FOR EACH ROW - ACCUMULATE LENGTH
C  ----------------------------------------------------------
 
C     LDATA WILL HOLD THE LENGTH IN BITS OF THE COMPRESSED DATA
C     (I.E. THE SUM TOTAL FOR ALL DATA VALUES FOR ALL SUBSETS
C     IN THE MESSAGE)
 
 20   LDATA = 0
      IF(NCOL.LE.0) GOTO 902
      DO I=1,NROW
      IF(ITYP(I).EQ.1 .OR. ITYP(I).EQ.2) THEN
 
C        ROW I OF THE COMPRESSION MATRIX CONTAINS NUMERIC VALUES,
C        SO KMIS(I) WILL STORE:
C          .FALSE. IF ALL SUCH VALUES ARE NON-"MISSING"
C          .TRUE. OTHERWISE 
 
         IMISS = 2**IWID(I)-1
         IF(ICOL.EQ.1) THEN
            KMIN(I) = IMISS
            KMAX(I) = 0
            KMIS(I) = .FALSE.
         ENDIF
         DO J=ICOL,NCOL
         IF(MATX(I,J).LT.IMISS) THEN
            KMIN(I) = MIN(KMIN(I),MATX(I,J))
            KMAX(I) = MAX(KMAX(I),MATX(I,J))
         ELSE
            KMIS(I) = .TRUE.
         ENDIF
         ENDDO
         KMISS = KMIS(I).AND.KMIN(I).LT.IMISS
         RANGE = MAX(1,KMAX(I)-KMIN(I)+1)
         IF(ITYP(I).EQ.1.AND.RANGE.GT.1) THEN
 
C           THE DATA VALUES IN ROW I OF THE COMPRESSION MATRIX
C           ARE DELAYED DESCRIPTOR REPLICATION FACTORS AND ARE
C           NOT ALL IDENTICAL (I.E. RANGE.GT.1), SO WE CANNOT
C           COMPRESS ALL OF THESE SUBSETS INTO THE SAME MESSAGE.
C           ASSUMING THAT NONE OF THE VALUES ARE "MISSING",
C           EXCLUDE THE LAST SUBSET (I.E. THE LAST COLUMN
C           OF THE MATRIX) AND TRY RE-COMPRESSING AGAIN.
 
            IF(KMISS) GOTO 903
            WRIT1 = .TRUE.
            NCOL = NCOL-1
            ICOL = 1
            GOTO 20
         ELSEIF(ITYP(I).EQ.2.AND.(RANGE.GT.1..OR.KMISS)) THEN
 
C           THE DATA VALUES IN ROW I OF THE COMPRESSION MATRIX
C           ARE NUMERIC VALUES THAT ARE NOT ALL IDENTICAL.
C           COMPUTE THE NUMBER OF BITS NEEDED TO HOLD THE
C           LARGEST OF THE INCREMENTS.
 
            KBIT(I) = NINT(LOG(RANGE)*RLN2)
            IF(2**KBIT(I)-1.LE.RANGE) KBIT(I) = KBIT(I)+1

C           HOWEVER, UNDER NO CIRCUMSTANCES SHOULD THIS NUMBER
C           EVER EXCEED THE WIDTH OF THE ORIGINAL UNDERLYING
C           DESCRIPTOR!

            IF(KBIT(I).GT.IWID(I)) KBIT(I) = IWID(I)
         ELSE
 
C           THE DATA VALUES IN ROW I OF THE COMPRESSION MATRIX
C           ARE NUMERIC VALUES THAT ARE ALL IDENTICAL, SO THE
C           INCREMENTS WILL BE OMITTED FROM THE MESSAGE.
          
            KBIT(I) = 0
         ENDIF
         LDATA = LDATA + IWID(I) + 6 + NCOL*KBIT(I)
      ELSEIF(ITYP(I).EQ.3) THEN
 
C        ROW I OF THE COMPRESSION MATRIX CONTAINS CHARACTER VALUES,
C        SO KMIS(I) WILL STORE:
C          .FALSE. IF ALL SUCH VALUES ARE IDENTICAL
C          .TRUE. OTHERWISE
 
         IF(ICOL.EQ.1) THEN
            CSTR(I) = CATX(I,1)
            KMIS(I) = .FALSE.
         ENDIF
         DO J=ICOL,NCOL
            IF ( (.NOT.KMIS(I)) .AND. (CSTR(I).NE.CATX(I,J)) ) THEN
               KMIS(I) = .TRUE.
            ENDIF
         ENDDO
         IF (KMIS(I)) THEN
 
C           THE DATA VALUES IN ROW I OF THE COMPRESSION MATRIX
C           ARE CHARACTER VALUES THAT ARE NOT ALL IDENTICAL.
 
            KBIT(I) = IWID(I)
         ELSE
 
C           THE DATA VALUES IN ROW I OF THE COMPRESSION MATRIX
C           ARE CHARACTER VALUES THAT ARE ALL IDENTICAL, SO THE
C           INCREMENTS WILL BE OMITTED FROM THE MESSAGE.
 
            KBIT(I) = 0
         ENDIF
         LDATA = LDATA + IWID(I) + 6 + NCOL*KBIT(I)
      ENDIF
      ENDDO
 
C  ROUND DATA LENGTH UP TO A WHOLE BYTE COUNT
C  ------------------------------------------
 
      IBYT = (LDATA+8-MOD(LDATA,8))/8

C     DEPENDING ON THE EDITION NUMBER OF THE MESSAGE, WE NEED TO ENSURE
C     THAT WE ROUND TO AN EVEN BYTE COUNT

      IF( (.NOT.EDGE4) .AND. (MOD(IBYT,2).NE.0) ) IBYT = IBYT+1

      JBIT = IBYT*8-LDATA
 
C  CHECK ON COMPRESSED MESSAGE LENGTH, EITHER WRITE/RESTORE OR RETURN
C  ------------------------------------------------------------------
 
      IF(IBYT+KBYT+8.GT.MAXCMB) THEN
 
C        THE CURRENT SUBSET WILL NOT FIT INTO THE CURRENT MESSAGE.
C        SET THE FLAG TO INDICATE THAT A MESSAGE WRITE IS NEEDED,
C        THEN GO BACK AND RE-COMPRESS THE SECTION 4 DATA FOR THIS
C        MESSAGE WHILE *EXCLUDING* THE DATA FOR THE CURRENT SUBSET
C        (WHICH WILL BE HELD AND STORED AS THE FIRST SUBSET OF A
C        NEW MESSAGE AFTER WRITING THE CURRENT MESSAGE!).
 
         WRIT1 = .TRUE.
         NCOL = NCOL-1
         ICOL = 1
         GOTO 20
      ELSEIF(.NOT.WRIT1) THEN
 
C        ADD THE CURRENT SUBSET TO THE CURRENT MESSAGE AND RETURN.
 
         CALL USRTPL(LUN,1,1)
         NSUB(LUN) = -NCOL
         GOTO 100
      ENDIF
 
C  WRITE THE COMPLETE COMPRESSED MESSAGE
C  -------------------------------------
 
C     NOW IT IS TIME TO DO THE "REAL" CALL TO CMSGINI TO ACTUALLY
C     INITIALIZE SECTIONS 0, 1, 2 AND 3 OF THE FINAL COMPRESSED
C     BUFR MESSAGE THAT WILL BE WRITTEN OUT.
 
 50   CALL CMSGINI(LUN,MESG,SUBSET,IDATE(LUN),NCOL,IBYT)
 
C     NOW ADD THE SECTION 4 DATA.
 
      IBIT = IBYT*8
      DO I=1,NROW
      IF(ITYP(I).EQ.1.OR.ITYP(I).EQ.2) THEN
         CALL PKB(KMIN(I),IWID(I),MESG,IBIT)
         CALL PKB(KBIT(I),      6,MESG,IBIT)
         IF(KBIT(I).GT.0) THEN
            DO J=1,NCOL
            IF(MATX(I,J).LT.2**IWID(I)-1) THEN
               INCR = MATX(I,J)-KMIN(I) 
            ELSE 
               INCR = 2**KBIT(I)-1
            ENDIF
            CALL PKB(INCR,KBIT(I),MESG,IBIT)
            ENDDO
         ENDIF
      ELSEIF(ITYP(I).EQ.3) THEN
         NCHR = IWID(I)/8
         IF(KBIT(I).GT.0) THEN
            CALL PKB(   0,IWID(I),MESG,IBIT)
            CALL PKB(NCHR,      6,MESG,IBIT)
            DO J=1,NCOL
               CALL PKC(CATX(I,J),NCHR,MESG,IBIT)
            ENDDO
         ELSE
            CALL PKC(CSTR(I),NCHR,MESG,IBIT)
            CALL PKB(      0,   6,MESG,IBIT)
         ENDIF
      ENDIF
      ENDDO
 
C  FILL IN THE END OF THE MESSAGE
C  ------------------------------
 
C     PAD THE END OF SECTION 4 WITH ZEROES UP TO THE NECESSARY
C     BYTE COUNT.
 
      CALL PKB(     0,JBIT,MESG,IBIT)
 
C     ADD SECTION 5.
 
      CALL PKC('7777',   4,MESG,IBIT)
 
C  SEE THAT THE MESSAGE BYTE COUNTERS AGREE THEN WRITE A MESSAGE
C  -------------------------------------------------------------
 
      IF(MOD(IBIT,8).NE.0) GOTO 904
      LBYT = IUPBS01(MESG,'LENM')
      NBYT = IBIT/8
      IF(NBYT.NE.LBYT) GOTO 905
 
      CALL MSGWRT(LUNIT,MESG,NBYT)
 
      MAXROW = MAX(MAXROW,NROW)
      MAXCOL = MAX(MAXCOL,NCOL)
      NCMSGS = NCMSGS+1
      NCSUBS = NCSUBS+NCOL
      NCBYTS = NCBYTS+NBYT
 
C  RESET
C  -----
    
C     NOW, UNLESS THIS WAS A "FLUSH" CALL TO THIS SUBROUTINE, GO BACK
C     AND INITIALIZE A NEW MESSAGE TO HOLD THE CURRENT SUBSET THAT WE
C     WERE NOT ABLE TO FIT INTO THE MESSAGE THAT WAS JUST WRITTEN OUT. 
 
      FIRST = .TRUE.
      IF(.NOT.FLUSH) GOTO 1
 
C  EXITS
C  -----
 
100   RETURN
900   WRITE(BORT_STR,'("BUFRLIB: WRCMPS - I/O STREAM INDEX FOR THIS '//
     . 'CALL (",I3,") .NE. I/O STREAM INDEX FOR INITIAL CALL (",I3,")'//
     . ' - UNIT NUMBER NOW IS",I4)') LUN,LUNC,LUNIX
      CALL BORT(BORT_STR)
901   WRITE(BORT_STR,'("BUFRLIB: WRCMPS - NO. OF ELEMENTS IN THE '//
     . 'SUBSET (",I6,") .GT. THE NO. OF ROWS ALLOCATED FOR THE '//
     . 'COMPRESSION MATRIX (",I6,")")') NVAL(LUN),MXCDV
      CALL BORT(BORT_STR)
902   WRITE(BORT_STR,'("BUFRLIB: WRCMPS - NO. OF COLUMNS CALCULATED '//
     . 'FOR COMPRESSION MAXRIX IS .LE. 0 (=",I6,")")') NCOL
      CALL BORT(BORT_STR)
903   CALL BORT('BUFRLIB: WRCMPS - MISSING DELAYED REPLICATION FACTOR')
904   CALL BORT('BUFRLIB: WRCMPS - THE NUMBER OF BITS IN THE '//
     . 'COMPRESSED BUFR MSG IS NOT A MULTIPLE OF 8 - MSG MUST END ON '//
     . ' A BYTE BOUNDARY')
905   WRITE(BORT_STR,'("BUFRLIB: WRCMPS - OUTPUT MESSAGE LENGTH FROM '//
     . 'SECTION 0",I6," DOES NOT EQUAL FINAL PACKED MESSAGE LENGTH ("'//
     .',I6,")")') LBYT,NBYT
      CALL BORT(BORT_STR)
      END
