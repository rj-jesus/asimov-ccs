!> Test that partitions a square mesh generated by CCS
!
!> The square mesh has a simple partition and is already connected, computing the connectivity
!> should not change the connectivity.

program test_partition_square_mesh
#include "ccs_macros.inc"

  use mpi

  use testing_lib
  use partitioning, only: compute_partitioner_input, &
                          partition_kway, compute_connectivity
  use kinds, only: ccs_int, ccs_long
  use types, only: topology
  use mesh_utils, only : build_square_mesh

  use utils, only : debug_print

  implicit none

  type(topology) :: topo
  type(ccs_mesh), target :: mesh
  integer :: i, j, n

  integer, parameter :: topo_idx_type = kind(topo%adjncy(1))
  integer(topo_idx_type) :: current, previous

  integer(topo_idx_type), dimension(:), allocatable :: tmp_partition
  
  call init()
  call initialise_test()

  n = count(mesh%neighbour_indices > 0)
  print*,"Number of positive value neighbour indices: ", n
  print*,"Adjacency arrays: ", topo%adjncy
  print*,"Adjacency index array: ", topo%xadj
  
  call partition_kway(par_env, topo)

  if(par_env%proc_id == 0) then
    print*, "Global partition after partitioning:"
    do i=1,topo%global_num_cells
      print*, topo%global_partition(i)
    end do
  end if

  ! Compute new connectivity after partitioning
  call compute_connectivity(par_env, topo)

  call check_topology("post")

  call clean_test()
  call fin()

contains

  subroutine check_topology(stage)

    character(len=*), intent(in) :: stage

    !if (size(topo%nb_indices, 2) /= size(mesh%neighbour_indices, 2) .or. &
    !     size(topo%nb_indices, 1) /= size(mesh%neighbour_indices, 1)) then
    !  print *, "TOPO local_num_cells: ", topo%local_num_cells
    !  print *, "TOPO nb_indices: ", size(topo%nb_indices, 1), size(topo%nb_indices, 2)
    !  print *, "TOPO partition: ", topo%global_partition
    !  print *, "MESH nlocal: ", mesh%nlocal
    !  print *, "MESH nb_indices: ", size(mesh%neighbour_indices, 1), size(mesh%neighbour_indices, 2)
    !  write(message, *) "ERROR: topology size is wrong!"
    !  call stop_test(message)
    !end if

    call check_self_loops(stage)
    call check_connectivity(stage)

  end subroutine

  subroutine check_self_loops(stage)

    character(len=*), intent(in) :: stage

    integer :: i

    do i = 1, topo%local_num_cells
      do j = topo%xadj(i), topo%xadj(i + 1) - 1
        if (topo%adjncy(j) == topo%global_indices(i)) then
          print *, "TOPO neighbours @ global idx ", topo%global_indices(i), ": ", topo%adjncy(topo%xadj(i):topo%xadj(i+1) - 1)
          write(message, *) "ERROR: found self-loop "//stage//"-partitioning!"
          call stop_test(message)
        end if
      end do
    end do
  end subroutine

  subroutine check_connectivity(stage)
 
    character(len=*), intent(in) :: stage

    integer :: i, j
    integer :: nadj
    integer, dimension(:), allocatable :: adjncy_global_expected

    !if (all(topo%nb_indices /= mesh%neighbour_indices)) then
    !  write(message, *) "ERROR: topology changed!"
    !  call stop_test(message)
    !end if
   
    do i = 1, topo%local_num_cells ! Loop over local cells
      
      nadj = topo%xadj(i+1) - topo%xadj(i)
      allocate( adjncy_global_expected(nadj) )

      call compute_expected_global_adjncy(i, adjncy_global_expected)

      do j = topo%xadj(i), topo%xadj(i + 1) - 1
        if (.not. any(adjncy_global_expected == topo%adjncy(j))) then
          print *, "TOPO neighbours @ global idx ", topo%global_indices(i), ": ", topo%adjncy(topo%xadj(i):topo%xadj(i+1) - 1)
          print *, "Expected nieghbours @ global idx ", topo%global_indices(i), ": ", adjncy_global_expected
          write(message, *) "ERROR: neighbours are wrong "//stage//"-partitioning!"
          call stop_test(message)
        end if
      end do

      deallocate(adjncy_global_expected)
    end do

  end subroutine
          
  subroutine compute_expected_global_adjncy(i, adjncy_global_expected)

    integer, intent(in) :: i
    integer, dimension(:), intent(inout) :: adjncy_global_expected

    integer :: interior_ctr

    adjncy_global_expected(:) = 0
    interior_ctr = 1

    associate( idx_global => topo%global_indices(i), &
               cidx_global => (topo%global_indices(i) - 1) )
      if ((modulo(cidx_global, 4) /= 0) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ left boundary
        adjncy_global_expected(interior_ctr) = idx_global - 1
        interior_ctr = interior_ctr + 1
      end if

      if ((modulo(cidx_global, 4) /= (4 - 1)) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ right boundary
        adjncy_global_expected(interior_ctr) = idx_global + 1
        interior_ctr = interior_ctr + 1
      end if

      if (((cidx_global / 4) /= 0) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ bottom boundary
        adjncy_global_expected(interior_ctr) = idx_global - 4
        interior_ctr = interior_ctr + 1
      end if

      if (((cidx_global / 4) /= (4 - 1)) .and. (interior_ctr <= size(adjncy_global_expected))) then
        ! NOT @ top boundary
        adjncy_global_expected(interior_ctr) = idx_global + 4
        interior_ctr = interior_ctr + 1
      end if
    end associate

  end subroutine

  subroutine initialise_test

    ! Create a square mesh
    print *, "Building mesh"
    mesh = build_square_mesh(par_env, 4, 1.0_ccs_real)
  
    !! --- read_topology() ---
    topo%global_num_cells = mesh%nglobal
    topo%global_num_faces = 40 ! Hardcoded for now
    topo%max_faces = mesh%nnb(1)
    allocate(topo%face_cell1(topo%global_num_faces))
    allocate(topo%face_cell2(topo%global_num_faces))
    allocate(topo%global_face_indices(topo%max_faces, topo%global_num_cells))
    
    ! Hardcode for now
    topo%face_cell1 = (/ 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, &
                         5, 5, 5, 6,  6, 7,  7, 8,  8, &
                         9,  9,  9, 10, 10, 11, 11, 12, 12, &
                         13, 13, 13, 14, 14, 15, 15, 16, 16 /)
    topo%face_cell2 = (/ 0, 2, 0, 5, 3, 0, 6, 4, 0, 7, 0, 0, 8, & 
                         0, 6, 9, 7, 10, 8, 11, 0, 12, 0, &
                         10, 13, 11, 14, 12, 15,  0, 16, &
                         0, 14,  0, 15,  0, 16,  0,  0,  0/)
  
    ! <MISSING> set topo%global_face_indices
    
    !! --- read_topology() --- end
  
    !! --- compute_partitioner_input() ---
    allocate(topo%vtxdist(par_env%num_procs + 1))
    allocate(topo%global_partition(topo%global_num_cells))
  
    ! Hardcode vtxdist for now
    topo%vtxdist = (/ 1, 5, 9, 13, 17 /)
  
    ! <MISSING> set topo%global_partition array?
    ! FAKE partition array based on initial mesh decomposition
    do i = 1, topo%global_num_cells
      if (any(mesh%global_indices(1:mesh%nlocal) == i)) then
        topo%global_partition(i) = par_env%proc_id
      else
        topo%global_partition(i) = -1
      end if
    end do
   
    !select type(par_env)
    !type is (parallel_environment_mpi)
    !  allocate(tmp_partition, source=topo%global_partition)
    !  write(message, *) "Initial partition: ", tmp_partition
    !  call dprint(message)
    !  call MPI_Allreduce(tmp_partition, topo%global_partition, topo%global_num_cells, &
    !          MPI_LONG, MPI_SUM, &
    !          par_env%comm, ierr)
    !  deallocate(tmp_partition)
    !  write(message, *) "Using partition: ", topo%global_partition
    !  call dprint(message)
    !class default
    !  write(message, *) "ERROR: This test only works for MPI!"
    !  call stop_test(message)
    !end select
    
    topo%local_num_cells = mesh%nlocal
    allocate(topo%xadj(topo%local_num_cells + 1))
  
    ! <MISSING> allocate topo%global_boundaries
    ! <MISSING> allocate topo%adjncy
    
    allocate(topo%local_partition(topo%local_num_cells))
    topo%halo_num_cells = mesh%nhalo
  
    select type(par_env)
    type is (parallel_environment_mpi)
  
      ! Also hardcode the adjncy arrays
      if(par_env%num_procs == 4) then
  
        if(par_env%proc_id == 0) then
          topo%adjncy = (/ 2, 5, 1, 3, 6, 2, 4, 7, 3, 8 /)
        else if (par_env%proc_id == 1) then
          topo%adjncy = (/ 1, 6, 9, 2, 5, 7, 10, 3, 6, 8, 11, 4, 7, 12 /)
        else if (par_env%proc_id == 2) then
          topo%adjncy = (/ 5, 10, 13, 6, 9, 11, 14, 7, 10, 12, 15, 8, 11, 16 /)
        else 
          topo%adjncy = (/ 9, 14, 10, 13, 15, 11, 14, 16, 12, 15 /)
        end if
  
      else
        write(message, *) "Test must be run on 4 MPI ranks"
        call stop_test(message)
      end if 
   
    class default
      write(message, *) "ERROR: Unknown parallel environment!"
      call stop_test(message)
    end select
  
    ! Now compute the adjacency index array
    j = 1
    topo%xadj(j) = 1
    previous = topo%adjncy(1)
  
    do i = 2, size(topo%adjncy)
      current = topo%adjncy(i)
      if (current < previous) then
        j = j + 1
        topo%xadj(j) = i 
      end if
      previous = current
    end do
  
    topo%xadj(j + 1) = size(topo%adjncy) + 1
  
    allocate(topo%adjwgt(size(topo%adjncy)))
    allocate(topo%vwgt(topo%local_num_cells))
  
    !! --- compute_partitioner_input() --- end
    
    ! Assign corresponding mesh values to the topology object
    topo%total_num_cells = mesh%ntotal
    topo%num_faces = mesh%nfaces_local
  
    allocate(topo%global_indices, source=mesh%global_indices)
    topo%global_indices = mesh%global_indices

    ! These need to be set to 1 for them to do nothing
    if (allocated(topo%adjwgt).and.allocated(topo%vwgt)) then
      topo%adjwgt = 1
      topo%vwgt = 1
    else
      call stop_test("Not allocated!!!")
    end if

    ! Run test to check we agree
    call check_topology("pre")

  end subroutine
  
  subroutine clean_test
    if(allocated(topo%xadj)) then
      deallocate(topo%xadj)
    end if

    if(allocated(topo%adjncy)) then
      deallocate(topo%adjncy)
    end if

    if(allocated(topo%adjwgt)) then
      deallocate(topo%adjwgt)
    end if

    if(allocated(topo%vwgt)) then
      deallocate(topo%vwgt)
    end if

    if(allocated(topo%vtxdist)) then
      deallocate(topo%vtxdist)
    end if
  end subroutine

end program
