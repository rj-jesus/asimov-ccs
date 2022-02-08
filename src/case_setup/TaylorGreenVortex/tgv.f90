
program tgv

  use, intrinsic :: iso_fortran_env, only:  output_unit

  use yaml, only: parse, error_length
  use read_config, only: get_case_name
  use kinds, only : accs_int, accs_real
  use parallel, only: initialise_parallel_environment, &
                      cleanup_parallel_environment
  use parallel_types, only: parallel_environment
  use types, only: io_environment, &
                   io_process
  use io, only: initialise_io, cleanup_io, configure_io, &
                open_file, close_file, &
                read_scalar, read_array

  implicit none

  class(*), pointer :: config_file
  character(len=error_length) :: error

  ! Case title
  character(len=:), allocatable :: case_name
  ! Geo file name
  character(len=:), allocatable :: geo_file

  class(parallel_environment), allocatable :: par_env
  class(io_environment), allocatable :: io_env
  class(io_process), allocatable :: geo_reader

  real, dimension(:,:), allocatable :: xyz_coords
  integer, dimension(:), allocatable :: vtxdist
  integer(kind=8), dimension(2) :: xyz_sel_start, xyz_sel_count

  integer(accs_int) :: irank, isize, i, j, k  
  integer(accs_int) :: local_idx_start, local_idx_end
  integer(accs_int) :: max_faces
  integer(accs_int) :: num_faces
  integer(accs_int) :: num_cells

  integer(accs_int) :: dims = 3

  ! Launch MPI
  call initialise_parallel_environment(par_env) 

  irank = par_env%proc_id
  isize = par_env%num_procs

  call initialise_io(par_env, "adios2-config.xml", io_env)

  ! Read case name from configuration file
  call read_configuration()

  geo_file = case_name//".geo"
  
  call configure_io(io_env, "test_reader", geo_reader)

  call open_file(geo_file, "read", geo_reader)

  call read_scalar(geo_reader, "ncel", num_cells)
  call read_scalar(geo_reader, "nfac", num_faces)
  call read_scalar(geo_reader, "maxfaces", max_faces)

  print*, "Max number of faces: ", max_faces
  print*, "Total number of faces: ", num_faces
  print*, "Total number of cells: ", num_cells

  ! Store cell range assigned to each process      
  allocate(vtxdist(isize+1))

  vtxdist(1) = 1
  vtxdist(isize + 1) = num_cells + 1

  k = int(real(num_cells) / isize)
  j = 1
  do i = 1, isize
     vtxdist(i) = j
     j = j + k
  enddo

  print*, "vtxdist: ", vtxdist

  ! First and last cell index assigned to this process
  local_idx_start = vtxdist(irank + 1)
  local_idx_end = vtxdist(irank + 2) - 1

  print*, "Rank ",irank,", local start and end indices: ", local_idx_start," - ", local_idx_end

  ! Starting point for reading chunk of data
  xyz_sel_start = (/ 0, vtxdist(irank + 1) - 1 /)
  ! How many data points will be read?
  xyz_sel_count = (/ dims, vtxdist(irank + 2) - vtxdist(irank + 1)/)

  allocate(xyz_coords(xyz_sel_count(1), xyz_sel_count(2)))

  call read_array(geo_reader, "/cell/x", xyz_sel_start , xyz_sel_count, xyz_coords)

  call close_file(geo_reader)

  call cleanup_io(io_env)

  call cleanup_parallel_environment(par_env)

  contains

  subroutine read_configuration()

    config_file => parse("./tgv_config.yaml", error=error)
    if (error/='') then
      print*,trim(error)
      stop 1
    endif
    
    ! Get title
    call get_case_name(config_file, case_name)

  end subroutine

end program tgv
