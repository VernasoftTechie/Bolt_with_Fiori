"! Checks the ABAP port against the real status-file format the engineer
"! windows write (sample taken from vernasofttechie-zmm_po_demo).
CLASS ltcl_status_file DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS sample
      RETURNING VALUE(rv_text) TYPE string.

    METHODS parse_header FOR TESTING.
    METHODS parse_timeline FOR TESTING.
    METHODS append_keeps_fields FOR TESTING.
    METHODS append_overrides FOR TESTING.
    METHODS branch_and_slug FOR TESTING.
    METHODS trim_blanks FOR TESTING.
ENDCLASS.


CLASS ltcl_status_file IMPLEMENTATION.

  METHOD sample.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    DATA(lv_d)  = zcl_bolt_status_file=>gc_dash.
    rv_text = |# Migration Status { lv_d } ZMM_PO_DEMO{ lv_nl }{ lv_nl }| &&
              |STATUS: waiting_manual{ lv_nl }| &&
              |UPDATED: 2026-10-06T07:00:34.000Z{ lv_nl }| &&
              |WAITING_ON: operator{ lv_nl }| &&
              |NOTE: Layout pushed - pull it, activate, and preview.{ lv_nl }| &&
              |STOP: none{ lv_nl }| &&
              |CLAIMED_BY: Window-1{ lv_nl }{ lv_nl }| &&
              |---{ lv_nl }{ lv_nl }| &&
              |## 2026-10-05T13:13:33.381Z { lv_d } Queued{ lv_nl }| &&
              |Migration submitted with 2 reference file(s).{ lv_nl }{ lv_nl }| &&
              |## 2026-10-06T06:18:58.000Z { lv_d } Picked up{ lv_nl }| &&
              |Window-1 picked this migration up.{ lv_nl }| &&
              |- second line   with  spaces{ lv_nl }|.
  ENDMETHOD.


  METHOD parse_header.
    DATA(ls_status) = zcl_bolt_status_file=>parse( sample( ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-title      exp = `ZMM_PO_DEMO` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-status     exp = `waiting_manual` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-updated_at exp = `2026-10-06T07:00:34.000Z` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-waiting_on exp = `operator` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-note       exp = `Layout pushed - pull it, activate, and preview.` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-stop       exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-claimed_by exp = `Window-1` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-label
                                        exp = |Waiting { zcl_bolt_status_file=>gc_dash } Manual Activity| ).
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_status-body sub = `## ` ) exp = 0 ).
  ENDMETHOD.


  METHOD parse_timeline.
    DATA(ls_status) = zcl_bolt_status_file=>parse( sample( ) ).
    DATA(lt_entries) = zcl_bolt_status_file=>timeline( ls_status-body ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_entries ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lt_entries[ 1 ]-at      exp = `2026-10-05T13:13:33.381Z` ).
    cl_abap_unit_assert=>assert_equals( act = lt_entries[ 1 ]-heading exp = `Queued` ).
    cl_abap_unit_assert=>assert_equals( act = lt_entries[ 1 ]-text    exp = `Migration submitted with 2 reference file(s).` ).
    cl_abap_unit_assert=>assert_equals( act = lt_entries[ 2 ]-heading exp = `Picked up` ).
    " Inner spacing of the engineer's text must survive untouched.
    cl_abap_unit_assert=>assert_char_cp( act = lt_entries[ 2 ]-text exp = '*second line   with  spaces' ).
  ENDMETHOD.


  METHOD append_keeps_fields.
    DATA(lv_new) = zcl_bolt_status_file=>append_entry(
                     iv_existing   = sample( )
                     iv_title      = `ZMM_PO_DEMO`
                     iv_heading    = `Concern raised`
                     iv_entry_text = `Please check page 2.` ).
    DATA(ls_status) = zcl_bolt_status_file=>parse( lv_new ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-status     exp = `waiting_manual` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-waiting_on exp = `operator` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-claimed_by exp = `Window-1` ).
    DATA(lt_entries) = zcl_bolt_status_file=>timeline( ls_status-body ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_entries ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = lt_entries[ 3 ]-heading exp = `Concern raised` ).
    cl_abap_unit_assert=>assert_equals( act = lt_entries[ 3 ]-text    exp = `Please check page 2.` ).
  ENDMETHOD.


  METHOD append_overrides.
    DATA(lv_new) = zcl_bolt_status_file=>append_entry(
                     iv_existing   = sample( )
                     iv_title      = `ZMM_PO_DEMO`
                     iv_heading    = `Manual activity confirmed`
                     iv_entry_text = `Client confirmed the manual step is done.`
                     is_change     = VALUE #( status     = `in_progress` set_status     = abap_true
                                              waiting_on = `engineer`    set_waiting_on = abap_true
                                              note       = ``            set_note       = abap_true ) ).
    DATA(ls_status) = zcl_bolt_status_file=>parse( lv_new ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-status     exp = `in_progress` ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-waiting_on exp = `engineer` ).
    cl_abap_unit_assert=>assert_initial( ls_status-note ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-claimed_by exp = `Window-1` ).
    " The engineer windows look for this exact heading text.
    cl_abap_unit_assert=>assert_true(
      xsdbool( find( val = lv_new sub = |{ zcl_bolt_status_file=>gc_dash } Manual activity confirmed| ) > 0 ) ).

    DATA(lv_stop) = zcl_bolt_status_file=>append_entry(
                      iv_existing   = lv_new
                      iv_title      = `ZMM_PO_DEMO`
                      iv_heading    = `Stop requested`
                      iv_entry_text = `Client requested a stop.`
                      is_change     = VALUE #( stop = abap_true set_stop = abap_true ) ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bolt_status_file=>parse( lv_stop )-stop exp = abap_true ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_stop exp = '*STOP: requested*' ).
  ENDMETHOD.


  METHOD branch_and_slug.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_bolt_status_file=>branch_name( iv_display_name = `ZMMET_PO_SF` iv_prefix = `vernasofttechie` )
      exp = `vernasofttechie-zmmet_po_sf` ).
    cl_abap_unit_assert=>assert_equals(
      act = zcl_bolt_status_file=>branch_name( iv_display_name = `Invoice Printing Form` iv_prefix = `` )
      exp = `invoice-printing-form` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bolt_status_file=>form_slug( `ZMMET_PO_SF` ) exp = `zmmet_po_sf` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bolt_status_file=>form_slug( `/ABC/MY FORM` ) exp = `abc_my_form` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_bolt_status_file=>file_path( `zmmet_po_sf` )
                                        exp = `docs/legacy_grab/zmmet_po_sf_status.md` ).
  ENDMETHOD.


  METHOD trim_blanks.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    cl_abap_unit_assert=>assert_equals( act = zcl_bolt_status_file=>trim( |{ lv_nl }  a  b { lv_nl }| ) exp = `a  b` ).
    cl_abap_unit_assert=>assert_initial( zcl_bolt_status_file=>trim( |  { lv_nl }| ) ).
  ENDMETHOD.

ENDCLASS.
