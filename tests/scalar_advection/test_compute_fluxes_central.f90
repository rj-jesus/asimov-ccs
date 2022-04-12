!> @brief Test that the flux matrix has been computed correctly
!
!> @description Compares the matrix calculated for flows in the +x and +y directions with
!> central and upwind differencing to the known matrix
program test_compute_fluxes

  use testing_lib
  use types, only: field, central_field
  use mesh_utils, only : build_square_mesh
  use fv, only: compute_fluxes, calc_cell_coords
  use utils, only : update, initialise, &
                set_size, pack_entries, set_values
  use vec, only : create_vector
  use mat, only : create_matrix, set_nnz
  use solver, only : axpy, norm
  use constants, only: add_mode, insert_mode
  use bc_constants

  implicit none

  type(ccs_mesh) :: mesh
  type(bc_config) :: bcs
  type(vector_spec) :: vec_properties
  class(field), allocatable :: scalar
  class(field), allocatable :: u, v
  integer(ccs_int), parameter :: cps = 5
  integer(ccs_int) :: direction, discretisation
  integer, parameter :: x_dir = 1, y_dir = 2
  integer, parameter :: central = -1

  call init()

  mesh = build_square_mesh(par_env, cps, 1.0_ccs_real)

  bcs%region(1) = bc_region_left
  bcs%region(2) = bc_region_right
  bcs%region(3) = bc_region_top
  bcs%region(4) = bc_region_bottom
  bcs%bc_type(:) = bc_type_dirichlet
  bcs%endpoints(:,:) = 1.0_ccs_real
    
  do direction = x_dir, y_dir
    discretisation = central
      
    if (discretisation == central) then
      allocate(central_field :: scalar)
      allocate(central_field :: u)
      allocate(central_field :: v)
    else
      write(message, *) 'Invalid discretisation type selected'
      call stop_test(message)
    end if

    call initialise(vec_properties)
    call set_size(par_env, mesh, vec_properties)
    call create_vector(vec_properties, scalar%values)
    call create_vector(vec_properties, u%values)
    call create_vector(vec_properties, v%values)

    call set_velocity_fields(mesh, direction, u, v)
    call run_compute_fluxes_test(scalar, u, v, bcs, mesh, cps, direction, discretisation)
    call tidy_velocity_fields(scalar, u, v)
  end do

  call fin()

  contains

  !> @brief Sets the velocity field in the desired direction and discretisation
  !
  !> @param[in] mesh - The mesh structure
  !> @param[in] direction - Integer indicating the direction of the velocity field
  !> @param[out] u, v     - The velocity fields in x and y directions
  subroutine set_velocity_fields(mesh, direction, u, v)
    use meshing, only: set_cell_location, get_global_index
    class(ccs_mesh), intent(in) :: mesh
    integer(ccs_int), intent(in) :: direction
    class(field), intent(inout) :: u, v
    type(cell_locator) :: self_loc
    type(vector_values) :: u_vals, v_vals
    integer(ccs_int) :: local_idx, self_idx
    real(ccs_real) :: u_val, v_val

    u_vals%mode = insert_mode
    v_vals%mode = insert_mode
    
    associate(n_local => mesh%nlocal)
      allocate(u_vals%idx(n_local))
      allocate(v_vals%idx(n_local))
      allocate(u_vals%val(n_local))
      allocate(v_vals%val(n_local))
      
      ! Set IC velocity fields
      do local_idx = 1, n_local
        call set_cell_location(mesh, local_idx, self_loc)
        call get_global_index(self_loc, self_idx)

        if (direction == x_dir) then
          u_val = 1.0_ccs_real
          v_val = 0.0_ccs_real
        else if (direction == y_dir) then
          u_val = 0.0_ccs_real
          v_val = 1.0_ccs_real
        end if

        u_val = 0.0_ccs_real
        v_val = 0.0_ccs_real
        
        call pack_entries(local_idx, self_idx, u_val, u_vals)
        call pack_entries(local_idx, self_idx, v_val, v_vals)
      end do
    end associate
    call set_values(u_vals, u%values)
    call set_values(v_vals, v%values)

    call update(u%values)
    call update(v%values)
    
    deallocate(u_vals%idx, v_vals%idx, u_vals%val, v_vals%val)
  end subroutine set_velocity_fields

  !> @brief Deallocates the velocity fields
  !
  !> @param[in] scalar - The scalar field structure
  !> @param[in] u, v   - The velocity fields to deallocate
  subroutine tidy_velocity_fields(scalar, u, v)
    class(field), allocatable :: scalar
    class(field), allocatable :: u, v

    deallocate(scalar)
    deallocate(u)
    deallocate(v)
  end subroutine tidy_velocity_fields

  !> @brief Compares the matrix computed for a given velocity field and discretisation to the known solution
  !
  !> @param[in] scalar         - The scalar field structure
  !> @param[in] u, v           - The velocity field structures
  !> @param[in] bcs            - The BC structure
  !> @param[in] mesh      - The mesh structure
  !> @param[in] cps            - The number of cells per side in the (square) mesh 
  !> @param[in] flow_direction - Integer indicating the direction of the flow 
  !> @param[in] discretisation - Integer indicating the discretisation scheme being tested 
  subroutine run_compute_fluxes_test(scalar, u, v, bcs, mesh, cps, flow_direction, discretisation)
    class(field), intent(in) :: scalar
    class(field), intent(in) :: u, v
    class(bc_config), intent(in) :: bcs
    type(ccs_mesh), intent(in) :: mesh
    integer(ccs_int), intent(in) :: cps
    integer(ccs_int), intent(in) :: flow_direction
    integer(ccs_int), intent(in) :: discretisation

    class(ccs_matrix), allocatable :: M, M_exact
    class(ccs_vector), allocatable :: b, b_exact
    type(vector_spec) :: vec_properties
    type(matrix_spec) :: mat_properties
    real(ccs_real) :: error
    
    call initialise(mat_properties)
    call initialise(vec_properties)
    call set_size(par_env, mesh, mat_properties)
    call set_size(par_env, mesh, vec_properties)
    call set_nnz(5, mat_properties)
    call create_matrix(mat_properties, M)
    call create_vector(vec_properties, b)
    call create_matrix(mat_properties, M_exact)
    call create_vector(vec_properties, b_exact)

    call compute_fluxes(scalar, u, v, mesh, bcs, cps, M, b)

    call update(M)
    call update(b)

    call compute_exact_matrix(mesh, flow_direction, discretisation, cps, M_exact, b_exact)

    call update(M_exact)
    call update(b_exact)

    call axpy(-1.0_ccs_real, M_exact, M)
    error = norm(M, 1)

    if (error .ge. eps) then
      write(message, *) 'FAIL: matrix difference norm too large ', error
      call stop_test(message)
    end if
    
    call axpy(-1.0_ccs_real, b_exact, b)
    error = norm(b, 2)

    if (error .ge. eps) then
      write(message, *) 'FAIL: vector difference norm too large ', error
      call stop_test(message)
    end if

    deallocate(M)
    deallocate(b)
    deallocate(M_exact)
    deallocate(b_exact)
  end subroutine run_compute_fluxes_test

  !> @brief Computes the known flux matrix for the given flow and discretisation
  !
  !> @param[in] mesh      - The (square) mesh
  !> @param[in] flow           - Integer indicating flow direction
  !> @param[in] discretisation - Integer indicating the discretisation scheme being used
  !> @param[in] cps            - Number of cells per side in mesh
  !> @param[out] M             - The resulting matrix
  !> @param[out] b             - The resulting RHS vector
  subroutine compute_exact_matrix(mesh, flow, discretisation, cps, M, b)

    use vec, only : zero_vector
    
    class(ccs_mesh), intent(in) :: mesh
    integer(ccs_int), intent(in) :: flow
    integer(ccs_int), intent(in) :: discretisation
    integer(ccs_int), intent(in) :: cps
    class(ccs_matrix), intent(inout) :: M
    class(ccs_vector), intent(inout) :: b

    ! type(vector_spec) :: vec_properties
    type(vector_values) :: vec_coeffs
    real(ccs_real) :: diff_coeff, adv_coeff
    integer(ccs_int) :: i, ii
    integer(ccs_int) :: row, col
    integer(ccs_int) :: vec_counter

    call initialise(vec_properties)
    call set_size(par_env, mesh, vec_properties)

    ! call compute_exact_advection_matrix(mesh, cps, flow, discretisation, M)
    ! call compute_exact_diffusion_matrix(mesh, cps, M)
    
    ! Now do the RHS
    vec_coeffs%setter_mode = add_mode
    call zero_vector(b)
    
    ! Advection first
    allocate(vec_coeffs%idx(2*mesh%nglobal/cps))
    allocate(vec_coeffs%val(2*mesh%nglobal/cps))

    vec_counter = 1
    if (discretisation == central) then
      adv_coeff = -1.0_ccs_real
    else
      adv_coeff = 0.0_ccs_real
    endif
    adv_coeff = 0.0_ccs_real

    if (par_env%proc_id == 0) then
      if (flow == x_dir) then
        do i = 1, cps
          call pack_entries(vec_counter, (i-1)*cps + 1, adv_coeff, vec_coeffs) 
          vec_counter = vec_counter + 1
          call pack_entries(vec_counter, i*cps, adv_coeff, vec_coeffs) 
          vec_counter = vec_counter + 1
        end do
      else
        do i = 1, cps
          call pack_entries(vec_counter, i, adv_coeff, vec_coeffs) 
          vec_counter = vec_counter + 1
          call pack_entries(vec_counter, mesh%nlocal - i + 1, adv_coeff, vec_coeffs) 
          vec_counter = vec_counter + 1
        end do
      end if
    else
      vec_coeffs%idx(:) = -1
      vec_coeffs%val(:) = 0.0_ccs_real
    endif
    call set_values(vec_coeffs, b)
    
    deallocate(vec_coeffs%idx)
    deallocate(vec_coeffs%val)

    ! ! And now diffusion
    ! allocate(vec_coeffs%idx(4*cps))
    ! allocate(vec_coeffs%val(4*cps))

    ! vec_counter = 1
    ! diff_coeff = 0.0_ccs_real !0.01_ccs_real
    ! if (par_env%proc_id == 0) then
    !   do i = 1, mesh%nglobal
    !     call calc_cell_coords(i, cps, row, col)
    !     if (row == 1 .or. row == cps) then
    !       call pack_entries(vec_counter, i, diff_coeff, vec_coeffs) 
    !       vec_counter = vec_counter + 1
    !     end if
    !     if (col == 1 .or. col == cps) then
    !       call pack_entries(vec_counter, i, diff_coeff, vec_coeffs) 
    !       vec_counter = vec_counter + 1
    !     end if
    !   end do
    ! else
    !   vec_coeffs%idx(:) = -1
    !   vec_coeffs%val(:) = 0.0_ccs_real
    ! end if
    ! call set_values(vec_coeffs, b)

    ! deallocate(vec_coeffs%idx)
    ! deallocate(vec_coeffs%val)
    
  end subroutine compute_exact_matrix

  !> @brief Computes the known diffusion flux matrix for the given flow and discretisation
  !
  !> @param[in] mesh      - The (square) mesh
  !> @param[in] cps            - Number of cells per side in mesh
  !> @param[out] M             - The resulting matrix
  subroutine compute_exact_diffusion_matrix(mesh, cps, M)

    class(ccs_mesh), intent(in) :: mesh
    integer(ccs_int), intent(in) :: cps
    class(ccs_matrix), intent(inout) :: M

    type(matrix_values) :: mat_coeffs

    real(ccs_real) :: diff_coeff
    
    integer(ccs_int) :: i, ii
    integer(ccs_int) :: j
    integer(ccs_int) :: mat_counter

    allocate(mat_coeffs%row_indices(1))
    allocate(mat_coeffs%col_indices(5))
    allocate(mat_coeffs%values(5))
    mat_coeffs%setter_mode = add_mode

    j = cps
    
    diff_coeff = -0.01_ccs_real
    ! Diffusion coefficients
    do i = 1, mesh%nlocal
      mat_counter = 1

      ii = mesh%idx_global(i)
      call pack_entries(1, mat_counter, ii, ii, -4*diff_coeff, mat_coeffs)
      mat_counter = mat_counter + 1

      if (ii - 1 > 0 .and. mod(ii, cps) .ne. 1) then
        call pack_entries(1, mat_counter, ii, ii-1, diff_coeff, mat_coeffs)
        mat_counter = mat_counter + 1
      end if
      if (ii - cps > 0) then
        call pack_entries(1, mat_counter, ii, ii-cps, diff_coeff, mat_coeffs)
        mat_counter = mat_counter + 1
      end if

      if (ii + 1 .le. mesh%nglobal .and. mod(ii, cps) .ne. 0) then
        call pack_entries(1, mat_counter, ii, ii+1, diff_coeff, mat_coeffs)
        mat_counter = mat_counter + 1
      end if
      if (ii + cps .le. mesh%nglobal) then
        call pack_entries(1, mat_counter, ii, ii+cps, diff_coeff, mat_coeffs)
        mat_counter = mat_counter + 1
      end if

      if (mat_counter < 6) then
        do j = mat_counter, cps
          call pack_entries(1, mat_counter, ii, -1, 0.0_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        end do
      end if

      call set_values(mat_coeffs, M)
    end do
    
    deallocate(mat_coeffs%row_indices)
    deallocate(mat_coeffs%col_indices)
    deallocate(mat_coeffs%values)
    
  end subroutine compute_exact_diffusion_matrix

  !> @brief Computes the known advection flux matrix for the given flow and discretisation
  !
  !> @param[in] mesh      - The (square) mesh
  !> @param[in] cps            - Number of cells per side in mesh
  !> @param[out] M             - The resulting matrix
  subroutine compute_exact_advection_matrix(mesh, cps, flow, discretisation, M)

    class(ccs_mesh), intent(in) :: mesh
    integer(ccs_int), intent(in) :: cps
    integer(ccs_int), intent(in) :: flow
    integer(ccs_int), intent(in) :: discretisation
    class(ccs_matrix), intent(inout) :: M

    type(matrix_values) :: mat_coeffs

    integer(ccs_int) :: i, ii
    integer(ccs_int) :: mat_counter

    mat_coeffs%setter_mode = add_mode
    allocate(mat_coeffs%row_indices(1))
    allocate(mat_coeffs%col_indices(2))
    allocate(mat_coeffs%values(2))

    ! Advection coefficients
    
    if (flow == x_dir) then
      ! CDS and flow along +x direction
      do i = 1, mesh%nlocal
        mat_counter = 1
        ii = mesh%idx_global(i)
        if (mod(ii, cps) == 1) then
          call pack_entries(1, mat_counter, ii, ii, -0.3_ccs_real, mat_coeffs) ! Make this more flexible so that the coeffs depend on cps
          mat_counter = mat_counter + 1
          call pack_entries(1, mat_counter, ii, ii+1, 0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        else if (mod(ii, cps) == 0) then
          call pack_entries(1, mat_counter, ii, ii, -0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
          call pack_entries(1, mat_counter, ii, ii-1, -0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        else
          call pack_entries(1, mat_counter, ii, ii+1, 0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
          call pack_entries(1, mat_counter, ii, ii-1, -0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        end if
        call set_values(mat_coeffs, M)
      end do
    else if (flow == y_dir) then
      ! CDS and flow along +y direction
      do i = 1, mesh%nlocal
        mat_counter = 1
        ii = mesh%idx_global(i)
        if (ii .le. cps) then
          call pack_entries(1, mat_counter, ii, ii, -0.3_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        else if (ii > mesh%nglobal - cps) then
          call pack_entries(1, mat_counter, ii, ii, -0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        end if

        if (ii + cps .le. mesh%nglobal) then
          call pack_entries(1, mat_counter, ii, ii+cps, 0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        end if
        if (ii - cps > 0) then
          call pack_entries(1, mat_counter, ii, ii-cps, -0.1_ccs_real, mat_coeffs)
          mat_counter = mat_counter + 1
        end if
        call set_values(mat_coeffs, M)
      end do
    end if

    deallocate(mat_coeffs%col_indices)
    deallocate(mat_coeffs%values)
  end subroutine compute_exact_advection_matrix
  
end program test_compute_fluxes