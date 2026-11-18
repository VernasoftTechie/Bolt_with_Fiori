"! <p class="shorttext synchronized">Bolt with Fiori - Smart Forms overview query (ZCE_BOLT_SMARTFORM)</p>
"! Smart Forms of the source system in filter SystemId (default system when
"! none is given), merged with ZBOLT_MIG so the screen can grey out a form
"! that is already in migration. Supports $search (form name/description),
"! $orderby, $top/$skip and $count. When the list cannot be read (system
"! down, destination wrong) one row FormName = '*ERROR*' carries the reason
"! in Message, so the screen can say what is wrong instead of showing nothing.
CLASS zcl_bolt_q_smartform DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_t_row TYPE STANDARD TABLE OF zce_bolt_smartform WITH EMPTY KEY.

    METHODS filter_value
      IMPORTING io_request     TYPE REF TO if_rap_query_request
                iv_name        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS build
      IMPORTING iv_system_id   TYPE string
      RETURNING VALUE(rt_rows) TYPE ty_t_row.
ENDCLASS.



CLASS zcl_bolt_q_smartform IMPLEMENTATION.

  METHOD filter_value.
    TRY.
        DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range.
        RETURN.
    ENDTRY.
    READ TABLE lt_ranges INTO DATA(ls_range) WITH KEY name = iv_name.
    IF sy-subrc = 0 AND ls_range-range IS NOT INITIAL.
      rv_value = condense( CONV string( ls_range-range[ 1 ]-low ) ).
    ENDIF.
  ENDMETHOD.


  METHOD build.
    DATA(ls_setup) = zcl_bolt_config=>get_setup( ).
    DATA(ls_system) = COND zbolt_system( WHEN iv_system_id IS NOT INITIAL
                                         THEN zcl_bolt_config=>get_system( CONV #( iv_system_id ) )
                                         ELSE zcl_bolt_config=>get_default_system( ) ).
    IF ls_system IS INITIAL.
      rt_rows = VALUE #( ( systemid = iv_system_id formname = '*ERROR*'
                           message  = |No source system { iv_system_id } is configured - add one in Configuration > SAP systems.| ) ).
      RETURN.
    ENDIF.

    TRY.
        DATA(lt_forms) = zcl_bolt_source=>list_forms( is_system   = ls_system
                                                      iv_prefixes = zcl_bolt_config=>prefixes( ls_setup ) ).
      CATCH zcx_bolt INTO DATA(lx_error).
        rt_rows = VALUE #( ( systemid = ls_system-system_id formname = '*ERROR*' message = lx_error->get_text( ) ) ).
        RETURN.
    ENDTRY.

    " Forms already in migration (from any system - a form name is one branch).
    SELECT form_name, mig_uuid, serial_no, status_label, push_status FROM zbolt_mig
      WHERE withdrawn = @space
      ORDER BY form_name
      INTO TABLE @DATA(lt_mig).

    LOOP AT lt_forms INTO DATA(ls_form).
      DATA(ls_row) = VALUE zce_bolt_smartform(
        systemid      = ls_system-system_id
        formname      = ls_form-form_name
        description   = ls_form-description
        devpackage    = ls_form-dev_package
        createdby     = ls_form-created_by
        createdon     = ls_form-created_on
        changedby     = ls_form-changed_by
        changedon     = ls_form-changed_on
        driverprogram = ls_form-driver_program
        outputtypes   = ls_form-output_types ).
      READ TABLE lt_mig INTO DATA(ls_mig) WITH KEY form_name = ls_form-form_name BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-inmigration     = abap_true.
        ls_row-migrationserial = ls_mig-serial_no.
        ls_row-miguuid         = ls_mig-mig_uuid.
        ls_row-migrationstatus = SWITCH #( ls_mig-push_status
                                   WHEN zcl_bolt_config=>gc_push-pending THEN `Sending to GitHub`
                                   WHEN zcl_bolt_config=>gc_push-failed  THEN `Sending failed - see Migration`
                                   ELSE COND #( WHEN ls_mig-status_label IS NOT INITIAL THEN ls_mig-status_label
                                                ELSE `Queued` ) ).
      ENDIF.
      APPEND ls_row TO rt_rows.
    ENDLOOP.
  ENDMETHOD.


  METHOD if_rap_query_provider~select.
    DATA(lt_all) = build( filter_value( io_request = io_request iv_name = `SYSTEMID` ) ).

    " $search: form name or description contains the text (CS ignores case)
    DATA(lv_search) = condense( io_request->get_search_expression( ) ).
    REPLACE ALL OCCURRENCES OF `"` IN lv_search WITH ``.
    IF lv_search IS NOT INITIAL.
      DELETE lt_all WHERE formname <> '*ERROR*' AND NOT ( formname CS lv_search OR description CS lv_search ).
    ENDIF.

    " $filter on the form name (equality / ranges); a function like contains()
    " cannot be expressed as ranges and is ignored - $search covers that.
    TRY.
        DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).
        READ TABLE lt_ranges INTO DATA(ls_name_range) WITH KEY name = `FORMNAME`.
        IF sy-subrc = 0.
          DATA lr_name TYPE RANGE OF zce_bolt_smartform-formname.
          lr_name = CORRESPONDING #( ls_name_range-range ).
          DELETE lt_all WHERE formname NOT IN lr_name AND formname <> '*ERROR*'.
        ENDIF.
        READ TABLE lt_ranges INTO DATA(ls_flag_range) WITH KEY name = `INMIGRATION`.
        IF sy-subrc = 0.
          DATA lr_flag TYPE RANGE OF zce_bolt_smartform-inmigration.
          lr_flag = CORRESPONDING #( ls_flag_range-range ).
          DELETE lt_all WHERE inmigration NOT IN lr_flag AND formname <> '*ERROR*'.
        ENDIF.
      CATCH cx_rap_query_filter_no_range.
        " keep everything
    ENDTRY.

    DATA(lt_sort) = io_request->get_sort_elements( ).
    DATA(lt_order) = VALUE abap_sortorder_tab( FOR ls_sort IN lt_sort
                                               ( name = ls_sort-element_name descending = ls_sort-descending ) ).
    IF lt_order IS INITIAL.
      lt_order = VALUE #( ( name = `FORMNAME` ) ).
    ENDIF.
    SORT lt_all BY (lt_order).

    IF io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( lt_all ) ).
    ENDIF.
    IF io_request->is_data_requested( ) = abap_false.
      RETURN.
    ENDIF.

    DATA lt_page TYPE ty_t_row.
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
