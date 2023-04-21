!v Module file timestepping_mod.f90
!
!  Provides the interface for timestepping methods.
module timestepping

  use kinds, only: ccs_real, ccs_int
  use types, only: field, ccs_mesh, ccs_vector, ccs_matrix, vector_spec

  implicit none

  private

  public :: apply_timestep
  public :: set_timestep
  public :: get_timestep
  public :: update_old_values
  public :: initialise_old_values
  public :: activate_timestepping
  public :: finalise_timestep

  interface
    !> Apply one timestep correction
    module subroutine apply_timestep(mesh, phi, diag, M, b)
      type(ccs_mesh), intent(in) :: mesh !< mesh object
      class(field), intent(inout) :: phi !< flow variable
      class(ccs_vector), intent(inout) :: diag !< preallocated vector with the same size as M diagonal
      class(ccs_matrix), intent(inout) :: M !< equation system
      class(ccs_vector), intent(inout) :: b !< rhs vector
    end subroutine

    !> Indicate a timestep has finished
    module subroutine finalise_timestep()
    end subroutine finalise_timestep

    !> Set timestep size
    module subroutine set_timestep(timestep)
      real(ccs_real), intent(in) :: timestep
    end subroutine

    !> Get timestep size
    module function get_timestep() result(timestep)
      real(ccs_real) :: timestep
    end function

    !> Place current field values into old field values
    module subroutine update_old_values(x)
      class(field), intent(inout) :: x
    end subroutine

    !v Enable timestepping
    !
    !  If this is not called at the start of a program,
    !  calls to apply_timestep will return without doing anything.
    module subroutine activate_timestepping()
    end subroutine

    !> Check whether timestepping is active
    module function timestepping_is_active() result(active)
      logical :: active
    end function

    !> Create vectors for storing one or more previous timesteps
    module subroutine initialise_old_values(vec_properties, x)
      type(vector_spec), intent(in) :: vec_properties
      class(field), intent(inout) :: x
    end subroutine

    !> Internal routine for creating vectors for storing one or more previous timesteps
    module subroutine initialise_old_values_generic(vec_properties, num_old_vals, x)
      type(vector_spec), intent(in) :: vec_properties
      integer(ccs_int), intent(in) :: num_old_vals
      class(field), intent(inout) :: x
    end subroutine

    !> Internal routine for placing current field values into old field values
    module subroutine update_old_values_generic(num_old_vals, x)
      integer(ccs_int), intent(in) :: num_old_vals
      class(field), intent(inout) :: x
    end subroutine

    !> Apply first order timestep correction
    module subroutine apply_timestep_first_order(mesh, phi, diag, M, b)
      type(ccs_mesh), intent(in) :: mesh !< mesh object
      class(field), intent(inout) :: phi !< flow variable
      class(ccs_vector), intent(inout) :: diag !< preallocated vector with the same size as M diagonal
      class(ccs_matrix), intent(inout) :: M !< equation system
      class(ccs_vector), intent(inout) :: b !< rhs vector
    end subroutine

    !> Apply second order timestep correction
    module subroutine apply_timestep_second_order(mesh, phi, diag, M, b)
      type(ccs_mesh), intent(in) :: mesh !< mesh object
      class(field), intent(inout) :: phi !< flow variable
      class(ccs_vector), intent(inout) :: diag !< preallocated vector with the same size as M diagonal
      class(ccs_matrix), intent(inout) :: M !< equation system
      class(ccs_vector), intent(inout) :: b !< rhs vector
    end subroutine
    
    !> Apply mixed order timestep correction (theta scheme)
    module subroutine apply_timestep_theta(mesh, theta, phi, diag, M, b)
      type(ccs_mesh), intent(in) :: mesh !< mesh object
      real(ccs_real), intent(in) :: theta !< timestepping scheme mixing factor
      class(field), intent(inout) :: phi !< flow variable
      class(ccs_vector), intent(inout) :: diag !< preallocated vector with the same size as M diagonal
      class(ccs_matrix), intent(inout) :: M !< equation system
      class(ccs_vector), intent(inout) :: b !< rhs vector
    end subroutine

  end interface

end module timestepping
