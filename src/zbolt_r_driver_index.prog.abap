*&---------------------------------------------------------------------*
*& Report ZBOLT_R_DRIVER_INDEX
*&---------------------------------------------------------------------*
*& Bolt with Fiori - builds the Smart Form driver index of THIS system.
*&
*& The legacy grab's slow step: read every custom (Z*/Y*) program once and
*& note which Smart Forms it calls near SSF_FUNCTION_MODULE_NAME (the same
*& +/-20-line window rule as ZSF2AF_R_LEGACY_GRAB). Stored in ZBOLT_DRVIDX
*& so a single form's grab from the Fiori app stays fast. Run it once on
*& every source system (DEV, QA, PRD) after installation, then weekly in
*& background (SM36). The NACE driver (TNAPR) is always extracted anyway;
*& this index adds drivers that NACE does not name.
*&---------------------------------------------------------------------*
REPORT zbolt_r_driver_index.

PARAMETERS p_pref1 TYPE c LENGTH 10 DEFAULT 'Z'.
PARAMETERS p_pref2 TYPE c LENGTH 10 DEFAULT 'Y'.
PARAMETERS p_test  AS CHECKBOX DEFAULT abap_false.

START-OF-SELECTION.
  DATA lt_db  TYPE STANDARD TABLE OF zbolt_drvidx WITH EMPTY KEY.
  DATA lv_now TYPE timestampl.

  DATA(lv_prefixes) = |{ condense( p_pref1 ) },{ condense( p_pref2 ) }|.
  DATA(lt_forms) = VALUE string_table( FOR ls_form IN zcl_bolt_source=>list_forms_local( lv_prefixes )
                                       ( ls_form-form_name ) ).
  WRITE: / |{ lines( lt_forms ) } custom Smart Form(s) on { sy-sysid } client { sy-mandt }.|.
  IF lt_forms IS INITIAL.
    RETURN.
  ENDIF.

  DATA(lo_grab) = NEW zcl_bolt_legacy_grab( iv_prefix1 = condense( CONV string( p_pref1 ) )
                                            iv_prefix2 = condense( CONV string( p_pref2 ) ) ).
  DATA(lt_idx) = lo_grab->build_driver_index( lt_forms ).
  LOOP AT lo_grab->get_log( ) INTO DATA(lv_log).
    WRITE: / lv_log.
  ENDLOOP.

  GET TIME STAMP FIELD lv_now.
  lt_db = VALUE #( FOR ls_idx IN lt_idx ( form_name  = ls_idx-formname
                                          prog_name  = ls_idx-progname
                                          indexed_at = lv_now ) ).
  SORT lt_db BY form_name prog_name.
  DELETE ADJACENT DUPLICATES FROM lt_db COMPARING form_name prog_name.

  WRITE: / |{ lines( lt_db ) } form/driver candidate pair(s) found.|.
  LOOP AT lt_db INTO DATA(ls_db).
    WRITE: / |  { ls_db-form_name } <- { ls_db-prog_name }|.
  ENDLOOP.

  IF p_test = abap_true.
    WRITE: / `Test run - nothing saved.`.
    RETURN.
  ENDIF.

  DELETE FROM zbolt_drvidx.
  MODIFY zbolt_drvidx FROM TABLE @lt_db.
  COMMIT WORK.
  WRITE: / `Driver index saved.`.
