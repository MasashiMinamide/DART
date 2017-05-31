      SUBROUTINE DRFINI(LUNIT,MDRF,NDRF,DRFTAG)

C$$$  SUBPROGRAM DOCUMENTATION BLOCK
C
C SUBPROGRAM:    DRFINI
C   PRGMMR: WOOLLEN          ORG: NP20       DATE: 2002-05-14
C
C ABSTRACT:  THIS SUBROUTINE INITIALIZES DELAYED REPLICATION FACTORS
C   AND EXPLICITLY ALLOCATES A CORRESPONDING AMOUNT OF SPACE IN THE
C   INTERNAL SUBSET ARRAYS, THEREBY ALLOWING THE SUBSEQUENT USE OF BUFR
C   ARCHIVE LIBRARY SUBROUTINE UFBSEQ TO WRITE DATA DIRECTLY INTO
C   DELAYED REPLICATION SEQUENCES.  NOTE THAT THIS SAME TYPE OF
C   INITIALIZATION IS DONE IMPLICTLY WITHIN BUFR ARCHIVE LIBRARY
C   SUBROUTINE UFBINT FOR DELAYED REPLICATION SEQUENCES WHICH APPEAR
C   ONLY ONE TIME WITHIN AN OVERALL SUBSET DEFINITION.  HOWEVER, BY
C   USING SUBROUTINE DRFINI ALONG WITH A SUBSEQUENT CALL TO SUBROUTINE
C   UFBSEQ, IT IS ACTUALLY POSSIBLE TO HAVE MULTIPLE OCCURRENCES OF A
C   PARTICULAR DELAYED REPLICATION SEQUENCE WITHIN A SINGLE OVERALL
C   SUBSET DEFINITION.
C
C PROGRAM HISTORY LOG:
C 2002-05-14  J. WOOLLEN -- ORIGINAL AUTHOR
C 2003-11-04  S. BENDER  -- ADDED REMARKS/BUFRLIB ROUTINE
C                           INTERDEPENDENCIES
C 2003-11-04  D. KEYSER  -- MAXJL (MAXIMUM NUMBER OF JUMP/LINK ENTRIES)
C                           INCREASED FROM 15000 TO 16000 (WAS IN
C                           VERIFICATION VERSION); UNIFIED/PORTABLE FOR
C                           WRF; ADDED DOCUMENTATION (INCLUDING
C                           HISTORY); OUTPUTS MORE COMPLETE DIAGNOSTIC
C                           INFO WHEN ROUTINE TERMINATES ABNORMALLY
C 2005-03-04  J. ATOR    -- UPDATED DOCUMENTATION
C DART $Id: drfini.f 4942 2011-06-02 20:51:48Z thoar $
C
C USAGE:    CALL DRFINI (LUNIT, MDRF, NDRF, DRFTAG)
C   INPUT ARGUMENT LIST:
C     LUNIT    - INTEGER: FORTRAN LOGICAL UNIT NUMBER FOR BUFR FILE
C     MDRF     - INTEGER: ARRAY OF DELAYED REPLICATION FACTORS,
C                IN ONE-TO-ONE CORRESPONDENCE WITH THE NUMBER OF
C                OCCURRENCES OF DRFTAG WITHIN THE OVERALL SUBSET
C                DEFINITION, AND EXPLICITLY DEFINING HOW MUCH SPACE
C                (I.E. HOW MANY REPLICATIONS) TO ALLOCATE WITHIN
C                EACH SUCCESSIVE OCCURRENCE
C     NDRF     - INTEGER: NUMBER OF DELAYED REPLICATION FACTORS
C                WITHIN MDRF
C     DRFTAG   - CHARACTER*(*): SEQUENCE MNEMONIC, BRACKETED BY 
C                APPROPRIATE DELAYED REPLICATION NOTATION
C                (E.G. {}, () OR <>) 
C
C REMARKS:
C    THIS ROUTINE CALLS:        BORT     STATUS   USRTPL
C    THIS ROUTINE IS CALLED BY: None
C                               Normally called only by application
C                               programs
C
C ATTRIBUTES:
C   LANGUAGE: FORTRAN 77
C   MACHINE:  PORTABLE TO ALL PLATFORMS
C
C$$$

      INCLUDE 'bufrlib.prm'

      COMMON /TABLES/ MAXTAB,NTAB,TAG(MAXJL),TYP(MAXJL),KNT(MAXJL),
     .                JUMP(MAXJL),LINK(MAXJL),JMPB(MAXJL),
     .                IBT(MAXJL),IRF(MAXJL),ISC(MAXJL),
     .                ITP(MAXJL),VALI(MAXJL),KNTI(MAXJL),
     .                ISEQ(MAXJL,2),JSEQ(MAXJL)
      COMMON /USRINT/ NVAL(NFILES),INV(MAXJL,NFILES),VAL(MAXJL,NFILES)

      CHARACTER*(*) DRFTAG
      CHARACTER*128 BORT_STR
      CHARACTER*10  TAG
      CHARACTER*3   TYP
      REAL*8        VAL
      DIMENSION     MDRF(NDRF)

C-----------------------------------------------------------------------
C-----------------------------------------------------------------------

      IF(NDRF.GT.100) GOTO 900

      CALL STATUS(LUNIT,LUN,IL,IM)

C  COMFORM THE TEMPLATES TO THE DELAYED REPLICATION FACTORS
C  --------------------------------------------------------

      M = 0
      N = 0

10    DO N=N+1,NVAL(LUN)
      NODE = INV(N,LUN)
      IF(ITP(NODE).EQ.1 .AND. TAG(NODE).EQ.DRFTAG) THEN
         M = M+1
         CALL USRTPL(LUN,N,MDRF(M))
         GOTO 10
      ENDIF
      ENDDO

C  EXITS
C  -----

      RETURN
 900  WRITE(BORT_STR,'("BUFRLIB: DRFINI - THE NUMBER OF DELAYED '//
     . 'REPLICATION FACTORS (",I5,") EXCEEDS THE LIMIT (100)")') NDRF
      CALL BORT(BORT_STR)
      END
