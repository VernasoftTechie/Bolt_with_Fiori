"! <p class="shorttext synchronized">Bolt - Smart Forms tab query (ZAB_CDS_CE_BOLT_FORM)</p>
"! Every custom Smart Form of THIS system (ZCL_AB_BOLT_FORM_CATALOG) merged
"! with the latest migration run of each form:
"!   NONE      never selected                       -> selectable
"!   ACTIVE    in migration (not stopped/completed)  -> not selectable
"!   STOPPED   stopped                               -> selectable (re-process)
"!   COMPLETED status completed                      -> not selectable
"! Supports $search (name / description / package), $filter on FormName,
"! MigState and Selectable, $orderby, $top/$skip and $count.
CLASS zcl_ab_bolt_q_form DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

    CONSTANTS:
      BEGIN OF gc_state,
        none      TYPE c LENGTH 10 VALUE 'NONE',
        active    TYPE c LENGTH 10 VALUE 'ACTIVE',
        stopped   TYPE c LENGTH 10 VALUE 'STOPPED',
        completed TYPE c LENGTH 10 VALUE 'COMPLETED',
      END OF gc_state.

    TYPES ty_t_row TYPE STANDARD TABLE OF zab_cds_ce_bolt_form WITH EMPTY KEY.

    "! All rows, unfiltered (also used by ABAP Unit and the self-test).
    METHODS build
      RETURNING VALUE(rt_rows) TYPE ty_t_row.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_ab_bolt_q_form IMPLEMENTATION.

  METHOD build.
    TYPES:
      BEGIN OF ty_last,
        form_name  TYPE zabt_bolt_mig-form_name,
        run_no     TYPE zabt_bolt_mig-run_no,
        mig_uuid   TYPE zabt_bolt_mig-mig_uuid,
        serial_no  TYPE zabt_bolt_mig-serial_no,
        mig_status TYPE zabt_bolt_mig-mig_status,
        stopped    TYPE zabt_bolt_mig-stopped,
        push_status TYPE zabt_bolt_mig-push_status,
      END OF ty_last.
    DATA lt_all  TYPE STANDARD TABLE OF ty_last WITH EMPTY KEY.
    DATA lt_last TYPE SORTED TABLE OF ty_last WITH UNIQUE KEY form_name.

    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).
    zcl_ab_bolt_config=>prefixes( EXPORTING is_setup   = ls_setup
                                  IMPORTING ev_prefix1 = DATA(lv_p1)
                                            ev_prefix2 = DATA(lv_p2) ).
    DATA(lt_forms) = zcl_ab_bolt_form_catalog=>list( iv_prefix1 = lv_p1 iv_prefix2 = lv_p2 ).

    SELECT form_name, run_no, mig_uuid, serial_no, mig_status, stopped, push_status FROM zabt_bolt_mig
      ORDER BY form_name, run_no DESCENDING
      INTO TABLE @lt_all.
    LOOP AT lt_all INTO DATA(ls_row_db).
      IF NOT line_exists( lt_last[ form_name = ls_row_db-form_name ] ).
        lt_last = VALUE #( BASE lt_last ( ls_row_db ) ).
      ENDIF.
    ENDLOOP.

    LOOP AT lt_forms INTO DATA(ls_form).
      DATA(ls_row) = VALUE zab_cds_ce_bolt_form(
        formname    = ls_form-form_name
        description = ls_form-description
        devpackage  = ls_form-dev_package
        createdby   = ls_form-created_by
        createdon   = ls_form-created_on
        changedby   = ls_form-changed_by
        changedon   = ls_form-changed_on
        driverprogs = ls_form-driver_progs
        outputtypes = ls_form-output_types
        migstate    = gc_state-none
        selectable  = abap_true ).
      READ TABLE lt_last INTO DATA(ls_last) WITH TABLE KEY form_name = ls_form-form_name.
      IF sy-subrc = 0.
        ls_row-lastserialno = ls_last-serial_no.
        ls_row-lastrunno    = ls_last-run_no.
        " A draft (initial load not on GitHub yet) says so instead of the status-file status.
        ls_row-laststatus   = COND #( WHEN ls_last-push_status <> zcl_ab_bolt_config=>gc_push-pushed THEN 'draft' ELSE ls_last-mig_status ).
        ls_row-lastmiguuid  = ls_last-mig_uuid.
        IF ls_last-mig_status = zcl_ab_bolt_config=>gc_status-completed.
          ls_row-migstate   = gc_state-completed.
          ls_row-selectable = abap_false.
        ELSEIF ls_last-stopped = abap_true.
          ls_row-migstate   = gc_state-stopped.
          ls_row-selectable = abap_true.
        ELSE.
          ls_row-migstate   = gc_state-active.
          ls_row-selectable = abap_false.
        ENDIF.
      ENDIF.
      APPEND ls_row TO rt_rows.
      CLEAR ls_last.
    ENDLOOP.
  ENDMETHOD.


  METHOD if_rap_query_provider~select.
    DATA lr_name  TYPE RANGE OF zab_cds_ce_bolt_form-formname.
    DATA lr_state TYPE RANGE OF zab_cds_ce_bolt_form-migstate.
    DATA lr_sel   TYPE RANGE OF zab_cds_ce_bolt_form-selectable.

    DATA(lt_all) = build( ).

    " $search: name, description or package contains the text (CS ignores case)
    DATA(lv_search) = condense( io_request->get_search_expression( ) ).
    REPLACE ALL OCCURRENCES OF `"` IN lv_search WITH ``.
    IF lv_search IS NOT INITIAL.
      DELETE lt_all WHERE NOT ( formname CS lv_search OR description CS lv_search OR devpackage CS lv_search ).
    ENDIF.

    TRY.
        DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).
        LOOP AT lt_ranges INTO DATA(ls_range).
          CASE ls_range-name.
            WHEN `FORMNAME`.
              lr_name = CORRESPONDING #( ls_range-range ).
              DELETE lt_all WHERE formname NOT IN lr_name.
            WHEN `MIGSTATE`.
              lr_state = CORRESPONDING #( ls_range-range ).
              DELETE lt_all WHERE migstate NOT IN lr_state.
            WHEN `SELECTABLE`.
              lr_sel = CORRESPONDING #( ls_range-range ).
              DELETE lt_all WHERE selectable NOT IN lr_sel.
          ENDCASE.
        ENDLOOP.
      CATCH cx_rap_query_filter_no_range.
        " A filter that is not a range (e.g. contains()) is ignored - $search covers it.
    ENDTRY.

    DATA(lt_sort) = io_request->get_sort_elements( ).
    DATA(lt_order) = VALUE abap_sortorder_tab( FOR ls_sort IN lt_sort
                                               ( name = ls_sort-element_name descending = ls_sort-descending ) ).
    IF lt_order IS INITIAL.
      lt_order = VALUE #( ( name = `FORMNAME` ) ).
    ENDIF.
    SORT lt_all BY (lt_order).

    " Read the paging always - RAP terminates when a requested option is not read.
    DATA(lo_paging) = io_request->get_paging( ).
    DATA(lv_offset) = lo_paging->get_offset( ).
    DATA(lv_size)   = lo_paging->get_page_size( ).

    IF io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( lt_all ) ).
    ENDIF.
    IF io_request->is_data_requested( ) = abap_false.
      RETURN.
    ENDIF.

    DATA lt_page TYPE ty_t_row.
    IF lv_size = if_rap_query_paging=>page_size_unlimited OR lv_size <= 0.
      lt_page = lt_all.
    ELSE.
      DATA(lv_lo) = lv_offset + 1.
      DATA(lv_hi) = lv_offset + lv_size.
      LOOP AT lt_all INTO DATA(ls_page_row) FROM lv_lo TO lv_hi.
        APPEND ls_page_row TO lt_page.
      ENDLOOP.
    ENDIF.
    io_response->set_data( lt_page ).
  ENDMETHOD.

ENDCLASS.
