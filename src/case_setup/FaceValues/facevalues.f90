!> @brief Program file for testing face-centred value functionality

program facevalues

    use kinds, only: accs_int, accs_real
    use parallel_types, only: parallel_environment
    use parallel, only: initialise_parallel_environment, &
                        cleanup_parallel_environment
    use types, only: face_data, vector_init_data, mesh
    use utils, only: set_global_size, initialise
    use mesh_utils, only: build_square_mesh, &
                          count_mesh_faces
    use vec, only: create_vector

    implicit none

    class(parallel_environment), allocatable, target :: par_env
    class(face_data), allocatable :: face_vals

    type(vector_init_data) :: vec_sizes
    type(mesh) :: square_mesh

    integer(accs_int) :: nfaces
    integer(accs_int) :: cps = 3 ! Cells per side of the mesh

    call initialise_parallel_environment(par_env)

    ! Create a square mesh
    square_mesh = build_square_mesh(cps, 1.0_accs_real, par_env)

    ! Count number of faces
    call count_mesh_faces(square_mesh, nfaces)

    write(*,'(a,i0,a,i0)') 'cps = ', cps, ' nfaces = ', nfaces

    call initialise(vec_sizes)
    call set_global_size(vec_sizes, nfaces, par_env)

    call create_vector(vec_sizes, face_vals%u%vec)    


    call cleanup_parallel_environment(par_env)

end program facevalues