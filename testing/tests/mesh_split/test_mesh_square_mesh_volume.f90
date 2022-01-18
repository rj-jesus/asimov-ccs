!> @brief Test the square mesh generator creates a correctly-sized mesh.
!
!> @description A "square" domain of side L should result in a mesh of volume L^d, this can be
!> verified by summing the volumes of all cells.
program test_mesh_square_mesh_volume

  use testing_lib
  use mesh_utils, only : build_square_mesh
  
  type(mesh) :: square_mesh

  integer(accs_int) :: n
  real(accs_real) :: l
  real(accs_real) :: vol
  real(accs_real) :: vol_global
  real(accs_real) :: expected_vol

  integer(accs_int) :: i
  
  call init()
  
  do n = 1, 100
    l = parallel_random(par_env)
    square_mesh = build_square_mesh(n, l, par_env)
    expected_vol = l**2 ! XXX: Currently the square mesh is hard-coded 2D...

    vol = 0_accs_real
    do i = 1, square_mesh%nlocal
      vol = vol + square_mesh%vol
    end do
    
    select type(par_env)
    type is(parallel_environment_mpi)
      call MPI_Allreduce(vol, vol_global, 1, real_type, MPI_SUM, par_env%comm, ierr)
    class default
      write (message,*) "ERROR: Unknown parallel environment!"
      call stop_test(message)
    end select

    ! XXX: This would be a good candidate for a testing library
    if (abs(expected_vol - vol_global) > 1.0e-8) then
      print *, square_mesh%h, l/n !TODO: not sure if this should be put inside message
      write (message,*) "FAIL: expected ", expected_vol, " got ", vol_global
      call stop_test(message)
    end if

  end do
  
  call fin()

end program test_mesh_square_mesh_volume