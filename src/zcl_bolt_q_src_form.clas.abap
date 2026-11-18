"! <p class="shorttext synchronized">Bolt with Fiori - source API: Smart Forms of this system</p>
"! Serves ZCE_BOLT_SRC_FORM for the Bolt app on another system (DEV/QA/PRD)
"! that reads this system's Smart Forms. Optional filters: PREFIXES eq 'Z,Y',
"! FORM_NAME (equality/ranges). $orderby FORM_NAME, $top/$skip and $count.
CLASS zcl_bolt_q_src_form DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_t_row TYPE STANDARD TABLE OF zce_bolt_src_form WITH EMPTY KEY.
ENDCLASS.



CLASS zcl_bolt_q_src_form IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA lt_all      TYPE ty_t_row.
    DATA lt_page     TYPE ty_t_row.
    DATA lv_prefixes TYPE string VALUE `Z,Y`.
    DATA lr_name     TYPE RANGE OF zce_bolt_src_form-form_name.

    TRY.
        DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).
        READ TABLE lt_ranges INTO DATA(ls_range) WITH KEY name = `PREFIXES`.
        IF sy-subrc = 0 AND ls_range-range IS NOT INITIAL.
          lv_prefixes = condense( CONV string( ls_range-range[ 1 ]-low ) ).
        ENDIF.
        READ TABLE lt_ranges INTO ls_range WITH KEY name = `FORM_NAME`.
        IF sy-subrc = 0.
          lr_name = CORRESPONDING #( ls_range-range ).
        ENDIF.
      CATCH cx_rap_query_filter_no_range.
        CLEAR lr_name.
    ENDTRY.

    LOOP AT zcl_bolt_source=>list_forms_local( lv_prefixes ) INTO DATA(ls_form).
      APPEND VALUE #( form_name      = ls_form-form_name
                      description    = ls_form-description
                      dev_package    = ls_form-dev_package
                      created_by     = ls_form-created_by
                      created_on     = ls_form-created_on
                      changed_by     = ls_form-changed_by
                      changed_on     = ls_form-changed_on
                      driver_program = ls_form-driver_program
                      output_types   = ls_form-output_types
                      prefixes       = lv_prefixes ) TO lt_all.
    ENDLOOP.
    IF lr_name IS NOT INITIAL.
      DELETE lt_all WHERE form_name NOT IN lr_name.
    ENDIF.
    SORT lt_all BY form_name.

    IF io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( lt_all ) ).
    ENDIF.
    IF io_request->is_data_requested( ) = abap_false.
      RETURN.
    ENDIF.

    DATA(lo_paging) = io_request->get_paging( ).
    DATA(lv_offset) = lo_paging->get_offset( ).
    DATA(lv_size)   = lo_paging->get_page_size( ).
    IF lv_size = if_rap_query_paging=>page_size_unlimited OR lv_size <= 0.
      lt_page = lt_all.
    ELSE.
      DATA(lv_lo) = lv_offset + 1.
      DATA(lv_hi) = lv_offset + lv_size.
      LOOP AT lt_all INTO DATA(ls_row) FROM lv_lo TO lv_hi.
        APPEND ls_row TO lt_page.
      ENDLOOP.
    ENDIF.
    io_response->set_data( lt_page ).
  ENDMETHOD.

ENDCLASS.
