"! <p class="shorttext synchronized">Bolt - live status file and timeline query</p>
"! Serves ZAB_CDS_CE_BOLT_STATUS (header) and ZAB_CDS_CE_BOLT_TIMELN (entries)
"! from the migration branch's status file, read live from GitHub - the
"! communication texts are never stored in SAP. Both entities are requested
"! with $filter=MigUuid eq <uuid>; the file is read once per request even
"! when the screen asks for both in one $batch.
CLASS zcl_ab_bolt_q_status DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_cache,
        mig_uuid TYPE sysuuid_x16,
        read     TYPE zcl_ab_bolt_mig_svc=>ty_read,
        message  TYPE string,
        url      TYPE string,
      END OF ty_cache,
      ty_t_cache TYPE SORTED TABLE OF ty_cache WITH UNIQUE KEY mig_uuid.

    CLASS-DATA gt_cache TYPE ty_t_cache.

    METHODS uuids
      IMPORTING io_request     TYPE REF TO if_rap_query_request
      RETURNING VALUE(rt_uuid) TYPE string_table.

    METHODS load
      IMPORTING iv_uuid         TYPE sysuuid_x16
      RETURNING VALUE(rs_cache) TYPE ty_cache.
ENDCLASS.



CLASS zcl_ab_bolt_q_status IMPLEMENTATION.

  METHOD uuids.
    TRY.
        DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range.
        RETURN.
    ENDTRY.
    READ TABLE lt_ranges INTO DATA(ls_range) WITH KEY name = `MIGUUID`.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    LOOP AT ls_range-range INTO DATA(ls_line) WHERE sign = 'I' AND option = 'EQ'.
      " Internal format is 32 hex characters; tolerate the dashed GUID form too.
      DATA(lv_text) = to_upper( condense( CONV string( ls_line-low ) ) ).
      REPLACE ALL OCCURRENCES OF `-` IN lv_text WITH ``.
      APPEND lv_text TO rt_uuid.
    ENDLOOP.
  ENDMETHOD.


  METHOD load.
    READ TABLE gt_cache INTO rs_cache WITH TABLE KEY mig_uuid = iv_uuid.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    rs_cache-mig_uuid = iv_uuid.
    SELECT SINGLE * FROM zabt_bolt_mig WHERE mig_uuid = @iv_uuid INTO @DATA(ls_row).
    IF sy-subrc <> 0.
      rs_cache-message = `This migration does not exist.`.
    ELSEIF ls_row-push_status <> zcl_ab_bolt_config=>gc_push-pushed.
      rs_cache-message = `Not on GitHub yet - the timeline starts once the migration is sent.`.
    ELSE.
      TRY.
          DATA(lo_github) = zcl_ab_bolt_github=>from_setup( ).
          rs_cache-url  = lo_github->web_url( condense( CONV string( ls_row-branch_name ) ) ).
          rs_cache-read = zcl_ab_bolt_mig_svc=>read_status( zcl_ab_bolt_mig_svc=>from_row( ls_row ) ).
          IF rs_cache-read-found = abap_false.
            rs_cache-message = `The status file is not on the branch (yet).`.
          ENDIF.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          rs_cache-message = lx_error->get_text( ).
      ENDTRY.
    ENDIF.
    gt_cache = VALUE #( BASE gt_cache ( rs_cache ) ).
  ENDMETHOD.


  METHOD if_rap_query_provider~select.
    DATA lt_status   TYPE STANDARD TABLE OF zab_cds_ce_bolt_status WITH EMPTY KEY.
    DATA lt_timeline TYPE STANDARD TABLE OF zab_cds_ce_bolt_timeln WITH EMPTY KEY.

    DATA(lt_uuid) = uuids( io_request ).
    DATA(lv_entity) = io_request->get_entity_id( ).

    LOOP AT lt_uuid INTO DATA(lv_uuid_text).
      DATA lv_uuid TYPE sysuuid_x16.
      TRY.
          lv_uuid = CONV sysuuid_x16( lv_uuid_text ).
        CATCH cx_root ##CATCH_ALL.
          CONTINUE.
      ENDTRY.
      DATA(ls_cache) = load( lv_uuid ).

      IF lv_entity = 'ZAB_CDS_CE_BOLT_TIMELN'.
        LOOP AT ls_cache-read-entries INTO DATA(ls_entry).
          APPEND VALUE #( miguuid   = lv_uuid
                          entryno   = sy-tabix
                          entryat   = ls_entry-at
                          heading   = ls_entry-heading
                          entrytext = ls_entry-text ) TO lt_timeline.
        ENDLOOP.
      ELSE.
        DATA(ls_status) = ls_cache-read-status.
        APPEND VALUE #( miguuid       = lv_uuid
                        statusfound   = ls_cache-read-found
                        migstatus     = ls_status-status
                        statuslabel   = ls_status-label
                        updatedat     = ls_status-updated_at
                        waitingon     = ls_status-waiting_on
                        note          = ls_status-note
                        stoprequested = ls_status-stop
                        claimedby     = ls_status-claimed_by
                        entrycount    = lines( ls_cache-read-entries )
                        branchurl     = ls_cache-url
                        message       = ls_cache-message ) TO lt_status.
      ENDIF.
    ENDLOOP.

    IF lv_entity = 'ZAB_CDS_CE_BOLT_TIMELN'.
      " Newest first unless the screen asks otherwise (the web app shows newest first).
      DATA(lt_sort) = io_request->get_sort_elements( ).
      DATA(lt_order) = VALUE abap_sortorder_tab( FOR ls_sort IN lt_sort
                                                 ( name = ls_sort-element_name descending = ls_sort-descending ) ).
      IF lt_order IS INITIAL.
        lt_order = VALUE #( ( name = `ENTRYNO` descending = abap_true ) ).
      ENDIF.
      SORT lt_timeline BY (lt_order).
      IF io_request->is_total_numb_of_rec_requested( ) = abap_true.
        io_response->set_total_number_of_records( lines( lt_timeline ) ).
      ENDIF.
      IF io_request->is_data_requested( ) = abap_true.
        io_response->set_data( lt_timeline ).
      ENDIF.
    ELSE.
      IF io_request->is_total_numb_of_rec_requested( ) = abap_true.
        io_response->set_total_number_of_records( lines( lt_status ) ).
      ENDIF.
      IF io_request->is_data_requested( ) = abap_true.
        io_response->set_data( lt_status ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
