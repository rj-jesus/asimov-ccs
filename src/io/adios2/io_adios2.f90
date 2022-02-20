!> @brief Submodule file io_adios2.smod
!
!> @build mpi adios2
!
!> @details Implementation (using MPI and ADIOS@) of parallel 
!!          IO functionality
submodule (io) io_adios2

  use adios2
  use adios2_types, only: adios2_env, adios2_io_process
  use parallel_types_mpi, only: parallel_environment_mpi

  implicit none

  contains

  !> @brief Read a scalar integer from file
  !
  !> param[in]  io_proc   : ADIOS2 IO process used for reading
  !> param[in]  attr_name : Name of scalar integer to read
  !> param[out] attr      : Value of scalar integer
  module subroutine read_scalar_integer(io_proc, attr_name, attr)
    class(io_process), intent(in) :: io_proc
    character (len=*), intent(in) :: attr_name
    integer(accs_int), intent(out) :: attr

    type(adios2_attribute) :: adios2_attr

    integer(accs_int) :: ierr

    select type(io_proc)
      type is(adios2_io_process)

        call adios2_inquire_attribute(adios2_attr, io_proc%io_task, attr_name, ierr)

        if (adios2_attr%type == adios2_type_integer8) then
          print*,"===> IO Error: trying to read an 8-byte INTEGER into a 4-byte INTEGER"
          print*,"===> Expected attribute type adios2_type_integer8."
          stop 1
        end if

        call adios2_attribute_data(attr, adios2_attr, ierr)

        class default
        print*,"Unknown IO process handler type"

      end select

  end subroutine

  !> @brief Read a scalar long integer from file
  !
  !> param[in]  io_proc   : ADIOS2 IO process used for reading
  !> param[in]  attr_name : Name of scalar longinteger to read
  !> param[out] attr      : Value of scalar long integer
  module subroutine read_scalar_long(io_proc, attr_name, attr)
    class(io_process), intent(in) :: io_proc
    character (len=*), intent(in) :: attr_name
    integer(kind=8), intent(out) :: attr

    type(adios2_attribute) :: adios2_attr

    integer(accs_int) :: ierr

    select type(io_proc)
      type is(adios2_io_process)

        call adios2_inquire_attribute(adios2_attr, io_proc%io_task, attr_name, ierr)

        if (adios2_attr%type == adios2_type_integer4) then
          print*,"===> IO Error: trying to read a 4-byte INTEGER into an 8-byte INTEGER"
          print*,"===> Expected attribute type adios2_type_integer4."
          stop 1
        end if

        call adios2_attribute_data(attr, adios2_attr, ierr)

        class default
        print*,"Unknown IO process handler type"

      end select

  end subroutine

  !> @brief Read a scalar real from file
  !
  !> param[in]  io_proc   : ADIOS2 IO process used for reading
  !> param[in]  attr_name : Name of scalar real to read
  !> param[out] attr      : Value of scalar real
  module subroutine read_scalar_real(io_proc, attr_name, attr)
    class(io_process), intent(in) :: io_proc
    character (len=*), intent(in) :: attr_name
    real, intent(out) :: attr

    type(adios2_attribute) :: adios2_attr

    integer(accs_int) :: ierr

    select type(io_proc)
      type is(adios2_io_process)

        call adios2_inquire_attribute(adios2_attr, io_proc%io_task, attr_name, ierr)
        if (adios2_attr%type == adios2_type_dp) then
          print*,"===> IO Error: trying to read a DOUBLE PRECISION REAL into a REAL"
          print*,"===> Expected attribute type adios2_type_real."
          stop 1
        end if
        call adios2_attribute_data(attr, adios2_attr, ierr)

      class default
        print*,"Unknown IO process handler type"

      end select

    end subroutine

  !> @brief Read a scalar double precision real from file
  !
  !> param[in]  io_proc   : ADIOS2 IO process used for reading
  !> param[in]  attr_name : Name of scalar double precision real to read
  !> param[out] attr      : Value of scalar double precision real
    module subroutine read_scalar_dp(io_proc, attr_name, attr)
      class(io_process), intent(in) :: io_proc
      character (len=*), intent(in) :: attr_name
      double precision, intent(out) :: attr
  
      type(adios2_attribute) :: adios2_attr
  
      integer(accs_int) :: ierr
  
      select type(io_proc)
        type is(adios2_io_process)
  
          call adios2_inquire_attribute(adios2_attr, io_proc%io_task, attr_name, ierr)
          if (adios2_attr%type == adios2_type_dp) then
            print*,"===> IO Error: trying to read a DOUBLE PRECISION REAL into a REAL"
            print*,"===> Expected attribute type adios2_type_dp."
            stop 
          end if
          call adios2_attribute_data(attr, adios2_attr, ierr)
  
        class default
          print*,"Unknown IO process handler type"
  
        end select
  
      end subroutine
  

    !> @brief Read a 1D integer array from file
    !
    !> @todo Check if the "mode" can be read from the configuration file
    !
    !> param[in]    io_proc  : ADIOS2 IO process used for reading
    !> param[in]    var_name : Name of integer array to read
    !> param[in]    start    : What global index to start reading from
    !> param[in]    count    : How many array element to read
    !> param[input] var      : The 1D integer array
    module subroutine read_array_integer1D(io_proc, var_name, start, count, var)
      class(io_process), intent(in) :: io_proc
      character (len=*), intent(in) :: var_name
      integer(kind=8), dimension(1), intent(in) :: start
      integer(kind=8), dimension(1), intent(in) :: count
      integer, dimension(:), intent(inout) :: var

      type(adios2_variable):: adios2_var
      integer(accs_int) :: ierr

      select type(io_proc)
        type is(adios2_io_process)

          call adios2_inquire_variable(adios2_var, io_proc%io_task, var_name, ierr)
          call adios2_set_selection(adios2_var, 1, start, count, ierr)
          call adios2_get(io_proc%engine, adios2_var, var, adios2_mode_sync, ierr)

      class default
        print*,"Unknown IO process handler type"

      end select

    end subroutine

    !> @brief Read a 2D integer array from file
    !
    !> @todo Check if the "mode" can be read from the configuration file
    !
    !> param[in]    io_proc  : ADIOS2 IO process used for reading
    !> param[in]    var_name : Name of integer array to read
    !> param[in]    start    : What global index to start reading from
    !> param[in]    count    : How many array element to read
    !> param[input] var      : The 2D integer array
    module subroutine read_array_integer2D(io_proc, var_name, start, count, var)
      class(io_process), intent(in) :: io_proc
      character (len=*), intent(in) :: var_name
      integer(kind=8), dimension(2), intent(in) :: start
      integer(kind=8), dimension(2), intent(in) :: count
      integer, dimension(:,:), intent(inout) :: var

      type(adios2_variable):: adios2_var
      integer(accs_int) :: ierr

      select type(io_proc)
        type is(adios2_io_process)

          call adios2_inquire_variable(adios2_var, io_proc%io_task, var_name, ierr)
          call adios2_set_selection(adios2_var, 2, start, count, ierr)
          call adios2_get(io_proc%engine, adios2_var, var, adios2_mode_sync, ierr)

      class default
        print*,"Unknown IO process handler type"

      end select

    end subroutine

    !> @brief Read a 1D real array from file
    !
    !> @todo Check if the "mode" can be read from the configuration file
    !
    !> param[in]    io_proc  : ADIOS2 IO process used for reading
    !> param[in]    var_name : Name of real array to read
    !> param[in]    start    : What global index to start reading from
    !> param[in]    count    : How many array element to read
    !> param[input] var      : The 1D real array
    module subroutine read_array_real1D(io_proc, var_name, start, count, var)
      class(io_process), intent(in) :: io_proc
      character (len=*), intent(in) :: var_name
      integer(kind=8), dimension(1), intent(in) :: start
      integer(kind=8), dimension(1), intent(in) :: count
      real, dimension(:), intent(inout) :: var

      type(adios2_variable):: adios2_var
      integer(accs_int) :: ierr

      select type(io_proc)
        type is(adios2_io_process)

          call adios2_inquire_variable(adios2_var, io_proc%io_task, var_name, ierr)
          call adios2_set_selection(adios2_var, 1, start, count, ierr)
          call adios2_get(io_proc%engine, adios2_var, var, adios2_mode_sync, ierr)

      class default
        print*,"Unknown IO process handler type"

      end select

    end subroutine

    !> @brief Read a 2D real array from file
    !
    !> @todo Check if the "mode" can be read from the configuration file
    !
    !> param[in]    io_proc  : ADIOS2 IO process used for reading
    !> param[in]    var_name : Name of real array to read
    !> param[in]    start    : What global index to start reading from
    !> param[in]    count    : How many array element to read
    !> param[input] var      : The 2D real array
    module subroutine read_array_real2D(io_proc, var_name, start, count, var)
      class(io_process), intent(in) :: io_proc
      character (len=*), intent(in) :: var_name
      integer(kind=8), dimension(2), intent(in) :: start
      integer(kind=8), dimension(2), intent(in) :: count
      real, dimension(:,:), intent(inout) :: var

      type(adios2_variable):: adios2_var
      integer(accs_int) :: ierr

      select type(io_proc)
        type is(adios2_io_process)

          call adios2_inquire_variable(adios2_var, io_proc%io_task, var_name, ierr)
          call adios2_set_selection(adios2_var, 2, start, count, ierr)
          call adios2_get(io_proc%engine, adios2_var, var, adios2_mode_sync, ierr)

      class default
        print*,"Unknown IO process handler type"

      end select

    end subroutine


  end submodule