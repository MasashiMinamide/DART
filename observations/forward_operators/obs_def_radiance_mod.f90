! DART software - Copyright 2004 - 2013 UCAR. This open source software is
! provided by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download
!
! $Id: obs_def_radiance_mod.f90 11371 2017-03-17 22:00:13Z nancy@ucar.edu $

! This module supports the observation types from the AIRS instruments.
! http://winds.jpl.nasa.gov/missions/quikscat/index.cfm

! BEGIN DART PREPROCESS KIND LIST
! AMSUA_METOP_A_CH5,            QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_METOP_A_CH6,            QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_METOP_A_CH7,            QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_METOP_A_CH8,            QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_METOP_A_CH9,            QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N15_CH5,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N15_CH6,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N15_CH7,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N15_CH8,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N15_CH9,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N18_CH5,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N18_CH6,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N18_CH7,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N18_CH8,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N18_CH9,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N19_CH5,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N19_CH6,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N19_CH7,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N19_CH8,                QTY_TEMPERATURE,        COMMON_CODE
! AMSUA_N19_CH9,                QTY_TEMPERATURE,        COMMON_CODE
! MHS_METOP_A_CH3,              QTY_TEMPERATURE,        COMMON_CODE
! MHS_METOP_A_CH4,              QTY_TEMPERATURE,        COMMON_CODE
! MHS_METOP_A_CH5,              QTY_TEMPERATURE,        COMMON_CODE
! MHS_N18_CH3,                  QTY_TEMPERATURE,        COMMON_CODE
! MHS_N18_CH4,                  QTY_TEMPERATURE,        COMMON_CODE
! MHS_N18_CH5,                  QTY_TEMPERATURE,        COMMON_CODE
! END DART PREPROCESS KIND LIST

! <next few lines under version control, do not edit>
! $URL: https://svn-dares-dart.cgd.ucar.edu/DART/releases/Manhattan/observations/forward_operators/obs_def_radiance_mod.f90 $
! $Id: obs_def_radiance_mod.f90 11371 2017-03-17 22:00:13Z nancy@ucar.edu $
! $Revision: 11371 $
! $Date: 2017-03-17 18:00:13 -0400 (Fri, 17 Mar 2017) $
