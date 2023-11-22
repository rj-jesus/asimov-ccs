module tgv2d_core
#include "ccs_macros.inc"

  use petscvec
  use petscsys

  use case_config, only: num_steps, num_iters, dt, cps, domain_size, write_frequency, &
                         velocity_relax, pressure_relax, res_target, case_name, &
                         write_gradients, velocity_solver_method_name, velocity_solver_precon_name, &
                         pressure_solver_method_name, pressure_solver_precon_name, &
                         compute_bwidth, compute_partqual
  use constants, only: cell, face, ccsconfig, ccs_string_len, &
                       field_u, field_v, field_w, field_p, field_p_prime, field_mf, field_viscosity, &
                       field_density, cell_centred_central, cell_centred_upwind, face_centred
  use kinds, only: ccs_real, ccs_int
  use types, only: field, field_spec, upwind_field, central_field, face_field, ccs_mesh, &
                   vector_spec, ccs_vector, field_ptr, fluid, fluid_solver_selector
  use fields, only: create_field, set_field_config_file, set_field_n_boundaries, set_field_name, &
                    set_field_type, set_field_vector_properties, set_field_store_residuals, set_field_enable_cell_corrections
  use fortran_yaml_c_interface, only: parse
  use parallel, only: initialise_parallel_environment, &
                      cleanup_parallel_environment, timer, &
                      read_command_line_arguments, sync
  use parallel_types, only: parallel_environment
  use meshing, only: get_global_num_cells
  use mesh_utils, only: build_square_mesh, write_mesh
  use vec, only: set_vector_location
  use petsctypes, only: vector_petsc
  use pv_coupling, only: solve_nonlinear
  use utils, only: set_size, initialise, update, exit_print, calc_kinetic_energy, calc_enstrophy, &
                   add_field_to_outputlist, reset_outputlist_counter, get_field, set_field, &
                   get_fluid_solver_selector, set_fluid_solver_selector, &
                   allocate_fluid_fields
  use boundary_conditions, only: read_bc_config, allocate_bc_arrays
  use read_config, only: get_variables, get_boundary_count, get_store_residuals, get_enable_cell_corrections
  use timestepping, only: set_timestep, activate_timestepping, reset_timestepping
  use io_visualisation, only: write_solution, reset_io_visualisation
  use fv, only: update_gradient

  implicit none

  public :: run_tgv2d

contains

  subroutine run_tgv2d(par_env, shared_env, error_L2, error_Linf, input_mesh, input_dt, input_num_steps)
    class(parallel_environment), allocatable, target, intent(in) :: par_env !< The parallel environment
    class(parallel_environment), allocatable, target, intent(in) :: shared_env !< The parallel environment
    real(ccs_real), dimension(3), intent(out) :: error_L2 !< L2 norm of the error for the U, V and P fields respectively
    real(ccs_real), dimension(3), intent(out) :: error_Linf !< Linf norm of the error for the U, V and P fields respectively
    type(ccs_mesh), intent(inout), optional :: input_mesh !< mesh object to use, if not provided, the build_square_mesh is used
    real(ccs_real), intent(in), optional :: input_dt !< timestep, if not provided, the yaml config option is used
    integer(ccs_int), intent(in), optional :: input_num_steps !< number of timesteps, if not provided, the yaml config option is used

    character(len=:), allocatable :: input_path  ! Path to input directory
    character(len=:), allocatable :: case_path  ! Path to input directory with case name appended
    character(len=:), allocatable :: ccs_config_file ! Config file for CCS

    type(ccs_mesh) :: mesh
    type(vector_spec) :: vec_properties

    type(field_spec) :: field_properties
    class(field), allocatable, target :: u, v, w, p, p_prime, mf, viscosity, density

    type(field_ptr), allocatable :: output_list(:)

    integer(ccs_int) :: n_boundaries

    integer(ccs_int) :: it_start, it_end
    integer(ccs_int) :: irank ! MPI rank ID
    integer(ccs_int) :: isize ! Size of MPI world

    double precision :: start_time
    double precision :: init_time
    double precision :: end_time

    logical :: u_sol = .true.  ! Default equations to solve for LDC case
    logical :: v_sol = .true.
    logical :: w_sol = .false.
    logical :: p_sol = .true.

    logical :: store_residuals, enable_cell_corrections
    
    integer(ccs_int) :: t         ! Timestep counter

    type(fluid) :: flow_fields
    type(fluid_solver_selector) :: fluid_sol

    irank = par_env%proc_id
    isize = par_env%num_procs

    call read_command_line_arguments(par_env, cps, case_name=case_name, in_dir=input_path)

    if (allocated(input_path)) then
      case_path = input_path // "/" // case_name
    else
      case_path = case_name
    end if

    ccs_config_file = case_path // ccsconfig

    call timer(start_time)

    ! Read case name from configuration file
    call read_configuration(ccs_config_file)

    if (irank == par_env%root) print *, "Starting ", case_name, " case!"

    ! Create a square mesh

    if (present(input_mesh)) then
      mesh = input_mesh
    else
      if (irank == par_env%root) print *, "Building mesh"
      mesh = build_square_mesh(par_env, shared_env, cps, domain_size)
    end if

    if (present(input_dt)) then
      dt = input_dt
    end if

    if (present(input_num_steps)) then
      num_steps = input_num_steps
    end if

    ! set solver and preconditioner info
    velocity_solver_method_name = "gmres"
    velocity_solver_precon_name = "bjacobi"
    pressure_solver_method_name = "cg"
    pressure_solver_precon_name = "gamg"

    ! Set start and end iteration numbers (read from input file)
    it_start = 1
    it_end = num_iters

    ! Initialise fields
    if (irank == par_env%root) print *, "Initialise fields"

    ! Create and initialise field vectors
    call initialise(vec_properties)
    call get_boundary_count(ccs_config_file, n_boundaries)
    call get_store_residuals(ccs_config_file, store_residuals)
    call get_enable_cell_corrections(ccs_config_file, enable_cell_corrections)

    call set_vector_location(cell, vec_properties)
    call set_size(par_env, mesh, vec_properties)

    call set_field_config_file(ccs_config_file, field_properties)
    call set_field_n_boundaries(n_boundaries, field_properties)
    call set_field_store_residuals(store_residuals, field_properties)
    call set_field_enable_cell_corrections(enable_cell_corrections, field_properties)

    call set_field_vector_properties(vec_properties, field_properties)
    call set_field_type(cell_centred_central, field_properties)
    call set_field_name("u", field_properties)
    call create_field(field_properties, u)
    call set_field_name("v", field_properties)
    call create_field(field_properties, v)
    call set_field_name("w", field_properties)
    call create_field(field_properties, w)

    call set_field_type(cell_centred_central, field_properties)
    call set_field_name("p", field_properties)
    call create_field(field_properties, p)
    call set_field_name("p_prime", field_properties)
    call create_field(field_properties, p_prime)
    call set_field_name("viscosity", field_properties)
    call create_field(field_properties, viscosity)
    call set_field_name("density", field_properties)
    call create_field(field_properties, density)

    call set_vector_location(face, vec_properties)
    call set_size(par_env, mesh, vec_properties)
    call set_field_vector_properties(vec_properties, field_properties)
    call set_field_type(face_centred, field_properties)
    call set_field_name("mf", field_properties)
    call create_field(field_properties, mf)
   
    ! Add fields to output list
    call add_field_to_outputlist(u, "u", output_list)
    call add_field_to_outputlist(v, "v", output_list)
    call add_field_to_outputlist(w, "w", output_list)
    call add_field_to_outputlist(p, "p", output_list)

    ! Write gradients to solution file
    write_gradients = .true.

    call activate_timestepping()
    call set_timestep(dt)

    ! Initialise velocity field
    if (irank == par_env%root) print *, "Initialise velocity field"
    call initialise_flow(mesh, u, v, w, p, mf, viscosity, density)

    call calc_tgv2d_error(par_env, mesh, u, v, w, p, error_L2, error_Linf)
    call calc_kinetic_energy(par_env, mesh, u, v, w)
    call calc_enstrophy(par_env, mesh, u, v, w)

    ! Solve using SIMPLE algorithm
    if (irank == par_env%root) print *, "Start SIMPLE"

    ! Write out mesh to file
    call write_mesh(par_env, case_path, mesh)

    ! Print the run configuration
    if (irank == par_env%root) then
      call print_configuration(mesh)
    end if

    ! XXX: This should get incorporated as part of create_field subroutines
    call set_fluid_solver_selector(field_u, u_sol, fluid_sol)
    call set_fluid_solver_selector(field_v, v_sol, fluid_sol)
    call set_fluid_solver_selector(field_w, w_sol, fluid_sol)
    call set_fluid_solver_selector(field_p, p_sol, fluid_sol)
    call allocate_fluid_fields(8, flow_fields)
    
    call set_field(1, u, flow_fields)
    call set_field(2, v, flow_fields)
    call set_field(3, w, flow_fields)
    call set_field(4, p, flow_fields)
    call set_field(5, p_prime, flow_fields)
    call set_field(6, mf, flow_fields)
    call set_field(7, viscosity, flow_fields) 
    call set_field(8, density, flow_fields)  
    
    call timer(init_time)

    do t = 1, num_steps
      call solve_nonlinear(par_env, mesh, it_start, it_end, res_target, &
                           fluid_sol, flow_fields)
      call calc_tgv2d_error(par_env, mesh, u, v, w, p, error_L2, error_Linf)
      call calc_kinetic_energy(par_env, mesh, u, v, w)

      call calc_enstrophy(par_env, mesh, u, v, w)

      if ((t == 1) .or. (t == num_steps) .or. (mod(t, write_frequency) == 0)) then
        call write_solution(par_env, case_path, mesh, output_list, t, num_steps, dt)
      end if
    end do

    ! Clean-up
    deallocate (u)
    deallocate (v)
    deallocate (w)
    deallocate (p)
    deallocate (p_prime)
    deallocate (output_list)

    call reset_timestepping()
    call reset_outputlist_counter()
    call reset_io_visualisation()

    call timer(end_time)

    if (irank == par_env%root) then
      print *, "Init time: ", init_time - start_time
      print *, "Elapsed time: ", end_time - start_time
    end if

  end subroutine run_tgv2d

  ! Read YAML configuration file
  subroutine read_configuration(config_filename)

    use read_config, only: get_value, get_relaxation_factors

    character(len=*), intent(in) :: config_filename

    class(*), pointer :: config_file  !< Pointer to CCS config file
    character(:), allocatable :: error

    character(len=ccs_string_len), dimension(:), allocatable :: variable_names  ! variable names for BC reading

    config_file => parse(config_filename, error)
    if (allocated(error)) then
      call error_abort(trim(error))
    end if

    call get_variables(config_file, variable_names)

    call get_value(config_file, 'steps', num_steps)
    if (num_steps == huge(0)) then
      call error_abort("No value assigned to num_steps.")
    end if

    call get_value(config_file, 'iterations', num_iters)
    if (num_iters == huge(0)) then
      call error_abort("No value assigned to num_iters.")
    end if

    call get_value(config_file, 'dt', dt)
    if (dt == huge(0.0)) then
      call error_abort("No value assigned to dt.")
    end if

    if (cps == huge(0)) then ! cps was not set on the command line
      call get_value(config_file, 'cps', cps)
      if (cps == huge(0)) then
        call error_abort("No value assigned to cps.")
      end if
    end if

    call get_value(config_file, 'L', domain_size)
    if (domain_size == huge(0.0)) then
      call error_abort("No value assigned to domain_size.")
    end if

    call get_value(config_file, 'target_residual', res_target)
    if (res_target == huge(0.0)) then
      call error_abort("No value assigned to target residual.")
    end if

    call get_relaxation_factors(config_file, u_relax=velocity_relax, p_relax=pressure_relax)
    if (velocity_relax == huge(0.0) .and. pressure_relax == huge(0.0)) then
      call error_abort("No values assigned to velocity and pressure underrelaxation.")
    end if

    call get_value(config_file, 'compute_partqual', compute_partqual)
    call get_value(config_file, 'compute_bwidth', compute_bwidth)

  end subroutine

  ! Print test case configuration
  subroutine print_configuration(mesh)

    class(ccs_mesh), intent(in) :: mesh

    integer(ccs_int) :: global_num_cells

    call get_global_num_cells(mesh, global_num_cells)

    ! XXX: this should eventually be replaced by something nicely formatted that uses "write"
    print *, " "
    print *, "******************************************************************************"
    print *, "* Solving the ", case_name, " case"
    print *, "******************************************************************************"
    print *, " "
    print *, "******************************************************************************"
    print *, "* SIMULATION LENGTH"
    print *, "* Running for ", num_steps, "timesteps and ", num_iters, "iterations"
    write (*, '(1x,a,e10.3)') "* Time step size: ", dt
    print *, "******************************************************************************"
    print *, "* MESH SIZE"
    print *, "* Cells per side: ", cps
    write (*, '(1x,a,e10.3)') "* Domain size: ", domain_size
    print *, "Global number of cells is ", global_num_cells
    print *, "******************************************************************************"
    print *, "* RELAXATION FACTORS"
    write (*, '(1x,a,e10.3)') "* velocity: ", velocity_relax
    write (*, '(1x,a,e10.3)') "* pressure: ", pressure_relax
    print *, "******************************************************************************"

  end subroutine

  subroutine initialise_flow(mesh, u, v, w, p, mf, viscosity, density)

    use constants, only: insert_mode, ndim
    use types, only: vector_values, cell_locator, face_locator, neighbour_locator
    use meshing, only: create_cell_locator, get_global_index, count_neighbours, create_neighbour_locator, &
                       get_local_index, create_face_locator, get_local_index, get_face_normal, get_centre, &
                       get_local_num_cells
    use fv, only: calc_cell_coords
    use utils, only: clear_entries, set_mode, set_row, set_entry, set_values
    use vec, only: get_vector_data, restore_vector_data, create_vector_values

    ! Arguments
    class(ccs_mesh), intent(in) :: mesh
    class(field), intent(inout) :: u, v, w, p, mf, viscosity, density

    ! Local variables
    integer(ccs_int) :: n_local
    integer(ccs_int) :: n, count
    integer(ccs_int) :: index_p, global_index_p, index_f, index_nb
    real(ccs_real) :: u_val, v_val, w_val, p_val
    type(cell_locator) :: loc_p
    type(face_locator) :: loc_f
    type(neighbour_locator) :: loc_nb
    type(vector_values) :: u_vals, v_vals, w_vals, p_vals
    real(ccs_real), dimension(:), pointer :: mf_data, viscosity_data, density_data

    real(ccs_real), dimension(ndim) :: x_p, x_f
    real(ccs_real), dimension(ndim) :: face_normal

    integer(ccs_int) :: nnb
    integer(ccs_int) :: j

    ! Set alias
    call get_local_num_cells(mesh, n_local)

    call create_vector_values(n_local, u_vals)
    call create_vector_values(n_local, v_vals)
    call create_vector_values(n_local, w_vals)
    call create_vector_values(n_local, p_vals)
    call set_mode(insert_mode, u_vals)
    call set_mode(insert_mode, v_vals)
    call set_mode(insert_mode, w_vals)
    call set_mode(insert_mode, p_vals)

    ! Set initial values for velocity fields
    do index_p = 1, n_local
      call create_cell_locator(mesh, index_p, loc_p)
      call get_global_index(loc_p, global_index_p)

      call get_centre(loc_p, x_p)

      u_val = sin(x_p(1)) * cos(x_p(2))
      v_val = -cos(x_p(1)) * sin(x_p(2))
      w_val = 0.0_ccs_real
      p_val = 0.0_ccs_real !-(sin(2 * x_p(1)) + sin(2 * x_p(2))) * 0.01_ccs_real / 4.0_ccs_real

      call set_row(global_index_p, u_vals)
      call set_entry(u_val, u_vals)
      call set_row(global_index_p, v_vals)
      call set_entry(v_val, v_vals)
      call set_row(global_index_p, w_vals)
      call set_entry(w_val, w_vals)
      call set_row(global_index_p, p_vals)
      call set_entry(p_val, p_vals)
    end do

    call set_values(u_vals, u%values)
    call set_values(v_vals, v%values)
    call set_values(w_vals, w%values)
    call set_values(p_vals, p%values)

    deallocate (u_vals%global_indices)
    deallocate (v_vals%global_indices)
    deallocate (w_vals%global_indices)
    deallocate (p_vals%global_indices)
    deallocate (u_vals%values)
    deallocate (v_vals%values)
    deallocate (w_vals%values)
    deallocate (p_vals%values)

    call get_vector_data(mf%values, mf_data)

    count = 0
    n = 0

    ! Loop over local cells and faces
    do index_p = 1, n_local

      call create_cell_locator(mesh, index_p, loc_p)
      call count_neighbours(loc_p, nnb)
      do j = 1, nnb

        call create_neighbour_locator(loc_p, j, loc_nb)
        call get_local_index(loc_nb, index_nb)

        ! if neighbour index is greater than previous face index
        if (index_nb > index_p) then ! XXX: abstract this test

          call create_face_locator(mesh, index_p, j, loc_f)
          call get_local_index(loc_f, index_f)
          call get_face_normal(loc_f, face_normal)
          call get_centre(loc_f, x_f)

          ! compute initial value based on current face coordinates
          mf_data(index_f) = sin(x_f(1)) * cos(x_f(2)) * face_normal(1) &
                             - cos(x_f(1)) * sin(x_f(2)) * face_normal(2)
        end if

      end do
    end do

    call get_vector_data(viscosity%values, viscosity_data)
    viscosity_data(:) =  1.e-2_ccs_real
    call restore_vector_data(viscosity%values, viscosity_data)

    call get_vector_data(density%values, density_data)
    density_data(:) = 1.0_ccs_real
    call restore_vector_data(density%values, density_data)

    call restore_vector_data(mf%values, mf_data)

    call update(u%values)
    call update(v%values)
    call update(w%values)
    call update(p%values)
    call update(mf%values)
    call update(viscosity%values)
    call update(density%values)

  end subroutine initialise_flow

  subroutine calc_tgv2d_error(par_env, mesh, u, v, w, p, error_L2, error_Linf)

    use constants, only: ndim
    use types, only: cell_locator
    use utils, only: str

    use vec, only: get_vector_data, restore_vector_data

    use meshing, only: get_centre, create_cell_locator, get_local_num_cells

    use parallel, only: allreduce
    use parallel_types_mpi, only: parallel_environment_mpi
    use timestepping, only: get_current_time, get_current_step

    class(parallel_environment), intent(in) :: par_env !< The parallel environment
    type(ccs_mesh), intent(in) :: mesh
    class(field), intent(inout) :: u, v, w, p
    real(ccs_real), dimension(3), intent(out) :: error_L2
    real(ccs_real), dimension(3), intent(out) :: error_Linf

    real(ccs_real), dimension(3) :: error_L2_local
    real(ccs_real), dimension(3) :: error_Linf_local

    real(ccs_real) :: ft
    real(ccs_real) :: u_an, v_an, w_an, p_an
    real(ccs_real), dimension(:), pointer :: u_data, v_data, w_data, p_data

    real(ccs_real) :: mu, rho, nu

    logical, save :: first_time = .true.

    type(cell_locator) :: loc_p
    real(ccs_real), dimension(ndim) :: x_p
    integer(ccs_int) :: index_p, local_num_cells

    character(len=ccs_string_len) :: fmt
    real(ccs_real) :: time
    integer(ccs_int) :: step

    integer(ccs_int) :: global_num_cells

    integer :: io_unit

    integer :: ierr

    mu = 0.01_ccs_real ! XXX: currently hardcoded somewhere
    rho = 1.0_ccs_real ! XXX: implicitly 1 throughout
    nu = mu / rho

    error_Linf_local(:) = 0.0_ccs_real
    error_L2_local(:) = 0.0_ccs_real

    call get_vector_data(u%values, u_data)
    call get_vector_data(v%values, v_data)
    call get_vector_data(w%values, w_data)
    call get_vector_data(p%values, p_data)
    call get_current_time(time)
    call get_current_step(step)

    call get_local_num_cells(mesh, local_num_cells)
    do index_p = 1, local_num_cells

      call create_cell_locator(mesh, index_p, loc_p)
      call get_centre(loc_p, x_p)

      ! Compute analytical solution
      ft = exp(-2 * nu * time)
      ! u_an = cos(x_p(1)) * sin(x_p(2)) * ft
      ! v_an = -sin(x_p(1)) * cos(x_p(2)) * ft
      u_an = sin(x_p(1)) * cos(x_p(2)) * ft
      v_an = -cos(x_p(1)) * sin(x_p(2)) * ft
      w_an = 0.0_ccs_real
      p_an = +(rho / 4.0_ccs_real) * (cos(2 * x_p(1)) + cos(2 * x_p(2))) * (ft**2)

      error_L2_local(1) = error_L2_local(1) + (u_an - u_data(index_p))**2
      error_L2_local(2) = error_L2_local(2) + (v_an - v_data(index_p))**2
      !error_L2_local(3) = error_L2_local(3) + (w_an - w_data(index_p))**2
      error_L2_local(3) = error_L2_local(3) + (p_an - p_data(index_p))**2

      error_Linf_local(1) = max(error_Linf_local(1), abs(u_an - u_data(index_p)))
      error_Linf_local(2) = max(error_Linf_local(2), abs(v_an - v_data(index_p)))
      !error_Linf_local(3) = max(error_Linf_local(3), abs(w_an - w_data(index_p)))
      error_Linf_local(3) = max(error_Linf_local(3), abs(p_an - p_data(index_p)))

    end do
    call restore_vector_data(u%values, u_data)
    call restore_vector_data(v%values, v_data)
    call restore_vector_data(w%values, w_data)
    call restore_vector_data(p%values, p_data)

    select type (par_env)
    type is (parallel_environment_mpi)
      call MPI_AllReduce(error_L2_local, error_L2, size(error_L2), MPI_DOUBLE_PRECISION, MPI_SUM, par_env%comm, ierr)
      call MPI_AllReduce(error_Linf_local, error_Linf, size(error_Linf), MPI_DOUBLE_PRECISION, MPI_MAX, par_env%comm, ierr)
    class default
      call error_abort("ERROR: Unknown type")
    end select

    call get_global_num_cells(mesh, global_num_cells)
    error_L2(:) = sqrt(error_L2(:) / global_num_cells)

    if (par_env%proc_id == par_env%root) then
      if (first_time) then
        first_time = .false.
        open (newunit=io_unit, file="tgv2d-err.log", status="replace", form="formatted")
      else
        open (newunit=io_unit, file="tgv2d-err.log", status="old", form="formatted", position="append")
      end if
      fmt = '(I0,' // str(2 * size(error_L2)) // '(1x,e12.4))'
      write (io_unit, fmt) step, error_L2, error_Linf
      close (io_unit)
    end if

  end subroutine calc_tgv2d_error

end module tgv2d_core

