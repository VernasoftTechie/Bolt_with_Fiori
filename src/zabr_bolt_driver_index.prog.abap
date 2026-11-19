*&---------------------------------------------------------------------*
*& Report ZABR_BOLT_DRIVER_INDEX
*&---------------------------------------------------------------------*
*& Bolt - builds the Smart Form driver index of THIS system.
*&
*& The legacy grab's slow step: read every custom program once and note
*& which Smart Forms it calls near SSF_FUNCTION_MODULE_NAME (the same
*& +/-20-line window rule as ZSF2AF_R_LEGACY_GRAB). Stored in
*& ZABT_BOLT_DRVIX so one form's grab from the Fiori app stays fast and the
*& Smart Forms tab can show driver programs. The NACE driver (TNAPR) is always
*& used anyway; this index adds drivers that NACE does not name.
*&
*& Run it once after installation, then daily in background
*& (job Z_AB_DA_BOLT_DRIVER_INDEX, see docs/04_installation.md).
*& Prefixes default to the Configuration tab's "Smart Form name prefixes".
*&---------------------------------------------------------------------*
REPORT zabr_bolt_driver_index.

PARAMETERS p_pref1 TYPE c LENGTH 10.
PARAMETERS p_pref2 TYPE c LENGTH 10.
PARAMETERS cb_test AS CHECKBOX DEFAULT abap_false.

INITIALIZATION.
  " A setup row that does not exist yet gives the default prefixes Z and Y.
  zcl_ab_bolt_config=>prefixes( EXPORTING is_setup   = zcl_ab_bolt_config=>get_setup( )
                                IMPORTING ev_prefix1 = DATA(gv_p1)
                                          ev_prefix2 = DATA(gv_p2) ).
  p_pref1 = gv_p1.
  p_pref2 = gv_p2.

START-OF-SELECTION.
  DATA gt_db  TYPE STANDARD TABLE OF zabt_bolt_drvix WITH EMPTY KEY.
  DATA gv_now TYPE timestampl.

  DATA(gv_prefix1) = to_upper( condense( CONV string( p_pref1 ) ) ).
  DATA(gv_prefix2) = to_upper( condense( CONV string( p_pref2 ) ) ).
  DATA(gt_forms) = VALUE string_table( FOR ls_form IN zcl_ab_bolt_form_catalog=>list( iv_prefix1 = gv_prefix1
                                                                                       iv_prefix2 = gv_prefix2 )
                                       ( CONV string( ls_form-form_name ) ) ).
  WRITE: / |{ lines( gt_forms ) } custom Smart Form(s) on { sy-sysid }.|.
  IF gt_forms IS INITIAL.
    RETURN.
  ENDIF.

  DATA(go_grab) = NEW zcl_ab_bolt_legacy_grab( iv_prefix1 = gv_prefix1
                                               iv_prefix2 = gv_prefix2 ).
  DATA(gt_idx) = go_grab->build_driver_index( gt_forms ).
  LOOP AT go_grab->get_log( ) INTO DATA(gv_log).
    WRITE: / gv_log.
  ENDLOOP.

  GET TIME STAMP FIELD gv_now.
  gt_db = VALUE #( FOR ls_idx IN gt_idx ( form_name  = ls_idx-formname
                                          prog_name  = ls_idx-progname
                                          indexed_at = gv_now ) ).
  SORT gt_db BY form_name prog_name.
  DELETE ADJACENT DUPLICATES FROM gt_db COMPARING form_name prog_name.

  WRITE: / |{ lines( gt_db ) } form/driver candidate pair(s) found.|.
  LOOP AT gt_db INTO DATA(gs_db).
    WRITE: / |  { gs_db-form_name } <- { gs_db-prog_name }|.
  ENDLOOP.

  IF cb_test = abap_true.
    WRITE: / `Test run - nothing saved.`.
    RETURN.
  ENDIF.

  DELETE FROM zabt_bolt_drvix.
  MODIFY zabt_bolt_drvix FROM TABLE @gt_db.
  COMMIT WORK.
  WRITE: / `Driver index saved.`.
