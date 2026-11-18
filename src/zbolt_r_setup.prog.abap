*&---------------------------------------------------------------------*
*& Report ZBOLT_R_SETUP
*&---------------------------------------------------------------------*
*& Bolt with Fiori - one-time setup defaults (optional).
*&
*& Pre-fills the Configuration tab so a client's app opens ready: client
*& name, GitHub destination/owner/repository/branch prefix and the DEV/QA/
*& PRD source systems (SM59 destination + SAP client each). Only fields you
*& fill are written; everything stays editable in the app afterwards.
*& The GitHub token is never entered here - it lives in the SM59
*& destination (docs/03_client_connectivity.md).
*&---------------------------------------------------------------------*
REPORT zbolt_r_setup.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
PARAMETERS p_cust  TYPE c LENGTH 60  LOWER CASE.
PARAMETERS p_ghdst TYPE rfcdest.
PARAMETERS p_owner TYPE c LENGTH 60  LOWER CASE.
PARAMETERS p_repo  TYPE c LENGTH 100 LOWER CASE.
PARAMETERS p_base  TYPE c LENGTH 60  LOWER CASE DEFAULT 'main'.
PARAMETERS p_prefx TYPE c LENGTH 60  LOWER CASE DEFAULT 'vernasofttechie'.
PARAMETERS p_admin TYPE c LENGTH 132.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
PARAMETERS p_path  TYPE c LENGTH 132 LOWER CASE DEFAULT '/sap/opu/odata4/sap/zbolt_ui_o4/srvd/sap/zbolt_ui/0001/'.
PARAMETERS p_devd  TYPE rfcdest.
PARAMETERS p_devc  TYPE c LENGTH 3.
PARAMETERS p_devl  AS CHECKBOX DEFAULT abap_true.
PARAMETERS p_qad   TYPE rfcdest.
PARAMETERS p_qac   TYPE c LENGTH 3.
PARAMETERS p_prdd  TYPE rfcdest.
PARAMETERS p_prdc  TYPE c LENGTH 3.
SELECTION-SCREEN END OF BLOCK b2.

START-OF-SELECTION.
  DATA lv_now TYPE timestampl.
  GET TIME STAMP FIELD lv_now.

  " --- setup row ------------------------------------------------------
  DATA(ls_setup) = zcl_bolt_config=>get_setup( ).
  IF ls_setup IS INITIAL.
    ls_setup = VALUE #( setup_id         = zcl_bolt_config=>gc_setup_id
                        gh_base_branch   = zcl_bolt_config=>gc_default_base
                        gh_branch_prefix = zcl_bolt_config=>gc_default_prefix
                        ai_provider      = zcl_bolt_config=>gc_provider_none
                        ai_max_tokens    = 2000
                        form_prefix1     = 'Z'
                        form_prefix2     = 'Y'
                        count_volume     = abap_true
                        created_by       = sy-uname
                        created_at       = lv_now ).
  ENDIF.
  IF p_cust IS NOT INITIAL.
    ls_setup-customer_name = p_cust.
  ENDIF.
  IF p_ghdst IS NOT INITIAL.
    ls_setup-gh_destination = p_ghdst.
  ENDIF.
  IF p_owner IS NOT INITIAL.
    ls_setup-gh_owner = p_owner.
  ENDIF.
  IF p_repo IS NOT INITIAL.
    ls_setup-gh_repo = p_repo.
  ENDIF.
  IF p_base IS NOT INITIAL.
    ls_setup-gh_base_branch = p_base.
  ENDIF.
  IF p_prefx IS NOT INITIAL.
    ls_setup-gh_branch_prefix = p_prefx.
  ENDIF.
  IF p_admin IS NOT INITIAL.
    ls_setup-admin_users = p_admin.
  ENDIF.
  ls_setup-changed_by         = sy-uname.
  ls_setup-changed_at         = lv_now.
  ls_setup-local_last_changed = lv_now.
  MODIFY zbolt_setup FROM @ls_setup.
  WRITE: / `Setup saved.`.

  " --- source systems -------------------------------------------------
  TYPES:
    BEGIN OF ty_sys_in,
      id     TYPE zbolt_system-system_id,
      dest   TYPE rfcdest,
      client TYPE zbolt_system-sap_client,
      is_loc TYPE abap_bool,
      seq    TYPE i,
    END OF ty_sys_in.
  DATA lt_in TYPE STANDARD TABLE OF ty_sys_in WITH EMPTY KEY.
  lt_in = VALUE #( ( id = 'DEV' dest = p_devd client = p_devc is_loc = p_devl     seq = 10 )
                   ( id = 'QA'  dest = p_qad  client = p_qac  is_loc = abap_false seq = 20 )
                   ( id = 'PRD' dest = p_prdd client = p_prdc is_loc = abap_false seq = 30 ) ).

  LOOP AT lt_in INTO DATA(ls_in).
    IF ls_in-dest IS INITIAL AND ls_in-is_loc = abap_false.
      CONTINUE.
    ENDIF.
    DATA(ls_system) = zcl_bolt_config=>get_system( ls_in-id ).
    IF ls_system IS INITIAL.
      ls_system = VALUE #( system_id  = ls_in-id
                           created_by = sy-uname
                           created_at = lv_now ).
    ENDIF.
    ls_system-description  = COND #( WHEN ls_in-is_loc = abap_true THEN |{ ls_in-id } - this system ({ sy-sysid })|
                                     ELSE |{ ls_in-id } system| ).
    ls_system-destination  = ls_in-dest.
    ls_system-sap_client   = COND #( WHEN ls_in-client IS NOT INITIAL THEN ls_in-client
                                     WHEN ls_in-is_loc = abap_true    THEN sy-mandt ).
    ls_system-service_path = p_path.
    ls_system-is_local     = ls_in-is_loc.
    ls_system-is_default   = xsdbool( ls_in-id = 'DEV' ).
    ls_system-sort_order   = ls_in-seq.
    ls_system-changed_by   = sy-uname.
    ls_system-changed_at   = lv_now.
    ls_system-local_last_changed = lv_now.
    MODIFY zbolt_system FROM @ls_system.
    WRITE: / |System { ls_in-id } saved.|.
  ENDLOOP.

  COMMIT WORK.
  WRITE: / `Done - open the Bolt app, Configuration tab, and run each Test connection.`.
