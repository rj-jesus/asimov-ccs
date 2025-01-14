!v Test that partitions a square mesh generated by CCS
!
!  The square mesh has a simple partition and is already connected, computing the connectivity
!  should not change the connectivity.

program test_partition_square_mesh
#include "ccs_macros.inc"

  use mpi

  use testing_lib
  use partitioning, only: compute_partitioner_input, &
                          partition_kway, compute_connectivity
  use kinds, only: ccs_int, ccs_long
  use types, only: topology, graph_connectivity, cell_locator
  use mesh_utils, only: build_square_topology
  use meshing, only: get_local_num_cells, get_global_num_cells, &
                     create_cell_locator, get_global_index
  use meshing, only: set_mesh_object, nullify_mesh_object

  use utils, only: debug_print

  implicit none

  integer :: i, j, n

  integer, parameter :: topo_idx_type = kind(mesh%topo%graph_conn%adjncy(1))
  integer(ccs_int) :: global_num_cells

  call init()

  print *, "Building mesh."
  call build_square_topology(par_env, shared_env, 4, mesh)

  call compute_partitioner_input(par_env, shared_env, mesh)
  call set_mesh_object(mesh)

  ! Run test to check we agree
  call check_topology("pre")

  n = count(mesh%topo%nb_indices > 0)
  print *, "Number of positive value neighbour indices: ", n
  print *, "Adjacency arrays: ", mesh%topo%graph_conn%adjncy
  print *, "Adjacency index array: ", mesh%topo%graph_conn%xadj

  !call partition_stride(par_env, mesh)
  call partition_kway(par_env, shared_env, roots_env, mesh)
  call check_topology("mid")

  if (par_env%proc_id == 0) then
    print *, "Global partition after partitioning:"
    call get_global_num_cells(global_num_cells)
    do i = 1, global_num_cells
      print *, mesh%topo%graph_conn%global_partition(i)
    end do
  end if

  ! Compute new connectivity after partitioning
  call compute_connectivity(par_env, shared_env, roots_env, mesh)

  call check_topology("post")
  call nullify_mesh_object()

  call clean_test()
  call fin()

contains

  subroutine check_topology(stage)

    character(len=*), intent(in) :: stage

    ! if (size(topo%nb_indices, 2) /= size(mesh%topo%nb_indices, 2) .or. &
    !   size(topo%nb_indices, 1) /= size(mesh%topo%nb_indices, 1)) then
    !   print *, "TOPO local_num_cells: ", topo%local_num_cells
    !   print *, "TOPO nb_indices: ", size(topo%nb_indices, 1), size(topo%nb_indices, 2)
    !   print *, "TOPO partition: ", topo%global_partition
    !   print *, "MESH nb_indices: ", size(mesh%topo%nb_indices, 1), size(mesh%topo%nb_indices, 2)
    !   write(message, *) "ERROR: topology size is wrong!"
    !   call stop_test(message)
    ! end if

    call check_distribution(stage)
    call check_topology_topo(mesh%topo, stage)
    call check_self_loops(stage)
    call check_connectivity(stage)

  end subroutine check_topology
  subroutine check_topology_topo(topo, stage)

    type(topology), intent(in) :: topo
    character(len=*), intent(in) :: stage

    call check_topology_graphconn(topo%graph_conn, stage)
    
    if ((maxval(topo%global_indices) > 16) .or. (minval(topo%global_indices) < 1)) then
      write (message, *) "ERROR: global indices min/max: ", &
        minval(topo%global_indices), maxval(topo%global_indices), &
        " outside expected range: ", 1, 16
      call stop_test(message)
    end if
   
  end subroutine check_topology_topo
  subroutine check_topology_graphconn(graph_conn, stage)

    type(graph_connectivity), intent(in) :: graph_conn
    character(len=*), intent(in) :: stage

    if ((maxval(graph_conn%xadj(1:size(graph_conn%xadj) - 1)) >= size(graph_conn%adjncy)) &
        .or. (graph_conn%xadj(size(graph_conn%xadj) - 1) > size(graph_conn%adjncy))) then
      print *, graph_conn%xadj
      print *, size(graph_conn%adjncy)
      write (message, *) "ERROR: xadj array is wrong!" // stage // "-partitioning"
      call stop_test(message)
    end if
   
  end subroutine check_topology_graphconn

  subroutine check_distribution(stage)

    character(len=*), intent(in) :: stage

    call check_distribution_topo(mesh%topo, stage)
    
  end subroutine
  subroutine check_distribution_topo(topo, stage)

    type(topology), intent(in) :: topo
    character(len=*), intent(in) :: stage

    integer :: i
    integer :: ctr

    integer(ccs_int) :: global_num_cells

    ! Do some basic verification

    if (size(topo%graph_conn%vtxdist) /= (par_env%num_procs + 1)) then
      write (message, *) "ERROR: global vertex distribution is wrong size " // stage // "- partitioning."
      call stop_test(message)
    end if

    ctr = 0
    do i = 2, size(topo%graph_conn%vtxdist)
      if (topo%graph_conn%vtxdist(i) < topo%graph_conn%vtxdist(i - 1)) then
        write (message, *) "ERROR: global vertex distribution ordering is wrong " // stage // "- partitioning."
        call stop_test(message)
      end if

      ctr = ctr + int(topo%graph_conn%vtxdist(i) - topo%graph_conn%vtxdist(i - 1))
    end do

    call get_global_num_cells(global_num_cells)
    if (ctr /= global_num_cells) then
      write (message, *) "ERROR: global vertex distribution count is wrong " // stage // "- partitioning."
      call stop_test(message)
    end if
   
  end subroutine check_distribution_topo
  
  subroutine check_self_loops(stage)

    character(len=*), intent(in) :: stage

    integer(ccs_int) :: local_num_cells
    integer(ccs_int) :: i

    type(cell_locator) :: loc_p
    integer(ccs_int) :: global_index_p

    call get_local_num_cells(local_num_cells)
    do i = 1, local_num_cells
      call create_cell_locator(i, loc_p)
      call get_global_index(loc_p, global_index_p)

      do j = int(mesh%topo%graph_conn%xadj(i)), int(mesh%topo%graph_conn%xadj(i + 1)) - 1
        if (mesh%topo%graph_conn%adjncy(j) == global_index_p) then
          print *, "TOPO neighbours @ global idx ", global_index_p, ": ", &
            mesh%topo%graph_conn%adjncy(mesh%topo%graph_conn%xadj(i):mesh%topo%graph_conn%xadj(i + 1) - 1)
          write (message, *) "ERROR: found self-loop " // stage // "- partitioning."
          call stop_test(message)
        end if
      end do
    end do

  end subroutine

  subroutine check_connectivity(stage)

    character(len=*), intent(in) :: stage

    integer(ccs_int) :: i, local_num_cells

    call get_local_num_cells(local_num_cells)
    do i = 1, local_num_cells ! Loop over local cells
      call check_connectivity_cell(mesh%topo, stage)
    end do

  end subroutine check_connectivity
  subroutine check_connectivity_cell(topo, stage)

    type(topology), intent(in) :: topo
    character(len=*), intent(in) :: stage

    integer, dimension(:), allocatable :: face_cell1_expected, face_cell2_expected

    face_cell1_expected = (/1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, &
         5, 5, 5, 6, 6, 7, 7, 8, 8, &
         9, 9, 9, 10, 10, 11, 11, 12, 12, &
         13, 13, 13, 14, 14, 15, 15, 16, 16/)
    if (.not. all(face_cell1_expected == topo%face_cell1)) then
       write (message, *) "ERROR: face_cell1 not correct! " // stage // "- partitioning."
       call stop_test(message)
    end if

    face_cell2_expected = (/0, 2, 0, 5, 3, 0, 6, 4, 0, 7, 0, 0, 8, &
         0, 6, 9, 7, 10, 8, 11, 0, 12, 0, &
         10, 13, 11, 14, 12, 15, 0, 16, &
         0, 14, 0, 15, 0, 16, 0, 0, 0/)
    if (.not. all(face_cell2_expected == topo%face_cell2)) then
       write (message, *) "ERROR: face_cell2 not correct! " // stage // "- partitioning."
       call stop_test(message)
    end if
    
    deallocate (face_cell1_expected)
    deallocate (face_cell2_expected)
    
  end subroutine check_connectivity_cell
  ! subroutine check_connectivity_cell_graphconn(i, graph_conn, loc_p, stage)

  !   integer(ccs_int), intent(in) :: i
  !   type(graph_connectivity), intent(in) :: graph_conn
  !   type(cell_locator), intent(in) :: loc_p
  !   character(len=*), intent(in) :: stage

  !   integer :: j
  !   integer :: nadj
  !   integer(ccs_int) :: global_index_p
  !   integer, dimension(:), allocatable :: adjncy_global_expected
    
  !   call get_global_index(loc_p, global_index_p)

  !   nadj = int(graph_conn%xadj(i + 1) - graph_conn%xadj(i))
  !   allocate (adjncy_global_expected(nadj))

  !   call compute_expected_global_adjncy(i, adjncy_global_expected)

  !   do j = int(graph_conn%xadj(i)), int(graph_conn%xadj(i + 1)) - 1
  !      if (.not. any(adjncy_global_expected == graph_conn%adjncy(j)) .and. graph_conn%adjncy(j) .gt. 0) then
  !         print *, "TOPO neighbours @ global idx ", global_index_p, ": ", graph_conn%adjncy(graph_conn%xadj(i):graph_conn%xadj(i+1) - 1)
  !         print *, "Expected neighbours @ global idx ", global_index_p, ": ", adjncy_global_expected
  !         write (message, *) "ERROR: neighbours are wrong " // stage // "- partitioning."
  !         call stop_test(message)
  !      end if
  !   end do

  !   do j = 1, size(adjncy_global_expected)
  !      if (.not. any(graph_conn%adjncy == adjncy_global_expected(j)) .and. adjncy_global_expected(j) /= 0) then
  !         print *, "TOPO neighbours @ global idx ", global_index_p, ": ", graph_conn%adjncy(graph_conn%xadj(i):graph_conn%xadj(i+1) - 1)
  !         print *, "Expected neighbours @ global idx ", global_index_p, ": ", adjncy_global_expected
  !         write (message, *) "ERROR: neighbours are missing " // stage // "- partitioning."
  !         call stop_test(message)
  !      end if
  !   end do

  !   deallocate (adjncy_global_expected)

  ! end subroutine check_connectivity_cell_graphconn
  
  ! subroutine compute_expected_global_adjncy(i, adjncy_global_expected)

  !   integer, intent(in) :: i
  !   integer, dimension(:), intent(inout) :: adjncy_global_expected

  !   integer :: interior_ctr

  !   type(cell_locator) :: loc_p
  !   integer(ccs_int) :: idx_global, cidx_global

  !   adjncy_global_expected(:) = 0
  !   interior_ctr = 1

  !   call create_cell_locator(mesh, i, loc_p)
  !   call get_global_index(loc_p, idx_global)
  !   cidx_global = idx_global - 1 ! C-style indexing

  !   if ((modulo(cidx_global, 4) /= 0) .and. (interior_ctr <= size(adjncy_global_expected))) then
  !     ! NOT @ left boundary
  !     adjncy_global_expected(interior_ctr) = idx_global - 1
  !     interior_ctr = interior_ctr + 1
  !   end if

  !   if ((modulo(cidx_global, 4) /= (4 - 1)) .and. (interior_ctr <= size(adjncy_global_expected))) then
  !     ! NOT @ right boundary
  !     adjncy_global_expected(interior_ctr) = idx_global + 1
  !     interior_ctr = interior_ctr + 1
  !   end if

  !   if (((cidx_global / 4) /= 0) .and. (interior_ctr <= size(adjncy_global_expected))) then
  !     ! NOT @ bottom boundary
  !     adjncy_global_expected(interior_ctr) = idx_global - 4
  !     interior_ctr = interior_ctr + 1
  !   end if

  !   if (((cidx_global / 4) /= (4 - 1)) .and. (interior_ctr <= size(adjncy_global_expected))) then
  !     ! NOT @ top boundary
  !     adjncy_global_expected(interior_ctr) = idx_global + 4
  !     interior_ctr = interior_ctr + 1
  !   end if

  ! end subroutine

!  subroutine initialise_test
!
!    !integer :: ctr
!
!    ! Create a square mesh
!    print *, "Building mesh."
!    !mesh = build_square_mesh(par_env, 4, 1.0_ccs_real)
!    call build_square_topology(par_env, 4, mesh)
!
!
!    !! These need to be set to 1 for them to do nothing
!    !if (allocated(mesh%topo%adjwgt) .and. allocated(mesh%topo%vwgt)) then
!    !  mesh%topo%adjwgt = 1
!    !  mesh%topo%vwgt = 1
!    !else
!    !  call stop_test("Not allocated.")
!    !end if
!
!
!  end subroutine

  subroutine clean_test

    call clean_test_topo(mesh%topo)
    
  end subroutine clean_test
  subroutine clean_test_topo(topo)

    type(topology), intent(inout) :: topo

    call clean_test_graphconn(topo%graph_conn)

  end subroutine clean_test_topo
  subroutine clean_test_graphconn(graph_conn)

    type(graph_connectivity), intent(inout) :: graph_conn

    if (allocated(graph_conn%xadj)) then
      deallocate (graph_conn%xadj)
    end if

    if (allocated(graph_conn%adjncy)) then
      deallocate (graph_conn%adjncy)
    end if

    if (allocated(graph_conn%adjwgt)) then
      deallocate (graph_conn%adjwgt)
    end if

    if (allocated(graph_conn%vwgt)) then
      deallocate (graph_conn%vwgt)
    end if

    if (allocated(graph_conn%vtxdist)) then
      deallocate (graph_conn%vtxdist)
    end if

  end subroutine clean_test_graphconn
  
  !!!!! This could be the basis of testing the components of build_square_mesh/etc.

  !call get_local_num_cells(mesh, local_num_cells)

  ! --- read_topology() ---
  ! topo%global_num_cells = mesh%topo%global_num_cells
  !mesh%topo%global_num_faces = 40 ! Hardcoded for now
  !mesh%topo%max_faces = mesh%topo%num_nb(1)
  !allocate (mesh%topo%face_cell1(mesh%topo%global_num_faces))
  !allocate (mesh%topo%face_cell2(mesh%topo%global_num_faces))
  !allocate (mesh%topo%global_face_indices(mesh%topo%max_faces, mesh%topo%global_num_cells))

  ! --- read_topology() --- end

  ! --- compute_partitioner_input() ---
  !allocate (mesh%topo%vtxdist(par_env%num_procs + 1))
  !allocate (mesh%topo%global_partition(mesh%topo%global_num_cells))

  ! Hardcode vtxdist for now
  !mesh%topo%vtxdist = (/1, 5, 9, 13, 17/)

  ! <MISSING> set mesh%topo%global_partition array?
  ! FAKE partition array based on initial mesh decomposition
  !do i = 1, mesh%topo%global_num_cells
  !  if (any(mesh%topo%global_indices(1:local_num_cells) == i)) then
  !    mesh%topo%global_partition(i) = par_env%proc_id
  !  else
  !    mesh%topo%global_partition(i) = -1
  !  end if
  !end do

  ! ALTERNATIVE global partition
  !ctr = 1
  !do i = 1, mesh%topo%global_num_cells
  !  if (i == mesh%topo%vtxdist(ctr + 1)) then
  !    ctr = ctr + 1
  !  end if
  !  mesh%topo%global_partition(i) = (ctr - 1) ! Partitions/ranks are zero-indexed
  !end do

  ! select type(par_env)
  ! type is (parallel_environment_mpi)
  !   allocate(tmp_partition, source=mesh%topo%global_partition)
  !   write(message, *) "Initial partition: ", tmp_partition
  !   call dprint(message)
  !   call MPI_Allreduce(tmp_partition, mesh%topo%global_partition, mesh%topo%global_num_cells, &
  !           MPI_LONG, MPI_SUM, &
  !           par_env%comm, ierr)
  !   deallocate(tmp_partition)
  !   write(message, *) "Using partition: ", mesh%topo%global_partition
  !   call dprint(message)
  ! class default
  !   write(message, *) "ERROR: This test only works for MPI."
  !   call stop_test(message)
  ! end select

  ! topo%local_num_cells = local_num_cells
  !allocate (mesh%topo%xadj(local_num_cells + 1))

  ! <MISSING> allocate mesh%topo%adjncy

  !allocate (mesh%topo%local_partition(local_num_cells))
  ! mesh%topo%halo_num_cells = mesh%topo%halo_num_cells

  !select type (par_env)
  !type is (parallel_environment_mpi)

    !!  ! Also hardcode the adjncy arrays
  !  if (par_env%num_procs == 4) then

  !    if (par_env%proc_id == 0) then
  !      mesh%topo%adjncy = (/2, 5, 1, 3, 6, 2, 4, 7, 3, 8/)
  !    else if (par_env%proc_id == 1) then
  !      mesh%topo%adjncy = (/1, 6, 9, 2, 5, 7, 10, 3, 6, 8, 11, 4, 7, 12/)
  !    else if (par_env%proc_id == 2) then
  !      mesh%topo%adjncy = (/5, 10, 13, 6, 9, 11, 14, 7, 10, 12, 15, 8, 11, 16/)
  !    else
  !      mesh%topo%adjncy = (/9, 14, 10, 13, 15, 11, 14, 16, 12, 15/)
  !    end if

  !  else
  !    write (message, *) "Test must be run on 4 MPI ranks."
  !    call stop_test(message)
  !  end if

  !class default
  !  write (message, *) "ERROR: Unknown parallel environment."
  !  call stop_test(message)
  !end select

end program
