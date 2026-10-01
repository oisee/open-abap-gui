CLASS ltcl_ex_69 DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS retains_group_values FOR TESTING.
ENDCLASS.

CLASS ltcl_ex_69 IMPLEMENTATION.

  METHOD retains_group_values.
* P_REQUIRED is filled: an empty OBLIGATORY field stops the screen before
* AT SELECTION-SCREEN, as on a system, and the group would not be saved
    DATA(lo_report) = NEW zcl_gg_ex_069( ).
    DATA(ls_saved) = zcl_gg_host=>run(
      io_report = lo_report
      it_input  = VALUE #( ( name = 'P_ENABLE' value = 'X' )
                          ( name = 'P_GROUP_A' value = 'a' )
                          ( name = 'P_GROUP_B' value = 'b' )
                          ( name = 'P_REQUIRED' value = 'r' ) ) ).
    cl_abap_unit_assert=>assert_false( ls_saved-selection_active ).
    DATA(ls_disabled) = zcl_gg_host=>run(
      io_report = lo_report
      it_input  = VALUE #( ( name = 'P_ENABLE' value = '' )
                          ( name = 'P_GROUP_A' value = '' )
                          ( name = 'P_GROUP_B' value = '' )
                          ( name = 'P_REQUIRED' value = 'r' ) ) ).
    cl_abap_unit_assert=>assert_false( ls_disabled-states[ name = 'P_GROUP_A' ]-enabled ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_disabled-values[ name = 'P_GROUP_A' ]-value
      exp = 'a' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_disabled-values[ name = 'P_GROUP_B' ]-value
      exp = 'b' ).
  ENDMETHOD.
ENDCLASS.
