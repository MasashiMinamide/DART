! DART software - Copyright UCAR. This open source software is provided
! by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download
!
! $Id: filter_mod.f90 11474 2017-04-13 15:26:47Z nancy@ucar.edu $

module filter_mod

!------------------------------------------------------------------------------
use types_mod,             only : r8, i8, missing_r8, metadatalength, MAX_NUM_DOMS
use obs_sequence_mod,      only : read_obs_seq, obs_type, obs_sequence_type,                  &
                                  get_obs_from_key, set_copy_meta_data, get_copy_meta_data,   &
                                  get_obs_def, get_time_range_keys, set_obs_values, set_obs,  &
                                  write_obs_seq, get_num_obs, get_obs_values, init_obs,       &
                                  assignment(=), get_num_copies, get_qc, get_num_qc, set_qc,  &
                                  static_init_obs_sequence, destroy_obs, read_obs_seq_header, &
                                  set_qc_meta_data, get_first_obs, get_obs_time_range,        &
                                  delete_obs_from_seq, delete_seq_head,                       &
                                  delete_seq_tail, replace_obs_values, replace_qc,            &
                                  destroy_obs_sequence, get_qc_meta_data, add_qc
                                 
use obs_def_mod,           only : obs_def_type, get_obs_def_error_variance, get_obs_def_time, &
                                  get_obs_def_type_of_obs
use obs_def_utilities_mod, only : set_debug_fwd_op
use time_manager_mod,      only : time_type, get_time, set_time, operator(/=), operator(>),   &
                                  operator(-), print_time
use utilities_mod,         only : register_module,  error_handler, E_ERR, E_MSG, E_DBG,       &
                                  logfileunit, nmlfileunit, timestamp,  &
                                  do_output, find_namelist_in_file, check_namelist_read,      &
                                  open_file, close_file, do_nml_file, do_nml_term, to_upper
use assim_model_mod,       only : static_init_assim_model, get_model_size,                    &
                                  end_assim_model,  pert_model_copies
use assim_tools_mod,       only : filter_assim, set_assim_tools_trace, get_missing_ok_status, &
                                  test_state_copies
use obs_model_mod,         only : move_ahead, advance_state, set_obs_model_trace
use ensemble_manager_mod,  only : init_ensemble_manager, end_ensemble_manager,                &
                                  ensemble_type, get_copy, get_my_num_copies, put_copy,       &
                                  all_vars_to_all_copies, all_copies_to_all_vars,             &
                                  compute_copy_mean, compute_copy_mean_sd,                    &
                                  compute_copy_mean_var, duplicate_ens, get_copy_owner_index, &
                                  get_ensemble_time, set_ensemble_time, broadcast_copy,       &
                                  prepare_to_read_from_vars, prepare_to_write_to_vars,        &
                                  prepare_to_read_from_copies,  get_my_num_vars,              &
                                  prepare_to_write_to_copies, get_ensemble_time,              &
                                  map_task_to_pe,  map_pe_to_task, prepare_to_update_copies,  &
                                  copies_in_window, set_num_extra_copies, get_allow_transpose, &
                                  all_copies_to_all_vars, allocate_single_copy, allocate_vars, &
                                  get_single_copy, put_single_copy, deallocate_single_copy,   &
                                  print_ens_handle
use adaptive_inflate_mod,  only : do_varying_ss_inflate,                                      &
                                  do_single_ss_inflate, inflate_ens, adaptive_inflate_init,   &
                                  adaptive_inflate_type, set_inflation_mean_copy ,            &
                                  log_inflation_info, set_inflation_sd_copy,                  &
                                  get_minmax_task_zero, do_rtps_inflate
use mpi_utilities_mod,     only : my_task_id, task_sync, broadcast_send, broadcast_recv,      &
                                  task_count
use smoother_mod,          only : smoother_read_restart, advance_smoother,                    &
                                  smoother_gen_copy_meta_data, smoother_write_restart,        &
                                  init_smoother, do_smoothing, smoother_mean_spread,          &
                                  smoother_assim,                                             &
                                  smoother_ss_diagnostics, smoother_end, set_smoother_trace

use random_seq_mod,        only : random_seq_type, init_random_seq, random_gaussian

use state_vector_io_mod,   only : state_vector_io_init, read_state, write_state, &
                                  set_stage_to_write, get_stage_to_write

use io_filenames_mod,      only : io_filenames_init, file_info_type, &
                                  combine_file_info, set_file_metadata,  &
                                  set_member_file_metadata, &
                                  set_io_copy_flag, check_file_info_variable_shape, &
                                  query_copy_present, COPY_NOT_PRESENT, &
                                  READ_COPY, WRITE_COPY, READ_WRITE_COPY

use forward_operator_mod,  only : get_obs_ens_distrib_state

use quality_control_mod,   only : initialize_qc

use single_file_io_mod,  only : finalize_singlefile_output

!------------------------------------------------------------------------------

implicit none
private

public :: filter_sync_keys_time, &
          filter_set_initial_time, &
          filter_main

! version controlled file description for error handling, do not edit
character(len=256), parameter :: source   = &
   "$URL: https://svn-dares-dart.cgd.ucar.edu/DART/releases/Manhattan/assimilation_code/modules/assimilation/filter_mod.f90 $"
character(len=32 ), parameter :: revision = "$Revision: 11474 $"
character(len=128), parameter :: revdate  = "$Date: 2017-04-13 11:26:47 -0400 (Thu, 13 Apr 2017) $"

! Some convenient global storage items
character(len=512)      :: msgstring
type(obs_type)          :: observation

integer                 :: trace_level, timestamp_level

! Defining whether diagnostics are for prior or posterior
integer, parameter :: PRIOR_DIAG = 0, POSTERIOR_DIAG = 2

! Determine if inflation it turned on or off for reading and writing
! inflation restart files
logical :: output_inflation = .false.

! Ensemble copy numbers
integer :: ENS_MEM_START            = COPY_NOT_PRESENT
integer :: ENS_MEM_END              = COPY_NOT_PRESENT
integer :: ENS_MEAN_COPY            = COPY_NOT_PRESENT
integer :: ENS_SD_COPY              = COPY_NOT_PRESENT
integer :: PRIOR_INF_COPY           = COPY_NOT_PRESENT
integer :: PRIOR_INF_SD_COPY        = COPY_NOT_PRESENT
integer :: POST_INF_COPY            = COPY_NOT_PRESENT
integer :: POST_INF_SD_COPY         = COPY_NOT_PRESENT
integer :: INPUT_MEAN               = COPY_NOT_PRESENT
integer :: INPUT_SD                 = COPY_NOT_PRESENT
integer :: PREASSIM_MEM_START       = COPY_NOT_PRESENT
integer :: PREASSIM_MEM_END         = COPY_NOT_PRESENT
integer :: PREASSIM_MEAN            = COPY_NOT_PRESENT
integer :: PREASSIM_SD              = COPY_NOT_PRESENT
integer :: PREASSIM_PRIORINF_MEAN   = COPY_NOT_PRESENT
integer :: PREASSIM_PRIORINF_SD     = COPY_NOT_PRESENT
integer :: PREASSIM_POSTINF_MEAN    = COPY_NOT_PRESENT
integer :: PREASSIM_POSTINF_SD      = COPY_NOT_PRESENT
integer :: POSTASSIM_MEM_START      = COPY_NOT_PRESENT
integer :: POSTASSIM_MEM_END        = COPY_NOT_PRESENT
integer :: POSTASSIM_MEAN           = COPY_NOT_PRESENT
integer :: POSTASSIM_SD             = COPY_NOT_PRESENT
integer :: POSTASSIM_PRIORINF_MEAN  = COPY_NOT_PRESENT
integer :: POSTASSIM_PRIORINF_SD    = COPY_NOT_PRESENT
integer :: POSTASSIM_POSTINF_MEAN   = COPY_NOT_PRESENT
integer :: POSTASSIM_POSTINF_SD     = COPY_NOT_PRESENT
integer :: SPARE_PRIOR_SPREAD       = COPY_NOT_PRESENT

logical :: do_prior_inflate     = .false.
logical :: do_posterior_inflate = .false.

logical :: has_cycling                  = .false. ! filter will advance the model

!----------------------------------------------------------------
! Namelist input with default values
!
integer  :: async = 0, ens_size = 20
integer  :: tasks_per_model_advance = 1
! if init_time_days and seconds are negative initial time is 0, 0
! for no restart or comes from restart if restart exists
integer  :: init_time_days    = 0
integer  :: init_time_seconds = 0
! Time of first and last observations to be used from obs_sequence
! If negative, these are not used
integer  :: first_obs_days      = -1
integer  :: first_obs_seconds   = -1
integer  :: last_obs_days       = -1
integer  :: last_obs_seconds    = -1
! Assimilation window; defaults to model timestep size.
integer  :: obs_window_days     = -1
integer  :: obs_window_seconds  = -1
! Control diagnostic output for state variables
integer  :: num_output_state_members = 0
integer  :: num_output_obs_members   = 0
integer  :: output_interval     = 1
integer  :: num_groups          = 1
logical  :: output_forward_op_errors = .false.
logical  :: output_timestamps        = .false.
logical  :: trace_execution          = .false.
logical  :: silence                  = .false.
logical  :: distributed_state = .true. ! Default to do state complete forward operators.

! IO options
! Names of files given explicitly in namelist
integer, parameter :: MAXFILES = 200
!>@todo FIXME - how does this work for multiple domains?  ens1d1, ens2d1, ... ens1d2 or
!> ens1d1 ens1d2, ens1d1 ens2d2, etc   i like the latter better.
character(len=256) ::  input_state_files(MAXFILES) = 'null' 
character(len=256) :: output_state_files(MAXFILES) = 'null' 
! Name of files containing a list of {input,output} restart files, 1 file per domain
character(len=256) ::  input_state_file_list(MAX_NUM_DOMS) = 'null' 
character(len=256) :: output_state_file_list(MAX_NUM_DOMS) = 'null'
! Read in a single file and perturb this to create an ensemble
logical            :: perturb_from_single_instance = .false.
real(r8)           :: perturbation_amplitude       = 0.2_r8
! File options.  Single vs. Multiple.
logical            :: single_file_in               = .false. ! all copies read  from 1 file
logical            :: single_file_out              = .false. ! all copies written to 1 file
! Stages to write.  Valid values include:
!    input, preassim, postassim, output
character(len=10)  :: stages_to_write(4) = (/"output    ", "null      ", "null      ", "null      "/)

!>@todo FIXME
!> for preassim and postassim output it might be we should
!> be controlling the writing of individual ensemble members
!> by looking at the num_output_state_member value.  0 means
!> don't write any members, otherwise it's a count.  and for
!> completeness, there could be a count for pre and a count for post.

logical :: output_members   = .true.
logical :: output_mean      = .true.
logical :: output_sd        = .true.
logical :: write_all_stages_at_end = .false.

character(len=256) :: obs_sequence_in_name  = "obs_seq.out",    &
                      obs_sequence_out_name = "obs_seq.final",  &
                      adv_ens_command       = './advance_model.csh'

!                  == './advance_model.csh'    -> advance ensemble using a script

! Inflation namelist entries follow, first entry for prior, second for posterior
! inf_flavor is 0:none, 1:obs space, 2: varying state space, 3: fixed state_space,
! 4 is rtps (relax to prior spread)
integer              :: inf_flavor(2)                  = 0
logical              :: inf_initial_from_restart(2)    = .false.
logical              :: inf_sd_initial_from_restart(2) = .false.
logical              :: inf_deterministic(2)           = .true.
real(r8)             :: inf_initial(2)                 = 1.0_r8
real(r8)             :: inf_sd_initial(2)              = 0.0_r8
real(r8)             :: inf_damping(2)                 = 1.0_r8
real(r8)             :: inf_lower_bound(2)             = 1.0_r8
real(r8)             :: inf_upper_bound(2)             = 1000000.0_r8
real(r8)             :: inf_sd_lower_bound(2)          = 0.0_r8

namelist /filter_nml/ async, adv_ens_command, ens_size, tasks_per_model_advance, &
   output_members, obs_sequence_in_name, obs_sequence_out_name, &
   init_time_days, init_time_seconds, &
   first_obs_days, first_obs_seconds, last_obs_days, last_obs_seconds, &
   obs_window_days, obs_window_seconds, &
   num_output_state_members, num_output_obs_members, &
   output_interval, num_groups, trace_execution, &
   output_forward_op_errors, output_timestamps, &
   inf_flavor, inf_initial_from_restart, inf_sd_initial_from_restart, &
   inf_deterministic, inf_damping, &
   inf_initial, inf_sd_initial, &
   inf_lower_bound, inf_upper_bound, inf_sd_lower_bound, &
   silence, &
   distributed_state, &
   single_file_in, single_file_out, &
   perturb_from_single_instance, perturbation_amplitude, &
   stages_to_write, &
   input_state_files, output_state_files, &
   output_state_file_list, input_state_file_list, &
   output_mean, output_sd, write_all_stages_at_end


!----------------------------------------------------------------

contains

!----------------------------------------------------------------
!> The code does not use %vars arrays except:
!> * Task 0 still writes the obs_sequence file, so there is a transpose (copies to vars) and
!> sending the obs_fwd_op_ens_handle%vars to task 0. Keys is also size obs%vars.
!> * If you read dart restarts state_ens_handle%vars is allocated.
!> * If you write dart diagnostics state_ens_handle%vars is allocated.
!> * If you are not doing distributed forward operators state_ens_handle%vars is allocated
subroutine filter_main()

type(ensemble_type)         :: state_ens_handle, obs_fwd_op_ens_handle, qc_ens_handle
type(obs_sequence_type)     :: seq
type(time_type)             :: time1, first_obs_time, last_obs_time
type(time_type)             :: curr_ens_time, next_ens_time, window_time
type(adaptive_inflate_type) :: prior_inflate, post_inflate

integer,    allocatable :: keys(:)
integer(i8)             :: model_size
integer                 :: i, j, iunit, io, time_step_number, num_obs_in_set
integer                 :: last_key_used, key_bounds(2)
integer                 :: in_obs_copy, obs_val_index
integer                 :: prior_obs_mean_index, posterior_obs_mean_index
integer                 :: prior_obs_spread_index, posterior_obs_spread_index
! Global indices into ensemble storage - observations
integer                 :: OBS_VAL_COPY, OBS_ERR_VAR_COPY, OBS_KEY_COPY
integer                 :: OBS_GLOBAL_QC_COPY,OBS_EXTRA_QC_COPY
integer                 :: OBS_MEAN_START, OBS_MEAN_END
integer                 :: OBS_VAR_START, OBS_VAR_END, TOTAL_OBS_COPIES
integer                 :: input_qc_index, DART_qc_index
integer                 :: num_state_ens_copies
logical                 :: read_time_from_file

integer :: num_extras ! the extra ensemble copies

type(file_info_type) :: file_info_input
type(file_info_type) :: file_info_preassim
type(file_info_type) :: file_info_postassim
type(file_info_type) :: file_info_output
type(file_info_type) :: file_info_all

logical                 :: ds, all_gone, allow_missing

! real(r8), allocatable   :: temp_ens(:) ! for smoother
real(r8), allocatable   :: prior_qc_copy(:)

call filter_initialize_modules_used() ! static_init_model called in here

! Read the namelist entry
call find_namelist_in_file("input.nml", "filter_nml", iunit)
read(iunit, nml = filter_nml, iostat = io)
call check_namelist_read(iunit, io, "filter_nml")

! Record the namelist values used for the run ...
if (do_nml_file()) write(nmlfileunit, nml=filter_nml)
if (do_nml_term()) write(     *     , nml=filter_nml)

if (task_count() == 1) distributed_state = .true.

call set_debug_fwd_op(output_forward_op_errors)
call set_trace(trace_execution, output_timestamps, silence)

call     trace_message('Filter start')
call timestamp_message('Filter start')

! Make sure ensemble size is at least 2 (NEED MANY OTHER CHECKS)
if(ens_size < 2) then
   write(msgstring, *) 'ens_size in namelist is ', ens_size, ': Must be > 1'
   call error_handler(E_ERR,'filter_main', msgstring, source, revision, revdate)
endif

! informational message to log
write(msgstring, '(A,I5)') 'running with an ensemble size of ', ens_size
call error_handler(E_MSG,'filter:', msgstring, source, revision, revdate)

! See if smoothing is turned on
ds = do_smoothing()

! Make sure inflation options are legal - this should be in the inflation module
! and not here.  FIXME!
do i = 1, 2
   if(inf_flavor(i) < 0 .or. inf_flavor(i) > 4) then
      write(msgstring, *) 'inf_flavor=', inf_flavor(i), ' Must be 0, 1, 2, 3, or 4 '
      call error_handler(E_ERR,'filter_main', msgstring, source, revision, revdate)
   endif
   if(inf_damping(i) < 0.0_r8 .or. inf_damping(i) > 1.0_r8) then
      write(msgstring, *) 'inf_damping=', inf_damping(i), ' Must be 0.0 <= d <= 1.0'
      call error_handler(E_ERR,'filter_main', msgstring, source, revision, revdate)
   endif
end do

! Check to see if state space inflation is turned on
if (inf_flavor(1) > 1 )                           do_prior_inflate     = .true.
if (inf_flavor(2) > 1 )                           do_posterior_inflate = .true.
if (do_prior_inflate .or. do_posterior_inflate)   output_inflation     = .true.

! Observation space inflation not currently supported
if(inf_flavor(1) == 1 .or. inf_flavor(2) == 1) call error_handler(E_ERR, 'filter_main', &
   'observation space inflation (type 1) not currently supported', source, revision, revdate, &
   text2='contact DART developers if you are interested in using it.')

! Relaxation-to-prior-spread (RTPS) is only an option for posterior inflation
if(inf_flavor(1) == 4) call error_handler(E_ERR, 'filter_main', &
   'RTPS inflation (type 4) only supported for Posterior inflation', source, revision, revdate)

! RTPS needs a single parameter from namelist: inf_initial(2).  
! Do not read in any files.  Also, no damping.  but warn the user if they try to set different
! values in the namelist.
if ( inf_flavor(2) == 4 ) then
   if (inf_initial_from_restart(2) .or. inf_sd_initial_from_restart(2)) &
      call error_handler(E_MSG, 'filter_main', 'RTPS inflation (type 4) overrides posterior inflation restart file with value in namelist', &
         text2='posterior inflation standard deviation value not used in RTPS')
   inf_initial_from_restart(2) = .false.    ! Get parameter from namelist inf_initial(2), not from file
   inf_sd_initial_from_restart(2) = .false. ! inf_sd not used in this algorithm

   if (.not. inf_deterministic(2)) &
      call error_handler(E_MSG, 'filter_main', 'RTPS inflation (type 4) overrides posterior inf_deterministic with .true.')
   inf_deterministic(2) = .true.  ! this algorithm is deterministic

   if (inf_damping(2) /= 1.0_r8) &
      call error_handler(E_MSG, 'filter_main', 'RTPS inflation (type 4) disables posterior inf_damping')
   inf_damping(2) = 1.0_r8  ! no damping
endif


call trace_message('Before initializing inflation')

! Initialize the adaptive inflation module
call adaptive_inflate_init(prior_inflate, inf_flavor(1), inf_initial_from_restart(1), &
   inf_sd_initial_from_restart(1), output_inflation, inf_deterministic(1),            &
   inf_initial(1), inf_sd_initial(1), inf_lower_bound(1), inf_upper_bound(1),         &
   inf_sd_lower_bound(1), state_ens_handle,                                           &
   allow_missing, 'Prior')

call adaptive_inflate_init(post_inflate, inf_flavor(2), inf_initial_from_restart(2),  &
   inf_sd_initial_from_restart(2), output_inflation, inf_deterministic(2),            &
   inf_initial(2),  inf_sd_initial(2), inf_lower_bound(2), inf_upper_bound(2),        &
   inf_sd_lower_bound(2), state_ens_handle,                                           &
   allow_missing, 'Posterior')

if (do_output()) then
   if (inf_flavor(1) > 0 .and. inf_damping(1) < 1.0_r8) then
      write(msgstring, '(A,F12.6,A)') 'Prior inflation damping of ', inf_damping(1), ' will be used'
      call error_handler(E_MSG,'filter:', msgstring)
   endif
   if (inf_flavor(2) > 0 .and. inf_damping(2) < 1.0_r8) then
      write(msgstring, '(A,F12.6,A)') 'Posterior inflation damping of ', inf_damping(2), ' will be used'
      call error_handler(E_MSG,'filter:', msgstring)
   endif
endif

call trace_message('After  initializing inflation')

! for now, set 'has_cycling' to match 'single_file_out' since we're only supporting
! multi-file output for a single pass through filter, and allowing cycling if we're
! writing to a single file.

has_cycling = single_file_out

! don't allow cycling and write all at end - might never be supported
if (has_cycling .and. write_all_stages_at_end) then
   call error_handler(E_ERR,'filter:', &
         'advancing the model inside filter and writing all state data at end not supported', &
          source, revision, revdate, text2='delaying write until end only supported when advancing model outside filter', &
          text3='set "write_all_stages_at_end=.false." to cycle and write data as it is computed')
endif

! Setup the indices into the ensemble storage:

! Can't output more ensemble members than exist
if(num_output_state_members > ens_size) num_output_state_members = ens_size
if(num_output_obs_members   > ens_size) num_output_obs_members   = ens_size

! Set up stages to write : input, preassim, postassim, output
call parse_stages_to_write(stages_to_write)

! Count and set up State copy numbers
num_state_ens_copies = count_state_ens_copies(ens_size)
num_extras           = num_state_ens_copies - ens_size

! Observation
OBS_ERR_VAR_COPY     = ens_size + 1
OBS_VAL_COPY         = ens_size + 2
OBS_KEY_COPY         = ens_size + 3
OBS_GLOBAL_QC_COPY   = ens_size + 4
OBS_EXTRA_QC_COPY    = ens_size + 5
OBS_MEAN_START       = ens_size + 6
OBS_MEAN_END         = OBS_MEAN_START + num_groups - 1
OBS_VAR_START        = OBS_MEAN_START + num_groups
OBS_VAR_END          = OBS_VAR_START + num_groups - 1

TOTAL_OBS_COPIES = ens_size + 5 + 2*num_groups

call     trace_message('Before setting up space for observations')
call timestamp_message('Before setting up space for observations')

! Initialize the obs_sequence; every pe gets a copy for now
call filter_setup_obs_sequence(seq, in_obs_copy, obs_val_index, input_qc_index, DART_qc_index)

call timestamp_message('After  setting up space for observations')
call     trace_message('After  setting up space for observations')

call trace_message('Before setting up space for ensembles')

! Allocate model size storage and ens_size storage for metadata for outputting ensembles
model_size = get_model_size()

if(distributed_state) then
   call init_ensemble_manager(state_ens_handle, num_state_ens_copies, model_size)
else
   call init_ensemble_manager(state_ens_handle, num_state_ens_copies, model_size, transpose_type_in = 2)
endif

call set_num_extra_copies(state_ens_handle, num_extras)

call trace_message('After  setting up space for ensembles')

! Don't currently support number of processes > model_size
if(task_count() > model_size) call error_handler(E_ERR,'filter_main', &
   'Number of processes > model size' ,source,revision,revdate)

! Set a time type for initial time if namelist inputs are not negative
call filter_set_initial_time(init_time_days, init_time_seconds, time1, read_time_from_file)

! Moved this. Not doing anything with it, but when we do it should be before the read
! Read in or initialize smoother restarts as needed
if(ds) then
   call init_smoother(state_ens_handle, POST_INF_COPY, POST_INF_SD_COPY)
   call smoother_read_restart(state_ens_handle, ens_size, model_size, time1, init_time_days)
endif

call     trace_message('Before reading in ensemble restart files')
call timestamp_message('Before reading in ensemble restart files')

! for now, assume that we only allow cycling if single_file_out is true.
! code in this call needs to know how to initialize the output files.
call initialize_file_information(num_state_ens_copies, file_info_input, &
                                 file_info_preassim, file_info_postassim, &
                                 file_info_output)

call check_file_info_variable_shape(file_info_output, state_ens_handle)

call set_inflation_mean_copy(prior_inflate, PRIOR_INF_COPY)
call set_inflation_sd_copy(  prior_inflate, PRIOR_INF_SD_COPY)
call set_inflation_mean_copy(post_inflate,  POST_INF_COPY)
call set_inflation_sd_copy(  post_inflate,  POST_INF_SD_COPY)

call read_state(state_ens_handle, file_info_input, read_time_from_file, time1, prior_inflate, post_inflate, &
                perturb_from_single_instance)

! This must be after read_state
call get_minmax_task_zero(prior_inflate, state_ens_handle, PRIOR_INF_COPY, PRIOR_INF_SD_COPY)
call log_inflation_info(prior_inflate, state_ens_handle%my_pe, 'Prior')
call get_minmax_task_zero(post_inflate, state_ens_handle, POST_INF_COPY, POST_INF_SD_COPY)
call log_inflation_info(post_inflate, state_ens_handle%my_pe, 'Posterior')


if (perturb_from_single_instance) then
   call error_handler(E_MSG,'read_state:', &
      'Reading in a single member and perturbing data for the other ensemble members')

   ! Only zero has the time, so broadcast the time to all other copy owners
   call broadcast_time_across_copy_owners(state_ens_handle, time1)
   call create_ensemble_from_single_file(state_ens_handle)
else
   call error_handler(E_MSG,'read_state:', &
      'Reading in initial condition/restart data for all ensemble members from file(s)')
endif

call timestamp_message('After  reading in ensemble restart files')
call     trace_message('After  reading in ensemble restart files')

! see what our stance is on missing values in the state vector
allow_missing = get_missing_ok_status()

call     trace_message('Before initializing output files')
call timestamp_message('Before initializing output files')

! Initialize the output sequences and state files and set their meta data
call filter_generate_copy_meta_data(seq, in_obs_copy, &
      prior_obs_mean_index, posterior_obs_mean_index, &
      prior_obs_spread_index, posterior_obs_spread_index)

if(ds) call error_handler(E_ERR, 'filter', 'smoother broken by Helen')
if(ds) call smoother_gen_copy_meta_data(num_output_state_members, output_inflation=.true.) !> @todo fudge

call timestamp_message('After  initializing output files')
call     trace_message('After  initializing output files')

call trace_message('Before trimming obs seq if start/stop time specified')

! Need to find first obs with appropriate time, delete all earlier ones
if(first_obs_seconds > 0 .or. first_obs_days > 0) then
   first_obs_time = set_time(first_obs_seconds, first_obs_days)
   call delete_seq_head(first_obs_time, seq, all_gone)
   if(all_gone) then
      msgstring = 'All obs in sequence are before first_obs_days:first_obs_seconds'
      call error_handler(E_ERR,'filter_main',msgstring,source,revision,revdate)
   endif
endif

! Start assimilating at beginning of modified sequence
last_key_used = -99

! Also get rid of observations past the last_obs_time if requested
if(last_obs_seconds >= 0 .or. last_obs_days >= 0) then
   last_obs_time = set_time(last_obs_seconds, last_obs_days)
   call delete_seq_tail(last_obs_time, seq, all_gone)
   if(all_gone) then
      msgstring = 'All obs in sequence are after last_obs_days:last_obs_seconds'
      call error_handler(E_ERR,'filter_main',msgstring,source,revision,revdate)
   endif
endif

call trace_message('After  trimming obs seq if start/stop time specified')

! Time step number is used to do periodic diagnostic output
time_step_number = -1
curr_ens_time = set_time(0, 0)
next_ens_time = set_time(0, 0)
call filter_set_window_time(window_time)

AdvanceTime : do
   call trace_message('Top of main advance time loop')

   time_step_number = time_step_number + 1
   write(msgstring , '(A,I5)') &
      'Main assimilation loop, starting iteration', time_step_number
   call trace_message(' ', ' ', -1)
   call trace_message(msgstring, 'filter: ', -1)

   ! Check the time before doing the first model advance.  Not all tasks
   ! might have a time, so only check on PE0 if running multitask.
   ! This will get broadcast (along with the post-advance time) to all
   ! tasks so everyone has the same times, whether they have copies or not.
   ! If smoothing, we need to know whether the move_ahead actually advanced
   ! the model or not -- the first time through this loop the data timestamp
   ! may already include the first observation, and the model will not need
   ! to be run.  Also, last time through this loop, the move_ahead call
   ! will determine if there are no more obs, not call the model, and return
   ! with no keys in the list, which is how we know to exit.  In both of
   ! these cases, we must not advance the times on the lags.

   ! Figure out how far model needs to move data to make the window
   ! include the next available observation.  recent change is
   ! curr_ens_time in move_ahead() is intent(inout) and doesn't get changed
   ! even if there are no more obs.
   call trace_message('Before move_ahead checks time of data and next obs')

   call move_ahead(state_ens_handle, ens_size, seq, last_key_used, window_time, &
      key_bounds, num_obs_in_set, curr_ens_time, next_ens_time)

   call trace_message('After  move_ahead checks time of data and next obs')

   ! Only processes with an ensemble copy know to exit;
   ! For now, let process 0 broadcast its value of key_bounds
   ! This will synch the loop here and allow everybody to exit
   ! Need to clean up and have a broadcast that just sends a single integer???
   ! PAR For now, can only broadcast real arrays
   call filter_sync_keys_time(state_ens_handle, key_bounds, num_obs_in_set, curr_ens_time, next_ens_time)

   if(key_bounds(1) < 0) then
      call trace_message('No more obs to assimilate, exiting main loop', 'filter:', -1)
      exit AdvanceTime
   endif

   ! if model state data not at required time, advance model
   if (curr_ens_time /= next_ens_time) then
      ! Advance the lagged distribution, if needed.
      ! Must be done before the model runs and updates the data.
      if(ds) then
         call     trace_message('Before advancing smoother')
         call timestamp_message('Before advancing smoother')
         call advance_smoother(state_ens_handle)
         call timestamp_message('After  advancing smoother')
         call     trace_message('After  advancing smoother')
      endif

      ! we are going to advance the model - make sure we're doing single file output
      if (.not. has_cycling) then
         call error_handler(E_ERR,'filter:', &
             'advancing the model inside filter and multiple file output not currently supported', &
             source, revision, revdate, text2='support will be added in subsequent releases', &
             text3='set "single_file_out=.true" for filter to advance the model, or advance the model outside filter')
      endif

      call trace_message('Ready to run model to advance data ahead in time', 'filter:', -1)
      call print_ens_time(state_ens_handle, 'Ensemble data time before advance')
      call     trace_message('Before running model')
      call timestamp_message('Before running model', sync=.true.)

      ! make sure storage is allocated in ensemble manager for vars.
      call allocate_vars(state_ens_handle)

      call all_copies_to_all_vars(state_ens_handle)

      call advance_state(state_ens_handle, ens_size, next_ens_time, async, &
                   adv_ens_command, tasks_per_model_advance, file_info_output, file_info_input)

      call all_vars_to_all_copies(state_ens_handle)

      ! update so curr time is accurate.
      curr_ens_time = next_ens_time
      state_ens_handle%current_time = curr_ens_time
      call set_time_on_extra_copies(state_ens_handle)

      ! only need to sync here since we want to wait for the
      ! slowest task to finish before outputting the time.
      call timestamp_message('After  running model', sync=.true.)
      call     trace_message('After  running model')
      call print_ens_time(state_ens_handle, 'Ensemble data time after  advance')
   else
      call trace_message('Model does not need to run; data already at required time', 'filter:', -1)
   endif

   call trace_message('Before setup for next group of observations')
   write(msgstring, '(A,I7)') 'Number of observations to be assimilated', &
      num_obs_in_set
   call trace_message(msgstring)
   call print_obs_time(seq, key_bounds(1), 'Time of first observation in window')
   call print_obs_time(seq, key_bounds(2), 'Time of last  observation in window')

   ! Create an ensemble for the observations from this time plus
   ! obs_error_variance, observed value, key from sequence, global qc,
   ! then mean for each group, then variance for each group
   call init_ensemble_manager(obs_fwd_op_ens_handle, TOTAL_OBS_COPIES, int(num_obs_in_set,i8), 1, transpose_type_in = 2)
   ! Also need a qc field for copy of each observation
   call init_ensemble_manager(qc_ens_handle, ens_size, int(num_obs_in_set,i8), 1, transpose_type_in = 2)

   ! Allocate storage for the keys for this number of observations
   allocate(keys(num_obs_in_set)) ! This is still var size for writing out the observation sequence

   ! Get all the keys associated with this set of observations
   ! Is there a way to distribute this?
   call get_time_range_keys(seq, key_bounds, num_obs_in_set, keys)

   call trace_message('After  setup for next group of observations')

   ! Compute mean and spread for inflation and state diagnostics
   call compute_copy_mean_sd(state_ens_handle, 1, ens_size, ENS_MEAN_COPY, ENS_SD_COPY)
  
   ! Write out the mean and sd for the input files if requested
   if (get_stage_to_write('input')) then

      if (output_mean) &
         call set_io_copy_flag(file_info_input, INPUT_MEAN, WRITE_COPY, has_units=.true.)
      if (output_sd)   &
         call set_io_copy_flag(file_info_input, INPUT_SD,   WRITE_COPY, has_units=.false.)

      call     trace_message('Before input state space output')
      call timestamp_message('Before input state space output')

      if (write_all_stages_at_end) then
         call store_input(state_ens_handle)
      else
         call write_state(state_ens_handle, file_info_input)
      endif

      call timestamp_message('After  input state space output')
      call     trace_message('After  input state space output')

   endif

   if(do_single_ss_inflate(prior_inflate) .or. do_varying_ss_inflate(prior_inflate)) then
      call trace_message('Before prior inflation damping and prep')

      if (inf_damping(1) /= 1.0_r8) then
         call prepare_to_update_copies(state_ens_handle)
         state_ens_handle%copies(PRIOR_INF_COPY, :) = 1.0_r8 + &
            inf_damping(1) * (state_ens_handle%copies(PRIOR_INF_COPY, :) - 1.0_r8)
      endif

      call filter_ensemble_inflate(state_ens_handle, PRIOR_INF_COPY, prior_inflate, ENS_MEAN_COPY)

      ! Recompute the the mean and spread as required for diagnostics
      call compute_copy_mean_sd(state_ens_handle, 1, ens_size, ENS_MEAN_COPY, ENS_SD_COPY)

      call trace_message('After  prior inflation damping and prep')
   endif

   ! if relaxation-to-prior-spread inflation, save the prior spread in SPARE_PRIOR_SPREAD
   if ( do_rtps_inflate(post_inflate) ) &
      call compute_copy_mean_sd(state_ens_handle, 1, ens_size, ENS_MEAN_COPY, SPARE_PRIOR_SPREAD)

   call     trace_message('Before computing prior observation values')
   call timestamp_message('Before computing prior observation values')

   ! Compute the ensemble of prior observations, load up the obs_err_var
   ! and obs_values. ens_size is the number of regular ensemble members,
   ! not the number of copies

   ! allocate() space for the prior qc copy
   call allocate_single_copy(obs_fwd_op_ens_handle, prior_qc_copy)

   call get_obs_ens_distrib_state(state_ens_handle, obs_fwd_op_ens_handle, qc_ens_handle, &
     seq, keys, obs_val_index, input_qc_index, &
     OBS_ERR_VAR_COPY, OBS_VAL_COPY, OBS_KEY_COPY, OBS_GLOBAL_QC_COPY, OBS_EXTRA_QC_COPY, &
     OBS_MEAN_START, OBS_VAR_START, isprior=.true., prior_qc_copy=prior_qc_copy)

   call timestamp_message('After  computing prior observation values')
   call     trace_message('After  computing prior observation values')

   ! Do prior state space diagnostic output as required

   if (get_stage_to_write('preassim')) then
      if ((output_interval > 0) .and. &
          (time_step_number / output_interval * output_interval == time_step_number)) then

         call     trace_message('Before preassim state space output')
         call timestamp_message('Before preassim state space output')

         ! save or output the data
         if (write_all_stages_at_end) then
            call store_preassim(state_ens_handle)
         else
            call write_state(state_ens_handle, file_info_preassim)
         endif

         call timestamp_message('After  preassim state space output')
         call     trace_message('After  preassim state space output')

      endif
   endif

   call trace_message('Before observation space diagnostics')

   ! This is where the mean obs
   ! copy ( + others ) is moved to task 0 so task 0 can update seq.
   ! There is a transpose (all_copies_to_all_vars(obs_fwd_op_ens_handle)) in obs_space_diagnostics
   ! Do prior observation space diagnostics and associated quality control
   call obs_space_diagnostics(obs_fwd_op_ens_handle, qc_ens_handle, ens_size, &
      seq, keys, PRIOR_DIAG, num_output_obs_members, in_obs_copy+1, &
      obs_val_index, OBS_KEY_COPY, &                                 ! new
      prior_obs_mean_index, prior_obs_spread_index, num_obs_in_set, &
      OBS_MEAN_START, OBS_VAR_START, OBS_GLOBAL_QC_COPY, &
      OBS_VAL_COPY, OBS_ERR_VAR_COPY, DART_qc_index)
   call trace_message('After  observation space diagnostics')


   ! FIXME:  i believe both copies and vars are equal at the end
   ! of the obs_space diags, so we can skip this.
   !call all_vars_to_all_copies(obs_fwd_op_ens_handle)

   write(msgstring, '(A,I8,A)') 'Ready to assimilate up to', size(keys), ' observations'
   call trace_message(msgstring, 'filter:', -1)

   call     trace_message('Before observation assimilation')
   call timestamp_message('Before observation assimilation')

   call filter_assim(state_ens_handle, obs_fwd_op_ens_handle, seq, keys, &
      ens_size, num_groups, obs_val_index, prior_inflate, &
      ENS_MEAN_COPY, ENS_SD_COPY, &
      PRIOR_INF_COPY, PRIOR_INF_SD_COPY, OBS_KEY_COPY, OBS_GLOBAL_QC_COPY, &
      OBS_MEAN_START, OBS_MEAN_END, OBS_VAR_START, &
      OBS_VAR_END, inflate_only = .false.)

   call timestamp_message('After  observation assimilation')
   call     trace_message('After  observation assimilation')

   ! Do the update for the smoother lagged fields, too.
   ! Would be more efficient to do these all at once inside filter_assim
   ! in the future
   if(ds) then
      write(msgstring, '(A,I8,A)') 'Ready to reassimilate up to', size(keys), ' observations in the smoother'
      call trace_message(msgstring, 'filter:', -1)

      call     trace_message('Before smoother assimilation')
      call timestamp_message('Before smoother assimilation')
      call smoother_assim(obs_fwd_op_ens_handle, seq, keys, ens_size, num_groups, &
         obs_val_index, ENS_MEAN_COPY, ENS_SD_COPY, &
         PRIOR_INF_COPY, PRIOR_INF_SD_COPY, OBS_KEY_COPY, OBS_GLOBAL_QC_COPY, &
         OBS_MEAN_START, OBS_MEAN_END, OBS_VAR_START, &
         OBS_VAR_END)
      call timestamp_message('After  smoother assimilation')
      call     trace_message('After  smoother assimilation')
   endif

   ! Already transformed, so compute mean and spread for state diag as needed
   call compute_copy_mean_sd(state_ens_handle, 1, ens_size, ENS_MEAN_COPY, ENS_SD_COPY)


   ! Do postassim state space output if requested

   if (get_stage_to_write('postassim')) then
      if ((output_interval > 0) .and. &
          (time_step_number / output_interval * output_interval == time_step_number)) then

         call     trace_message('Before postassim state space output')
         call timestamp_message('Before postassim state space output')

         ! save or output the data
         if (write_all_stages_at_end) then
            call store_postassim(state_ens_handle)
         else
            call write_state(state_ens_handle, file_info_postassim)
         endif

         !>@todo What to do here?
         !call smoother_ss_diagnostics(model_size, num_output_state_members, &
         !  output_inflation, temp_ens, ENS_MEAN_COPY, ENS_SD_COPY, &
         ! POST_INF_COPY, POST_INF_SD_COPY)

         call timestamp_message('After  postassim state space output')
         call     trace_message('After  postassim state space output')

      endif
   endif

   ! This block applies posterior inflation

   if(do_single_ss_inflate(post_inflate) .or. do_varying_ss_inflate(post_inflate) .or. &
      do_rtps_inflate(post_inflate)) then

      call trace_message('Before posterior inflation damping and prep')

      if (inf_damping(2) /= 1.0_r8) then
         call prepare_to_update_copies(state_ens_handle)
         state_ens_handle%copies(POST_INF_COPY, :) = 1.0_r8 + &
            inf_damping(2) * (state_ens_handle%copies(POST_INF_COPY, :) - 1.0_r8)
      endif

      if (do_rtps_inflate(post_inflate)) then   
         call filter_ensemble_inflate(state_ens_handle, POST_INF_COPY, post_inflate, ENS_MEAN_COPY, &
                                      SPARE_PRIOR_SPREAD, ENS_SD_COPY)
      else
         call filter_ensemble_inflate(state_ens_handle, POST_INF_COPY, post_inflate, ENS_MEAN_COPY)
      endif

      ! Recompute the mean or the mean and spread as required for diagnostics
      call compute_copy_mean_sd(state_ens_handle, 1, ens_size, ENS_MEAN_COPY, ENS_SD_COPY)

      call trace_message('After  posterior inflation damping and prep')

   endif

   ! this block recomputes the expected obs values for the obs_seq.final file

   call     trace_message('Before computing posterior observation values')
   call timestamp_message('Before computing posterior observation values')

   ! Compute the ensemble of posterior observations, load up the obs_err_var
   ! and obs_values.  ens_size is the number of regular ensemble members,
   ! not the number of copies

    call get_obs_ens_distrib_state(state_ens_handle, obs_fwd_op_ens_handle, qc_ens_handle, &
     seq, keys, obs_val_index, input_qc_index, &
     OBS_ERR_VAR_COPY, OBS_VAL_COPY, OBS_KEY_COPY, OBS_GLOBAL_QC_COPY, OBS_EXTRA_QC_COPY, &
     OBS_MEAN_START, OBS_VAR_START, isprior=.false., prior_qc_copy=prior_qc_copy)

   call deallocate_single_copy(obs_fwd_op_ens_handle, prior_qc_copy)

   call timestamp_message('After  computing posterior observation values')
   call     trace_message('After  computing posterior observation values')

   if(ds) then
      call trace_message('Before computing smoother means/spread')
      call smoother_mean_spread(ens_size, ENS_MEAN_COPY, ENS_SD_COPY)
      call trace_message('After  computing smoother means/spread')
   endif

   call trace_message('Before posterior obs space diagnostics')

   ! Write posterior observation space diagnostics
   ! There is a transpose (all_copies_to_all_vars(obs_fwd_op_ens_handle)) in obs_space_diagnostics
   call obs_space_diagnostics(obs_fwd_op_ens_handle, qc_ens_handle, ens_size, &
      seq, keys, POSTERIOR_DIAG, num_output_obs_members, in_obs_copy+2, &
      obs_val_index, OBS_KEY_COPY, &                             ! new
      posterior_obs_mean_index, posterior_obs_spread_index, num_obs_in_set, &
      OBS_MEAN_START, OBS_VAR_START, OBS_GLOBAL_QC_COPY, &
      OBS_VAL_COPY, OBS_ERR_VAR_COPY, DART_qc_index)


   call trace_message('After  posterior obs space diagnostics')

   ! this block computes the adaptive state space posterior inflation
   ! (it was applied earlier, this is computing the updated values for
   ! the next cycle.)

   if(do_single_ss_inflate(post_inflate) .or. do_varying_ss_inflate(post_inflate)) then

      ! If not reading the sd values from a restart file and the namelist initial
      !  sd < 0, then bypass this entire code block altogether for speed.
      if ((inf_sd_initial(2) >= 0.0_r8) .or. inf_sd_initial_from_restart(2)) then

         call     trace_message('Before computing posterior state space inflation')
         call timestamp_message('Before computing posterior state space inflation')

         call filter_assim(state_ens_handle, obs_fwd_op_ens_handle, seq, keys, ens_size, num_groups, &
            obs_val_index, post_inflate, ENS_MEAN_COPY, ENS_SD_COPY, &
            POST_INF_COPY, POST_INF_SD_COPY, OBS_KEY_COPY, OBS_GLOBAL_QC_COPY, &
            OBS_MEAN_START, OBS_MEAN_END, OBS_VAR_START, &
            OBS_VAR_END, inflate_only = .true.)

         call timestamp_message('After  computing posterior state space inflation')
         call     trace_message('After  computing posterior state space inflation')

         ! recalculate standard deviation since this was overwritten in filter_assim
         call compute_copy_mean_sd(state_ens_handle, 1, ens_size, ENS_MEAN_COPY, ENS_SD_COPY)


      endif  ! sd >= 0 or sd from restart file
   endif  ! if doing state space posterior inflate


   call trace_message('Near bottom of main loop, cleaning up obs space')
   ! Deallocate storage used for keys for each set
   deallocate(keys)

   ! The last key used is updated to move forward in the observation sequence
   last_key_used = key_bounds(2)

   ! Free up the obs ensemble space; LATER, can just keep it if obs are same size next time
   call end_ensemble_manager(obs_fwd_op_ens_handle)
   call end_ensemble_manager(qc_ens_handle)

   if (get_stage_to_write('output')) then
      if ((output_interval > 0) .and. &
          (time_step_number / output_interval * output_interval == time_step_number)) then

         call     trace_message('Before state space output')
         call timestamp_message('Before state space output')

         !>@todo FIXME this assumes we cannot combine cycling inside filter
         !>and delaying write until the end.

         ! will write outside loop
         if (.not. write_all_stages_at_end) &
            call write_state(state_ens_handle, file_info_output)
      
         !>@todo need to fix smoother
         !if(ds) call smoother_write_restart(1, ens_size)

         call timestamp_message('After  state space output')
         call     trace_message('After  state space output')

      endif
   endif

   call trace_message('Bottom of main advance time loop')

end do AdvanceTime

call trace_message('End of main filter assimilation loop, starting cleanup', 'filter:', -1)

call trace_message('Before writing output sequence file')
! Only pe 0 outputs the observation space diagnostic file
if(my_task_id() == 0) call write_obs_seq(seq, obs_sequence_out_name)
call trace_message('After  writing output sequence file')

! Output all restart files if requested
if (write_all_stages_at_end) then
   call     trace_message('Before writing all state restart files at end')
   call timestamp_message('Before writing all state restart files at end')

   file_info_all = combine_file_info( (/file_info_input, file_info_preassim, &
                                        file_info_postassim, file_info_output/) )

   call write_state(state_ens_handle, file_info_all)

   call timestamp_message('After  writing all state restart files at end')
   call     trace_message('After  writing all state restart files at end')
endif

! close the diagnostic/restart netcdf files
if (single_file_out) then
   if (get_stage_to_write('input')) &
      call finalize_singlefile_output(file_info_input)

   if (get_stage_to_write('preassim')) &
      call finalize_singlefile_output(file_info_preassim)

   if (get_stage_to_write('postassim')) &
      call finalize_singlefile_output(file_info_postassim)

   if (get_stage_to_write('output')) &
      call finalize_singlefile_output(file_info_output)
endif

! Give the model_mod code a chance to clean up.
call trace_message('Before end_model call')
call end_assim_model()
call trace_message('After  end_model call')

call trace_message('Before ensemble and obs memory cleanup')
call end_ensemble_manager(state_ens_handle)

! Free up the observation kind and obs sequence
call destroy_obs(observation)
call destroy_obs_sequence(seq)
call trace_message('After  ensemble and obs memory cleanup')

if(ds) then
   call trace_message('Before smoother memory cleanup')
   call smoother_end()
   call trace_message('After  smoother memory cleanup')
endif

call     trace_message('Filter done')
call timestamp_message('Filter done')
if(my_task_id() == 0) then
   write(logfileunit,*)'FINISHED filter.'
   write(logfileunit,*)
endif

end subroutine filter_main

!-----------------------------------------------------------
!> This generates the copy meta data for the diagnostic files.
!> And also creates the state space diagnostic file.
!> Note for the state space diagnostic files the order of copies
!> in the diagnostic file is different from the order of copies
!> in the ensemble handle.
subroutine filter_generate_copy_meta_data(seq, in_obs_copy, &
   prior_obs_mean_index, posterior_obs_mean_index, &
   prior_obs_spread_index, posterior_obs_spread_index)

type(obs_sequence_type),     intent(inout) :: seq
integer,                     intent(in)    :: in_obs_copy
integer,                     intent(out)   :: prior_obs_mean_index, posterior_obs_mean_index
integer,                     intent(out)   :: prior_obs_spread_index, posterior_obs_spread_index

! Figures out the strings describing the output copies for the three output files.
! THese are the prior and posterior state output files and the observation sequence
! output file which contains both prior and posterior data.

character(len=metadatalength) :: prior_meta_data, posterior_meta_data
integer :: i, num_state_copies, num_obs_copies

! Set the metadata for the observations.

! Set up obs ensemble mean
num_obs_copies = in_obs_copy
num_obs_copies = num_obs_copies + 1
prior_meta_data = 'prior ensemble mean'
call set_copy_meta_data(seq, num_obs_copies, prior_meta_data)
prior_obs_mean_index = num_obs_copies
num_obs_copies = num_obs_copies + 1
posterior_meta_data = 'posterior ensemble mean'
call set_copy_meta_data(seq, num_obs_copies, posterior_meta_data)
posterior_obs_mean_index = num_obs_copies

! Set up obs ensemble spread
num_obs_copies = num_obs_copies + 1
prior_meta_data = 'prior ensemble spread'
call set_copy_meta_data(seq, num_obs_copies, prior_meta_data)
prior_obs_spread_index = num_obs_copies
num_obs_copies = num_obs_copies + 1
posterior_meta_data = 'posterior ensemble spread'
call set_copy_meta_data(seq, num_obs_copies, posterior_meta_data)
posterior_obs_spread_index = num_obs_copies

! Make sure there are not too many copies requested
if(num_output_obs_members > 10000) then
   write(msgstring, *)'output metadata in filter needs obs ensemble size < 10000, not ',&
                      num_output_obs_members
   call error_handler(E_ERR,'filter_generate_copy_meta_data',msgstring,source,revision,revdate)
endif

! Set up obs ensemble members as requested
do i = 1, num_output_obs_members
   write(prior_meta_data, '(a21, 1x, i6)') 'prior ensemble member', i
   write(posterior_meta_data, '(a25, 1x, i6)') 'posterior ensemble member', i
   num_obs_copies = num_obs_copies + 1
   call set_copy_meta_data(seq, num_obs_copies, prior_meta_data)
   num_obs_copies = num_obs_copies + 1
   call set_copy_meta_data(seq, num_obs_copies, posterior_meta_data)
end do


end subroutine filter_generate_copy_meta_data

!-------------------------------------------------------------------------

subroutine filter_initialize_modules_used()

call trace_message('Before filter_initialize_module_used call')
call register_module(source,revision,revdate)

! Initialize the obs sequence module
call static_init_obs_sequence()

! Initialize the model class data now that obs_sequence is all set up
call static_init_assim_model()
call state_vector_io_init()
call initialize_qc()
call trace_message('After filter_initialize_module_used call')

end subroutine filter_initialize_modules_used

!-------------------------------------------------------------------------

subroutine filter_setup_obs_sequence(seq, in_obs_copy, obs_val_index, &
   input_qc_index, DART_qc_index)

type(obs_sequence_type), intent(inout) :: seq
integer,                 intent(out)   :: in_obs_copy, obs_val_index
integer,                 intent(out)   :: input_qc_index, DART_qc_index

character(len=metadatalength) :: no_qc_meta_data = 'No incoming data QC'
character(len=metadatalength) :: dqc_meta_data   = 'DART quality control'
character(len=129) :: obs_seq_read_format
integer              :: obs_seq_file_id, num_obs_copies
integer              :: tnum_copies, tnum_qc, tnum_obs, tmax_num_obs, qc_num_inc, num_qc
logical              :: pre_I_format

! Determine the number of output obs space fields
! 4 is for prior/posterior mean and spread,
! Prior and posterior values for all selected fields (so times 2)
num_obs_copies = 2 * num_output_obs_members + 4

! Input file can have one qc field, none, or more.  note that read_obs_seq_header
! does NOT return the actual metadata values, which would be helpful in trying
! to decide if we need to add copies or qcs.
call read_obs_seq_header(obs_sequence_in_name, tnum_copies, tnum_qc, tnum_obs, tmax_num_obs, &
   obs_seq_file_id, obs_seq_read_format, pre_I_format, close_the_file = .true.)


! if there are less than 2 incoming qc fields, we will need
! to make at least 2 (one for the dummy data qc and one for
! the dart qc).
if (tnum_qc < 2) then
   qc_num_inc = 2 - tnum_qc
else
   qc_num_inc = 0
endif

! Read in with enough space for diagnostic output values and add'l qc field(s)
call read_obs_seq(obs_sequence_in_name, num_obs_copies, qc_num_inc, 0, seq)

! check to be sure that we have an incoming qc field.  if not, look for
! a blank qc field
input_qc_index = get_obs_qc_index(seq)
if (input_qc_index < 0) then
   input_qc_index = get_blank_qc_index(seq)
   if (input_qc_index < 0) then
      ! Need 1 new qc field for dummy incoming qc
      call add_qc(seq, 1)
      input_qc_index = get_blank_qc_index(seq)
      if (input_qc_index < 0) then
         call error_handler(E_ERR,'filter_setup_obs_sequence', &
           'error adding blank qc field to sequence; should not happen', &
            source, revision, revdate)
      endif
   endif
   ! Since we are constructing a dummy QC, label it as such
   call set_qc_meta_data(seq, input_qc_index, no_qc_meta_data)
endif

! check to be sure we either find an existing dart qc field and
! reuse it, or we add a new one.
DART_qc_index = get_obs_dartqc_index(seq)
if (DART_qc_index < 0) then
   DART_qc_index = get_blank_qc_index(seq)
   if (DART_qc_index < 0) then
      ! Need 1 new qc field for the DART quality control
      call add_qc(seq, 1)
      DART_qc_index = get_blank_qc_index(seq)
      if (DART_qc_index < 0) then
         call error_handler(E_ERR,'filter_setup_obs_sequence', &
           'error adding blank qc field to sequence; should not happen', &
            source, revision, revdate)
      endif
   endif
   call set_qc_meta_data(seq, DART_qc_index, dqc_meta_data)
endif

! Get num of obs copies and num_qc
num_qc = get_num_qc(seq)
in_obs_copy = get_num_copies(seq) - num_obs_copies

! Create an observation type temporary for use in filter
call init_obs(observation, get_num_copies(seq), num_qc)

! Set initial DART quality control to 0 for all observations?
! Or leave them uninitialized, since
! obs_space_diagnostics should set them all without reading them

! Determine which copy has actual obs
obs_val_index = get_obs_copy_index(seq)

end subroutine filter_setup_obs_sequence

!-------------------------------------------------------------------------

function get_obs_copy_index(seq)

type(obs_sequence_type), intent(in) :: seq
integer                             :: get_obs_copy_index

integer :: i

! Determine which copy in sequence has actual obs

do i = 1, get_num_copies(seq)
   get_obs_copy_index = i
   ! Need to look for 'observation'
   if(index(get_copy_meta_data(seq, i), 'observation') > 0) return
end do
! Falling of end means 'observations' not found; die
call error_handler(E_ERR,'get_obs_copy_index', &
   'Did not find observation copy with metadata "observation"', &
      source, revision, revdate)

end function get_obs_copy_index

!-------------------------------------------------------------------------

function get_obs_prior_index(seq)

type(obs_sequence_type), intent(in) :: seq
integer                             :: get_obs_prior_index

integer :: i

! Determine which copy in sequence has prior mean, if any.

do i = 1, get_num_copies(seq)
   get_obs_prior_index = i
   ! Need to look for 'prior mean'
   if(index(get_copy_meta_data(seq, i), 'prior ensemble mean') > 0) return
end do
! Falling of end means 'prior mean' not found; not fatal!

get_obs_prior_index = -1

end function get_obs_prior_index

!-------------------------------------------------------------------------

function get_obs_qc_index(seq)

type(obs_sequence_type), intent(in) :: seq
integer                             :: get_obs_qc_index

integer :: i

! Determine which qc, if any, has the incoming obs qc
! this is tricky because we have never specified what string
! the metadata has to have.  look for 'qc' or 'QC' and the
! first metadata that matches (much like 'observation' above)
! is the winner.

do i = 1, get_num_qc(seq)
   get_obs_qc_index = i

   ! Need to avoid 'QC metadata not initialized'
   if(index(get_qc_meta_data(seq, i), 'QC metadata not initialized') > 0) cycle
 
   ! Need to look for 'QC' or 'qc'
   if(index(get_qc_meta_data(seq, i), 'QC') > 0) return
   if(index(get_qc_meta_data(seq, i), 'qc') > 0) return
   if(index(get_qc_meta_data(seq, i), 'Quality Control') > 0) return
   if(index(get_qc_meta_data(seq, i), 'QUALITY CONTROL') > 0) return
end do
! Falling off end means 'QC' string not found; not fatal!

get_obs_qc_index = -1

end function get_obs_qc_index

!-------------------------------------------------------------------------

function get_obs_dartqc_index(seq)

type(obs_sequence_type), intent(in) :: seq
integer                             :: get_obs_dartqc_index

integer :: i

! Determine which qc, if any, has the DART qc

do i = 1, get_num_qc(seq)
   get_obs_dartqc_index = i
   ! Need to look for 'DART quality control'
   if(index(get_qc_meta_data(seq, i), 'DART quality control') > 0) return
end do
! Falling off end means 'DART quality control' not found; not fatal!

get_obs_dartqc_index = -1

end function get_obs_dartqc_index

!-------------------------------------------------------------------------

function get_blank_qc_index(seq)

type(obs_sequence_type), intent(in) :: seq
integer                             :: get_blank_qc_index

integer :: i

! Determine which qc, if any, is blank

do i = 1, get_num_qc(seq)
   get_blank_qc_index = i
   ! Need to look for 'QC metadata not initialized'
   if(index(get_qc_meta_data(seq, i), 'QC metadata not initialized') > 0) return
end do
! Falling off end means unused slot not found; not fatal!

get_blank_qc_index = -1

end function get_blank_qc_index

!-------------------------------------------------------------------------

subroutine filter_set_initial_time(days, seconds, time, read_time_from_file)

integer,         intent(in)  :: days, seconds
type(time_type), intent(out) :: time
logical,         intent(out) :: read_time_from_file

if(days >= 0) then
   time = set_time(seconds, days)
   read_time_from_file = .false.
else
   time = set_time(0, 0)
   read_time_from_file = .true.
endif

end subroutine filter_set_initial_time

!-------------------------------------------------------------------------

subroutine filter_set_window_time(time)

type(time_type), intent(out) :: time


if(obs_window_days >= 0) then
   time = set_time(obs_window_seconds, obs_window_days)
else
   time = set_time(0, 0)
endif

end subroutine filter_set_window_time

!-------------------------------------------------------------------------

subroutine filter_ensemble_inflate(ens_handle, inflate_copy, inflate, ENS_MEAN_COPY, &
                                   SPARE_PRIOR_SPREAD, ENS_SD_COPY)

type(ensemble_type),         intent(inout) :: ens_handle
integer,                     intent(in)    :: inflate_copy, ENS_MEAN_COPY
type(adaptive_inflate_type), intent(inout) :: inflate
integer, optional,           intent(in)    :: SPARE_PRIOR_SPREAD, ENS_SD_COPY

integer :: j, group, grp_bot, grp_top, grp_size

! Assumes that the ensemble is copy complete
call prepare_to_update_copies(ens_handle)

! Inflate each group separately;  Divide ensemble into num_groups groups
grp_size = ens_size / num_groups

do group = 1, num_groups
   grp_bot = (group - 1) * grp_size + 1
   grp_top = grp_bot + grp_size - 1
   ! Compute the mean for this group
   call compute_copy_mean(ens_handle, grp_bot, grp_top, ENS_MEAN_COPY)

   if ( do_rtps_inflate(inflate)) then 
      if ( present(SPARE_PRIOR_SPREAD) .and. present(ENS_SD_COPY)) then 
         write(msgstring, *) ' doing RTPS inflation'
         call error_handler(E_MSG,'filter_ensemble_inflate',msgstring,source,revision,revdate)
         do j = 1, ens_handle%my_num_vars 
            call inflate_ens(inflate, ens_handle%copies(grp_bot:grp_top, j), &
               ens_handle%copies(ENS_MEAN_COPY, j), ens_handle%copies(inflate_copy, j), 0.0_r8, &
               ens_handle%copies(SPARE_PRIOR_SPREAD, j), ens_handle%copies(ENS_SD_COPY, j)) 
         end do 
      else 
         write(msgstring, *) 'internal error: missing arguments for RTPS inflation, should not happen'
         call error_handler(E_ERR,'filter_ensemble_inflate',msgstring,source,revision,revdate)
      endif 
   else 
      do j = 1, ens_handle%my_num_vars
         call inflate_ens(inflate, ens_handle%copies(grp_bot:grp_top, j), &
            ens_handle%copies(ENS_MEAN_COPY, j), ens_handle%copies(inflate_copy, j))
      end do
   endif
end do

end subroutine filter_ensemble_inflate

!-------------------------------------------------------------------------

subroutine obs_space_diagnostics(obs_fwd_op_ens_handle, qc_ens_handle, ens_size, &
   seq, keys, prior_post, num_output_members, members_index, &
   obs_val_index, OBS_KEY_COPY, &
   ens_mean_index, ens_spread_index, num_obs_in_set, &
   OBS_MEAN_START, OBS_VAR_START, OBS_GLOBAL_QC_COPY, OBS_VAL_COPY, &
   OBS_ERR_VAR_COPY, DART_qc_index)

! Do prior observation space diagnostics on the set of obs corresponding to keys

type(ensemble_type),     intent(inout) :: obs_fwd_op_ens_handle, qc_ens_handle
integer,                 intent(in)    :: ens_size
integer,                 intent(in)    :: num_obs_in_set
integer,                 intent(in)    :: keys(num_obs_in_set), prior_post
integer,                 intent(in)    :: num_output_members, members_index
integer,                 intent(in)    :: obs_val_index
integer,                 intent(in)    :: OBS_KEY_COPY
integer,                 intent(in)    :: ens_mean_index, ens_spread_index
type(obs_sequence_type), intent(inout) :: seq
integer,                 intent(in)    :: OBS_MEAN_START, OBS_VAR_START
integer,                 intent(in)    :: OBS_GLOBAL_QC_COPY, OBS_VAL_COPY
integer,                 intent(in)    :: OBS_ERR_VAR_COPY, DART_qc_index

integer               :: j, k, ens_offset
integer               :: ivalue
real(r8), allocatable :: obs_temp(:)
real(r8)              :: rvalue(1)

! Do verbose forward operator output if requested
if(output_forward_op_errors) call verbose_forward_op_output(qc_ens_handle, prior_post, ens_size, keys)

! Make var complete for get_copy() calls below.
! Can you use a gather instead of a transpose and get copy?
call all_copies_to_all_vars(obs_fwd_op_ens_handle)

! allocate temp space for sending data - surely only task 0 needs to allocate this?
allocate(obs_temp(num_obs_in_set))

! Update the ensemble mean
! Get this copy to process 0
call get_copy(map_task_to_pe(obs_fwd_op_ens_handle, 0), obs_fwd_op_ens_handle, OBS_MEAN_START, obs_temp)
! Only pe 0 gets to write the sequence
if(my_task_id() == 0) then
     ! Loop through the observations for this time
     do j = 1, obs_fwd_op_ens_handle%num_vars
      rvalue(1) = obs_temp(j)
      call replace_obs_values(seq, keys(j), rvalue, ens_mean_index)
     end do
  endif

! Update the ensemble spread
! Get this copy to process 0
call get_copy(map_task_to_pe(obs_fwd_op_ens_handle, 0), obs_fwd_op_ens_handle, OBS_VAR_START, obs_temp)
! Only pe 0 gets to write the sequence
if(my_task_id() == 0) then
   ! Loop through the observations for this time
   do j = 1, obs_fwd_op_ens_handle%num_vars
      ! update the spread in each obs
      if (obs_temp(j) /= missing_r8) then
         rvalue(1) = sqrt(obs_temp(j))
      else
         rvalue(1) = obs_temp(j)
      endif
      call replace_obs_values(seq, keys(j), rvalue, ens_spread_index)
   end do
endif

! May be possible to only do this after the posterior call...
! Update any requested ensemble members
ens_offset = members_index + 4
! Update all of these ensembles that are required to sequence file
do k = 1, num_output_members
   ! Get this copy on pe 0
   call get_copy(map_task_to_pe(obs_fwd_op_ens_handle, 0), obs_fwd_op_ens_handle, k, obs_temp)
   ! Only task 0 gets to write the sequence
   if(my_task_id() == 0) then
      ! Loop through the observations for this time
      do j = 1, obs_fwd_op_ens_handle%num_vars
         ! update the obs values
         rvalue(1) = obs_temp(j)
         ivalue = ens_offset + 2 * (k - 1)
         call replace_obs_values(seq, keys(j), rvalue, ivalue)
      end do
   endif
end do

! Update the qc global value
call get_copy(map_task_to_pe(obs_fwd_op_ens_handle, 0), obs_fwd_op_ens_handle, OBS_GLOBAL_QC_COPY, obs_temp)
! Only task 0 gets to write the observations for this time
if(my_task_id() == 0) then
   ! Loop through the observations for this time
   do j = 1, obs_fwd_op_ens_handle%num_vars
      rvalue(1) = obs_temp(j)
      call replace_qc(seq, keys(j), rvalue, DART_qc_index)
   end do
endif

! clean up.
deallocate(obs_temp)

end subroutine obs_space_diagnostics

!-------------------------------------------------------------------------

subroutine filter_sync_keys_time(ens_handle, key_bounds, num_obs_in_set, time1, time2)

integer,             intent(inout)  :: key_bounds(2), num_obs_in_set
type(time_type),     intent(inout)  :: time1, time2
type(ensemble_type), intent(inout)     :: ens_handle

! Have owner of copy 1 broadcast these values to all other tasks.
! Only tasks which contain copies have this info; doing it this way
! allows ntasks > nens to work.

real(r8) :: rkey_bounds(2), rnum_obs_in_set(1)
real(r8) :: rtime(4)
integer  :: days, secs
integer  :: copy1_owner, owner_index

call get_copy_owner_index(1, copy1_owner, owner_index)

if( ens_handle%my_pe == copy1_owner) then
   rkey_bounds = key_bounds
   rnum_obs_in_set(1) = num_obs_in_set
   call get_time(time1, secs, days)
   rtime(1) = secs
   rtime(2) = days
   call get_time(time2, secs, days)
   rtime(3) = secs
   rtime(4) = days
   call broadcast_send(map_pe_to_task(ens_handle, copy1_owner), rkey_bounds, rnum_obs_in_set, rtime)
else
   call broadcast_recv(map_pe_to_task(ens_handle, copy1_owner), rkey_bounds, rnum_obs_in_set, rtime)
   key_bounds =     nint(rkey_bounds)
   num_obs_in_set = nint(rnum_obs_in_set(1))
   time1 = set_time(nint(rtime(1)), nint(rtime(2)))
   time2 = set_time(nint(rtime(3)), nint(rtime(4)))
endif

! Every task gets the current time (necessary for the forward operator)
ens_handle%current_time = time1

end subroutine filter_sync_keys_time

!-------------------------------------------------------------------------
! Only copy 1 on task zero has the correct time after reading
! when you read one instance using filter_read_restart.
! perturb_from_single_instance = .true.
! This routine makes the times consistent across the ensemble. 
! Any task that owns one or more state vectors needs the time for
! the move ahead call.
!> @todo This is broadcasting the time to all tasks, not
!> just the tasks that own copies.

subroutine broadcast_time_across_copy_owners(ens_handle, ens_time)

type(ensemble_type), intent(inout) :: ens_handle
type(time_type),     intent(in)    :: ens_time

real(r8) :: rtime(2)
integer  :: days, secs
integer  :: copy1_owner, owner_index
type(time_type) :: time_from_copy1

call get_copy_owner_index(1, copy1_owner, owner_index)

if( ens_handle%my_pe == copy1_owner) then
   call get_time(ens_time, secs, days)
   rtime(1) = secs
   rtime(2) = days
   call broadcast_send(map_pe_to_task(ens_handle, copy1_owner), rtime)
   ens_handle%time(1:ens_handle%my_num_copies) = ens_time
else
   call broadcast_recv(map_pe_to_task(ens_handle, copy1_owner), rtime)
   time_from_copy1 = set_time(nint(rtime(1)), nint(rtime(2)))
   if (ens_handle%my_num_copies > 0) ens_handle%time(1:ens_handle%my_num_copies) = time_from_copy1
endif

end subroutine broadcast_time_across_copy_owners

!-------------------------------------------------------------------------

subroutine set_trace(trace_execution, output_timestamps, silence)

logical, intent(in) :: trace_execution
logical, intent(in) :: output_timestamps
logical, intent(in) :: silence

! Set whether other modules trace execution with messages
! and whether they output timestamps to trace overall performance

! defaults
trace_level     = 0
timestamp_level = 0

! selectively turn stuff back on
if (trace_execution)   trace_level     = 1
if (output_timestamps) timestamp_level = 1

! turn as much off as possible
if (silence) then
   trace_level     = -1
   timestamp_level = -1
endif

call set_smoother_trace(trace_level, timestamp_level)
call set_obs_model_trace(trace_level, timestamp_level)
call set_assim_tools_trace(trace_level, timestamp_level)

end subroutine set_trace

!-------------------------------------------------------------------------

subroutine trace_message(msg, label, threshold)

character(len=*), intent(in)           :: msg
character(len=*), intent(in), optional :: label
integer,          intent(in), optional :: threshold

! Write message to stdout and log file.
integer :: t

t = 0
if (present(threshold)) t = threshold

if (trace_level <= t) return

if (.not. do_output()) return

if (present(label)) then
   call error_handler(E_MSG,trim(label),trim(msg))
else
   call error_handler(E_MSG,' filter trace:',trim(msg))
endif

end subroutine trace_message

!-------------------------------------------------------------------------

subroutine timestamp_message(msg, sync)

character(len=*), intent(in) :: msg
logical, intent(in), optional :: sync

! Write current time and message to stdout and log file.
! if sync is present and true, sync mpi jobs before printing time.

if (timestamp_level <= 0) return

if (present(sync)) then
  if (sync) call task_sync()
endif

if (do_output()) call timestamp(' '//trim(msg), pos='brief')

end subroutine timestamp_message

!-------------------------------------------------------------------------

subroutine print_ens_time(ens_handle, msg)

type(ensemble_type), intent(in) :: ens_handle
character(len=*), intent(in) :: msg

! Write message to stdout and log file.
type(time_type) :: mtime

if (trace_level <= 0) return

if (do_output()) then
   if (get_my_num_copies(ens_handle) < 1) return
   call get_ensemble_time(ens_handle, 1, mtime)
   call print_time(mtime, ' filter trace: '//msg, logfileunit)
   call print_time(mtime, ' filter trace: '//msg)
endif

end subroutine print_ens_time

!-------------------------------------------------------------------------

subroutine print_obs_time(seq, key, msg)

type(obs_sequence_type), intent(in) :: seq
integer, intent(in) :: key
character(len=*), intent(in), optional :: msg

! Write time of an observation to stdout and log file.
type(obs_type) :: obs
type(obs_def_type) :: obs_def
type(time_type) :: mtime

if (trace_level <= 0) return

if (do_output()) then
   call init_obs(obs, 0, 0)
   call get_obs_from_key(seq, key, obs)
   call get_obs_def(obs, obs_def)
   mtime = get_obs_def_time(obs_def)
   call print_time(mtime, ' filter trace: '//msg, logfileunit)
   call print_time(mtime, ' filter trace: '//msg)
   call destroy_obs(obs)
endif

end subroutine print_obs_time

!-------------------------------------------------------------------------
!> write out failed forward operators
!> This was part of obs_space_diagnostics

subroutine verbose_forward_op_output(qc_ens_handle, prior_post, ens_size, keys)

type(ensemble_type), intent(inout) :: qc_ens_handle
integer,             intent(in)    :: prior_post
integer,             intent(in)    :: ens_size
integer,             intent(in)    :: keys(:) ! I think this is still var size

character*12 :: task
integer :: j, i
integer :: forward_unit

write(task, '(i6.6)') my_task_id()

! all tasks open file?
if(prior_post == PRIOR_DIAG) then
   forward_unit = open_file('prior_forward_ope_errors' // task, 'formatted', 'append')
else
   forward_unit = open_file('post_forward_ope_errors' // task, 'formatted', 'append')
endif

! qc_ens_handle is a real representing an integer; values /= 0 get written out
do i = 1, ens_size
   do j = 1, qc_ens_handle%my_num_vars
      if(nint(qc_ens_handle%copies(i, j)) /= 0) write(forward_unit, *) i, keys(j), nint(qc_ens_handle%copies(i, j))
   end do
end do

call close_file(forward_unit)

end subroutine verbose_forward_op_output

!------------------------------------------------------------------
!> Produces an ensemble by copying my_vars of the 1st ensemble member
!> and then perturbing the copies array.
!> Mimicks the behaviour of pert_model_state:
!> pert_model_copies is called:
!>   if no model perturb is provided, perturb_copies_task_bitwise is called.
!> Note: Not enforcing a model_mod to produce a
!> pert_model_copies that is bitwise across any number of
!> tasks, although there is enough information in the
!> ens_handle to do this.
!>
!> Some models allow missing_r8 in the state vector.  If missing_r8 is
!> allowed the locations of missing_r8s are stored before the perturb,
!> then the missing_r8s are put back in after the perturb.

subroutine create_ensemble_from_single_file(ens_handle)

type(ensemble_type), intent(inout) :: ens_handle

integer               :: i ! loop variable
logical               :: interf_provided ! model does the perturbing
logical, allocatable  :: miss_me(:)

! Copy from ensemble member 1 to the other copies
do i = 1, ens_handle%my_num_vars
   ens_handle%copies(2:ens_size, i) = ens_handle%copies(1, i)  ! How slow is this?
enddo

! store missing_r8 locations
if (get_missing_ok_status()) then ! missing_r8 is allowed in the state
   allocate(miss_me(ens_size))
   miss_me = .false.
   where(ens_handle%copies(1, :) == missing_r8) miss_me = .true.
endif

call pert_model_copies(ens_handle, ens_size, perturbation_amplitude, interf_provided)
if (.not. interf_provided) then
   call perturb_copies_task_bitwise(ens_handle)
endif

! Put back in missing_r8
if (get_missing_ok_status()) then
   do i = 1, ens_size
      where(miss_me) ens_handle%copies(i, :) = missing_r8
   enddo
endif

end subroutine create_ensemble_from_single_file


!------------------------------------------------------------------
! Perturb the copies array in a way that is bitwise reproducible
! no matter how many task you run on.

subroutine perturb_copies_task_bitwise(ens_handle)

type(ensemble_type), intent(inout) :: ens_handle

integer               :: i, j ! loop variables
type(random_seq_type) :: r(ens_size)
real(r8)              :: random_number(ens_size) ! array of random numbers
integer               :: local_index

! Need ens_size random number sequences.
do i = 1, ens_size
   call init_random_seq(r(i), i)
enddo

local_index = 1 ! same across the ensemble

! Only one task is going to update per i.  This will not scale at all.
do i = 1, ens_handle%num_vars

   do j = 1, ens_size
     ! Can use %copies here because the random number
     ! is only relevant to the task than owns element i.
     random_number(j)  =  random_gaussian(r(j), ens_handle%copies(j, local_index), perturbation_amplitude)
   enddo

   if (ens_handle%my_vars(local_index) == i) then
      ens_handle%copies(1:ens_size, local_index) = random_number(:)
      local_index = local_index + 1 ! task is ready for the next random number
      local_index = min(local_index, ens_handle%my_num_vars)
   endif

enddo

end subroutine perturb_copies_task_bitwise

!------------------------------------------------------------------
!> Set the time on any extra copies that a pe owns
!> Could we just set the time on all copies?

subroutine set_time_on_extra_copies(ens_handle)

type(ensemble_type), intent(inout) :: ens_handle

integer :: copy_num, owner, owners_index
integer :: ens_size

ens_size = ens_handle%num_copies - ens_handle%num_extras

do copy_num = ens_size + 1, ens_handle%num_copies
   ! Set time for a given copy of an ensemble
   call get_copy_owner_index(copy_num, owner, owners_index)
   if(ens_handle%my_pe == owner) then
      call set_ensemble_time(ens_handle, owners_index, ens_handle%current_time)
   endif
enddo

end subroutine  set_time_on_extra_copies


!------------------------------------------------------------------
!> Copy the current mean, sd, inf_mean, inf_sd to spare copies
!> Assuming that if the spare copy is there you should fill it

subroutine store_input(ens_handle)

type(ensemble_type), intent(inout) :: ens_handle

if (query_copy_present(INPUT_MEAN)) &
   ens_handle%copies(INPUT_MEAN, :) = ens_handle%copies(ENS_MEAN_COPY, :)

if (query_copy_present(INPUT_SD)) &
   ens_handle%copies(INPUT_SD, :) = ens_handle%copies(ENS_SD_COPY, :)

end subroutine store_input


!------------------------------------------------------------------
!> Copy the current mean, sd, inf_mean, inf_sd to spare copies
!> Assuming that if the spare copy is there you should fill it

subroutine store_preassim(ens_handle)

type(ensemble_type), intent(inout) :: ens_handle

integer :: i, offset

if (query_copy_present(PREASSIM_MEAN)) &
   ens_handle%copies(PREASSIM_MEAN, :) = ens_handle%copies(ENS_MEAN_COPY, :)

if (query_copy_present(PREASSIM_SD)) &
   ens_handle%copies(PREASSIM_SD, :) = ens_handle%copies(ENS_SD_COPY, :)

if (query_copy_present(PREASSIM_PRIORINF_MEAN)) &
   ens_handle%copies(PREASSIM_PRIORINF_MEAN, :) = ens_handle%copies(PRIOR_INF_COPY, :)

if (query_copy_present(PREASSIM_PRIORINF_SD)) &
   ens_handle%copies(PREASSIM_PRIORINF_SD, :) = ens_handle%copies(PRIOR_INF_SD_COPY, :)

if (query_copy_present(PREASSIM_POSTINF_MEAN)) &
   ens_handle%copies(PREASSIM_POSTINF_MEAN, :) = ens_handle%copies(POST_INF_COPY, :)

if (query_copy_present(PREASSIM_POSTINF_SD)) &
   ens_handle%copies(PREASSIM_POSTINF_SD, :) = ens_handle%copies(POST_INF_SD_COPY, :)
     
do i = 1, num_output_state_members
   offset = PREASSIM_MEM_START + i - 1
   if (query_copy_present(offset)) ens_handle%copies(offset, :) = ens_handle%copies(i, :)
enddo

end subroutine store_preassim


!------------------------------------------------------------------
!> Copy the current post_inf_mean, post_inf_sd to spare copies
!> Assuming that if the spare copy is there you should fill it
!> No need to store the mean and sd as you would with store_preassim because
!> mean and sd are not changed during filter_assim(inflate_only = .true.)

subroutine store_postassim(ens_handle)

type(ensemble_type), intent(inout) :: ens_handle

integer :: i, offset

if (query_copy_present(POSTASSIM_MEAN)) &
   ens_handle%copies(POSTASSIM_MEAN, :) = ens_handle%copies(ENS_MEAN_COPY, :)

if (query_copy_present(POSTASSIM_SD)) &
   ens_handle%copies(POSTASSIM_SD, :) = ens_handle%copies(ENS_SD_COPY, :)

if (query_copy_present(POSTASSIM_PRIORINF_MEAN)) &
   ens_handle%copies(POSTASSIM_PRIORINF_MEAN, :) = ens_handle%copies(PRIOR_INF_COPY, :)

if (query_copy_present(POSTASSIM_PRIORINF_SD)) &
   ens_handle%copies(POSTASSIM_PRIORINF_SD, :) = ens_handle%copies(PRIOR_INF_SD_COPY, :)

if (query_copy_present(POSTASSIM_POSTINF_MEAN)) &
   ens_handle%copies(POSTASSIM_POSTINF_MEAN, :) = ens_handle%copies(POST_INF_COPY, :)

if (query_copy_present(POSTASSIM_POSTINF_SD)) &
   ens_handle%copies(POSTASSIM_POSTINF_SD, :) = ens_handle%copies(POST_INF_SD_COPY, :)

do i = 1, num_output_state_members
   offset = POSTASSIM_MEM_START + i - 1
   if (query_copy_present(offset)) ens_handle%copies(offset, :) = ens_handle%copies(i, :)
enddo

end subroutine store_postassim


!------------------------------------------------------------------
!> Count the number of copies to be allocated for the ensemble manager

function count_state_ens_copies(ens_size) result(num_copies)

integer, intent(in) :: ens_size
integer :: num_copies

integer :: cnum = 0

! Filter Ensemble Members
!   ENS_MEM_XXXX
ENS_MEM_START = next_copy_number(cnum)
ENS_MEM_END   = next_copy_number(cnum, ens_size)

! Filter Extra Copies For Assimilation
!    ENS_MEAN_COPY    
!    ENS_SD_COPY      
!    PRIOR_INF_COPY   
!    PRIOR_INF_SD_COPY
!    POST_INF_COPY    
!    POST_INF_SD_COPY 

ENS_MEAN_COPY     = next_copy_number(cnum)
ENS_SD_COPY       = next_copy_number(cnum)
PRIOR_INF_COPY    = next_copy_number(cnum)
PRIOR_INF_SD_COPY = next_copy_number(cnum)
POST_INF_COPY     = next_copy_number(cnum)
POST_INF_SD_COPY  = next_copy_number(cnum)

! If there are no diagnostic files, we will need to store the
! copies that would have gone in Prior_Diag.nc and Posterior_Diag.nc
! in spare copies in the ensemble.

if (write_all_stages_at_end) then
   if (get_stage_to_write('input')) then
      ! Option to Output Input Mean and SD
      !   INPUT_MEAN
      !   INPUT_SD  
      if (output_mean) then
         INPUT_MEAN = next_copy_number(cnum)
      endif
      if (output_sd) then
         INPUT_SD   = next_copy_number(cnum)
      endif
   endif

   if (get_stage_to_write('preassim')) then
      ! Option to Output Preassim Ensemble Members After Prior Inflation
      !   PREASSIM_MEM_START
      !   PREASSIM_MEM_END = PREASSIM_MEM_START + num_output_state_members - 1
      PREASSIM_MEM_START = next_copy_number(cnum)
      PREASSIM_MEM_END   = next_copy_number(cnum, num_output_state_members)

      ! Option to Output Input Mean and SD
      !   PREASSIM_MEAN
      !   PREASSIM_SD
      if (output_mean) then
         PREASSIM_MEAN = next_copy_number(cnum)
      endif
      if (output_sd) then
         PREASSIM_SD   = next_copy_number(cnum)
      endif

      if (output_inflation) then
         ! Option to Output Preassim Infation with Damping
         !    PREASSIM_PRIORINF_MEAN
         !    PREASSIM_PRIORINF_SD
         if (do_prior_inflate) then
            PREASSIM_PRIORINF_MEAN = next_copy_number(cnum)
            PREASSIM_PRIORINF_SD   = next_copy_number(cnum)
         endif
         if (do_posterior_inflate) then
            PREASSIM_POSTINF_MEAN  = next_copy_number(cnum)
            PREASSIM_POSTINF_SD    = next_copy_number(cnum)
         endif
      endif
   endif

   if (get_stage_to_write('postassim')) then
      ! Option to Output Postassim Ensemble Members Before Posterior Inflation
      !   POSTASSIM_MEM_START
      !   POSTASSIM_MEM_END = POSTASSIM_MEM_START + num_output_state_members - 1
      POSTASSIM_MEM_START = next_copy_number(cnum)
      POSTASSIM_MEM_END   = next_copy_number(cnum, num_output_state_members)

      ! Option to Output Input Mean and SD
      !   POSTASSIM_MEAN
      !   POSTASSIM_SD
      if (output_mean) then
         POSTASSIM_MEAN = next_copy_number(cnum)
      endif
      if (output_sd) then
         POSTASSIM_SD   = next_copy_number(cnum)
      endif

      if (output_inflation) then
         ! Option to Output POSTASSIM Infation with Damping
         !    POSTASSIM_PRIORINF_MEAN
         !    POSTASSIM_PRIORINF_SD
         !    POSTASSIM_POSTINF_MEAN
         !    POSTASSIM_POSTINF_SD
         if (do_prior_inflate) then
            POSTASSIM_PRIORINF_MEAN = next_copy_number(cnum)
            POSTASSIM_PRIORINF_SD   = next_copy_number(cnum)
         endif
         if (do_posterior_inflate) then
            POSTASSIM_POSTINF_MEAN  = next_copy_number(cnum)
            POSTASSIM_POSTINF_SD    = next_copy_number(cnum)
         endif
      endif
   endif

else

   ! Write everything in stages
   INPUT_MEAN              = ENS_MEAN_COPY
   INPUT_SD                = ENS_SD_COPY
  
   PREASSIM_MEM_START      = ENS_MEM_START
   PREASSIM_MEM_END        = ENS_MEM_END
   PREASSIM_MEAN           = ENS_MEAN_COPY
   PREASSIM_SD             = ENS_SD_COPY
   PREASSIM_PRIORINF_MEAN  = PRIOR_INF_COPY
   PREASSIM_PRIORINF_SD    = PRIOR_INF_SD_COPY
   PREASSIM_POSTINF_MEAN   = POST_INF_COPY
   PREASSIM_POSTINF_SD     = POST_INF_SD_COPY
  
   POSTASSIM_MEM_START     = ENS_MEM_START
   POSTASSIM_MEM_END       = ENS_MEM_END
   POSTASSIM_MEAN          = ENS_MEAN_COPY
   POSTASSIM_SD            = ENS_SD_COPY
   POSTASSIM_PRIORINF_MEAN = PRIOR_INF_COPY
   POSTASSIM_PRIORINF_SD   = PRIOR_INF_SD_COPY
   POSTASSIM_POSTINF_MEAN  = POST_INF_COPY
   POSTASSIM_POSTINF_SD    = POST_INF_SD_COPY

endif


! CSS If Whitaker/Hamill (2012) relaxation-to-prior-spread (rpts) inflation (inf_flavor = 4)
!  then we need an extra copy to hold (save) the prior ensemble spread
!   ENS_SD_COPY will be overwritten with the posterior spread before
!   applying the inflation algorithm; hence we must save the prior ensemble spread in a different copy
if ( inf_flavor(2) == 4 ) then ! CSS
   SPARE_PRIOR_SPREAD = next_copy_number(cnum)
endif 


num_copies = cnum

end function count_state_ens_copies


!------------------------------------------------------------------
!> Set file name information.  For members restarts can be read from
!> a restart_file_list.txt or constructed using a stage name and
!> num_ens.  The file_info handle knows whether or not there is an
!> associated restart_file_list.txt. If no list is provided member
!> filenames are written as :
!>    stage_member_####.nc (ex. preassim_member_0001.nc)
!> extra copies are stored as :
!>    stage_basename.nc (ex. preassim_mean.nc)

subroutine set_filename_info(file_info, stage, num_ens, &
                             MEM_START, MEM_END, ENS_MEAN, ENS_SD, &
                             PRIOR_INF_MEAN, PRIOR_INF_SD, POST_INF_MEAN, POST_INF_SD)

type(file_info_type), intent(inout) :: file_info
character(len=*),     intent(in)    :: stage
integer,              intent(in)    :: num_ens
integer,              intent(inout) :: MEM_START
integer,              intent(inout) :: MEM_END
integer,              intent(inout) :: ENS_MEAN
integer,              intent(inout) :: ENS_SD
integer,              intent(inout) :: PRIOR_INF_MEAN
integer,              intent(inout) :: PRIOR_INF_SD
integer,              intent(inout) :: POST_INF_MEAN
integer,              intent(inout) :: POST_INF_SD

call set_member_file_metadata(file_info, num_ens, MEM_START)

MEM_END = MEM_START + num_ens - 1

call set_file_metadata(file_info, ENS_MEAN,       stage, 'mean',          'ensemble mean')
call set_file_metadata(file_info, ENS_SD,         stage, 'sd',            'ensemble sd')
call set_file_metadata(file_info, PRIOR_INF_MEAN, stage, 'priorinf_mean', 'prior inflation mean')
call set_file_metadata(file_info, PRIOR_INF_SD,   stage, 'priorinf_sd',   'prior inflation sd')
call set_file_metadata(file_info, POST_INF_MEAN,  stage, 'postinf_mean',  'posterior inflation mean')
call set_file_metadata(file_info, POST_INF_SD,    stage, 'postinf_sd',    'posterior inflation sd')

end subroutine set_filename_info

!------------------------------------------------------------------

subroutine set_input_file_info( file_info, num_ens, MEM_START, &
                         PRIOR_INF_MEAN, PRIOR_INF_SD, POST_INF_MEAN, POST_INF_SD)

type(file_info_type), intent(inout) :: file_info
integer,              intent(in)    :: num_ens
integer,              intent(in)    :: MEM_START
integer,              intent(in)    :: PRIOR_INF_MEAN
integer,              intent(in)    :: PRIOR_INF_SD
integer,              intent(in)    :: POST_INF_MEAN
integer,              intent(in)    :: POST_INF_SD

if ( perturb_from_single_instance ) then
   call set_io_copy_flag(file_info, MEM_START, READ_COPY)
   !>@todo know whether we are perturbing or not
   !#! call set_perturb_members(file_info, MEM_START, num_ens)
else
   call set_io_copy_flag(file_info, MEM_START, MEM_START+num_ens-1, READ_COPY)
endif

if ( do_prior_inflate ) then
   if ( inf_initial_from_restart(1)    ) &
      call set_io_copy_flag(file_info, PRIOR_INF_MEAN, READ_COPY, has_units=.false.)
   if ( inf_sd_initial_from_restart(1) ) &
      call set_io_copy_flag(file_info, PRIOR_INF_SD,   READ_COPY, has_units=.false.)
endif

if ( do_posterior_inflate ) then
   if ( inf_initial_from_restart(2)    ) &
      call set_io_copy_flag(file_info, POST_INF_MEAN,  READ_COPY, has_units=.false.)
   if ( inf_sd_initial_from_restart(2) ) &
      call set_io_copy_flag(file_info, POST_INF_SD,    READ_COPY, has_units=.false.)
endif

end subroutine set_input_file_info

!------------------------------------------------------------------

subroutine set_output_file_info( file_info, num_ens, MEM_START, ENS_MEAN, &
                                 ENS_SD, PRIOR_INF_MEAN, PRIOR_INF_SD, &
                                 POST_INF_MEAN, POST_INF_SD, do_clamping, &
                                 force_copy)

type(file_info_type), intent(inout) :: file_info
integer,              intent(in)    :: num_ens
integer,              intent(in)    :: MEM_START
integer,              intent(in)    :: ENS_MEAN
integer,              intent(in)    :: ENS_SD
integer,              intent(in)    :: PRIOR_INF_MEAN
integer,              intent(in)    :: PRIOR_INF_SD
integer,              intent(in)    :: POST_INF_MEAN
integer,              intent(in)    :: POST_INF_SD
logical,              intent(in)    :: do_clamping
logical,              intent(in)    :: force_copy

integer :: MEM_END

MEM_END = MEM_START+num_ens-1

!>@todo revisit if we should be clamping mean copy for file_info_output
if ( output_members )      &
   call set_io_copy_flag(file_info, MEM_START, MEM_END, WRITE_COPY, &
                         num_output_ens=num_ens, clamp_vars=do_clamping, &
                         force_copy_back=force_copy)
if ( output_mean )          &
   call set_io_copy_flag(file_info, ENS_MEAN,           WRITE_COPY, &
                         clamp_vars=do_clamping, force_copy_back=force_copy)
if ( output_sd )            &
   call set_io_copy_flag(file_info, ENS_SD,             WRITE_COPY, &
                         has_units=.false., force_copy_back=force_copy)
if ( do_prior_inflate )     &
   call set_io_copy_flag(file_info, PRIOR_INF_MEAN,     WRITE_COPY, &
                         has_units=.false., force_copy_back=force_copy)
if ( do_prior_inflate )     &
   call set_io_copy_flag(file_info, PRIOR_INF_SD,       WRITE_COPY, &
                         has_units=.false., force_copy_back=force_copy)
if ( do_posterior_inflate ) &
   call set_io_copy_flag(file_info, POST_INF_MEAN,      WRITE_COPY, &
                         has_units=.false., force_copy_back=force_copy)
if ( do_posterior_inflate ) &
   call set_io_copy_flag(file_info, POST_INF_SD,        WRITE_COPY, &
                         has_units=.false., force_copy_back=force_copy)

end subroutine set_output_file_info

!-----------------------------------------------------------
!> checks the user input and informs the IO modules which files to write.


subroutine parse_stages_to_write(stages)

character(len=*), intent(in) :: stages(:)

integer :: nstages, i
character (len=32) :: my_stage

nstages = size(stages,1)

do i = 1, nstages
   my_stage = stages(i)
   call to_upper(my_stage)
   if (trim(my_stage) /= trim('NULL')) then
      call set_stage_to_write(stages(i),.true.)
      write(msgstring,*)"filter will write stage : "//trim(stages(i))
      call error_handler(E_MSG,'parse_stages_to_write', &
                         msgstring,source,revision,revdate)
   endif
enddo

end subroutine parse_stages_to_write

!-----------------------------------------------------------
!> checks the user input and informs the IO modules which files to write.


function next_copy_number(cnum, ncopies)
integer, intent(inout)        :: cnum
integer, intent(in), optional :: ncopies
integer :: next_copy_number

if (present(ncopies)) then
   next_copy_number = cnum + ncopies - 1
else
   next_copy_number = cnum + 1
endif

cnum = next_copy_number

end function next_copy_number

!-----------------------------------------------------------
!> initialize file names and which copies should be read and or written


subroutine initialize_file_information(num_state_ens_copies, file_info_input, &
                                       file_info_preassim, file_info_postassim, &
                                       file_info_output)

integer,              intent(in)    :: num_state_ens_copies
type(file_info_type), intent(out) :: file_info_input
type(file_info_type), intent(out) :: file_info_preassim
type(file_info_type), intent(out) :: file_info_postassim
type(file_info_type), intent(out) :: file_info_output

!>@todo FIXME temporary error message until we handle filename in the namelist
!> (for now, you need to use the indirect file which contains a list of files)
if (( input_state_files(1) /= 'null' .and.  input_state_files(1) /= '') .or. &
    (output_state_files(1) /= 'null' .and. output_state_files(1) /= '')) then
   call error_handler(E_ERR,'initialize_file_information', &
                      'input_state_files and output_state_files are currently unsupported.',  &
                      source, revision, revdate, &
                      text2='please use input_state_file_list and output_state_file_list instead')
endif

! Allocate space for the filename handles
call io_filenames_init(file_info_input,     num_state_ens_copies, has_cycling, single_file_in,      &
                                            restart_list=input_state_file_list,  &
                                            root_name='input')
call io_filenames_init(file_info_preassim,  num_state_ens_copies, has_cycling, single_file_out,     &
                                            root_name='preassim')
call io_filenames_init(file_info_postassim, num_state_ens_copies, has_cycling, single_file_out,     &
                                            root_name='postassim')
call io_filenames_init(file_info_output,    num_state_ens_copies, has_cycling, single_file_out,     &
                                            restart_list=output_state_file_list, &
                                            root_name='output', &
                                            check_output_compatibility = .true.)

! Set filename information
call set_filename_info(file_info_input,    'input', ens_size, &
                       ENS_MEM_START, ENS_MEM_END, INPUT_MEAN, INPUT_SD,      &
                       PRIOR_INF_COPY, PRIOR_INF_SD_COPY, &
                       POST_INF_COPY, POST_INF_SD_COPY)
call set_filename_info(file_info_preassim, 'preassim', num_output_state_members, &
                       PREASSIM_MEM_START, PREASSIM_MEM_END, PREASSIM_MEAN, PREASSIM_SD, &
                       PREASSIM_PRIORINF_MEAN, PREASSIM_PRIORINF_SD, &
                       PREASSIM_POSTINF_MEAN,  PREASSIM_POSTINF_SD)
call set_filename_info(file_info_postassim,'postassim', num_output_state_members,  &
                       POSTASSIM_MEM_START, POSTASSIM_MEM_END, POSTASSIM_MEAN, POSTASSIM_SD, &
                       POSTASSIM_PRIORINF_MEAN, POSTASSIM_PRIORINF_SD, &
                       POSTASSIM_POSTINF_MEAN , POSTASSIM_POSTINF_SD)
call set_filename_info(file_info_output,   'output', ens_size, &
                       ENS_MEM_START, ENS_MEM_END, ENS_MEAN_COPY, ENS_SD_COPY, &
                       PRIOR_INF_COPY, PRIOR_INF_SD_COPY, &
                       POST_INF_COPY, POST_INF_SD_COPY)

! Set which copies should be read and written
call set_input_file_info(  file_info_input, ens_size, &
                           ENS_MEM_START, &
                           PRIOR_INF_COPY, PRIOR_INF_SD_COPY, &
                           POST_INF_COPY, POST_INF_SD_COPY)
call set_output_file_info( file_info_preassim, num_output_state_members, &
                           PREASSIM_MEM_START, PREASSIM_MEAN, PREASSIM_SD, &
                           PREASSIM_PRIORINF_MEAN, PREASSIM_PRIORINF_SD, &
                           PREASSIM_POSTINF_MEAN,  PREASSIM_POSTINF_SD, &
                           do_clamping=.false., force_copy=.true.)
call set_output_file_info( file_info_postassim, num_output_state_members, &
                           POSTASSIM_MEM_START, POSTASSIM_MEAN, POSTASSIM_SD, &
                           POSTASSIM_PRIORINF_MEAN, POSTASSIM_PRIORINF_SD, &
                           POSTASSIM_POSTINF_MEAN , POSTASSIM_POSTINF_SD, &
                           do_clamping=.false., force_copy=.true.)
call set_output_file_info( file_info_output, ens_size, &
                           ENS_MEM_START, ENS_MEAN_COPY, ENS_SD_COPY, &
                           PRIOR_INF_COPY, PRIOR_INF_SD_COPY, &
                           POST_INF_COPY, POST_INF_SD_COPY, &
                           do_clamping=.true., force_copy=.false.)

end subroutine initialize_file_information

!==================================================================
! TEST FUNCTIONS BELOW THIS POINT
!------------------------------------------------------------------
!> dump out obs_copies to file
subroutine test_obs_copies(obs_fwd_op_ens_handle, information)

type(ensemble_type), intent(in) :: obs_fwd_op_ens_handle
character(len=*),    intent(in) :: information

character*20  :: task_str !< string to hold the task number
character*129 :: file_obscopies !< output file name
integer :: i

write(task_str, '(i10)') obs_fwd_op_ens_handle%my_pe
file_obscopies = TRIM('obscopies_' // TRIM(ADJUSTL(information)) // TRIM(ADJUSTL(task_str)))
open(15, file=file_obscopies, status ='unknown')

do i = 1, obs_fwd_op_ens_handle%num_copies - 4
   write(15, *) obs_fwd_op_ens_handle%copies(i,:)
enddo

close(15)

end subroutine test_obs_copies

!-------------------------------------------------------------------
end module filter_mod

! <next few lines under version control, do not edit>
! $URL: https://svn-dares-dart.cgd.ucar.edu/DART/releases/Manhattan/assimilation_code/modules/assimilation/filter_mod.f90 $
! $Id: filter_mod.f90 11474 2017-04-13 15:26:47Z nancy@ucar.edu $
! $Revision: 11474 $
! $Date: 2017-04-13 11:26:47 -0400 (Thu, 13 Apr 2017) $
