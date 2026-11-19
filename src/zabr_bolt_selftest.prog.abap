*&---------------------------------------------------------------------*
*& Report ZABR_BOLT_SELFTEST
*&---------------------------------------------------------------------*
*& Bolt - backend self-test (increment 2 acceptance, then any time).
*&
*& 1. Produces every legacy file of one Smart Form exactly as the Commit in
*&    the Fiori app will (legacy grab .md + drivers, Smart Form XML, Smart
*&    Styles) and lists them with kind and size. Nothing is sent anywhere.
*& 2. Optionally downloads them to a PC folder, to compare the .xml with
*&    SMARTFORMS > Utilities > Download Form (installation guide step B2.4).
*& 3. Optionally checks the GitHub connection and the AI provider stored on
*&    the Setup page (read-only calls: GET /user, GET /repos/...).
*&---------------------------------------------------------------------*
REPORT zabr_bolt_selftest.

PARAMETERS p_form TYPE tdsfname OBLIGATORY.
PARAMETERS cb_down AS CHECKBOX DEFAULT abap_false.
PARAMETERS p_path TYPE string LOWER CASE DEFAULT `C:\temp\bolt_selftest`.
PARAMETERS cb_gh AS CHECKBOX DEFAULT abap_false.
PARAMETERS cb_ai AS CHECKBOX DEFAULT abap_false.

START-OF-SELECTION.
  DATA(gs_setup) = zcl_ab_bolt_config=>get_setup( ).
  IF gs_setup IS INITIAL.
    gs_setup = zcl_ab_bolt_config=>default_setup( ).
    WRITE: / `No setup row yet - using the defaults (open the Bolt app once to create it).`.
  ENDIF.

  " ---- 1. legacy files ---------------------------------------------------
  DATA(gv_form) = to_upper( condense( CONV string( p_form ) ) ).
  DATA(gs_mig) = VALUE zcl_ab_bolt_mig_svc=>ty_mig(
                   form_name   = gv_form
                   form_slug   = zcl_ab_bolt_status_file=>form_slug( gv_form )
                   branch_name = zcl_ab_bolt_mig_svc=>branch_for( iv_form_name = gv_form iv_run_no = 1 is_setup = gs_setup )
                   run_no      = 1 ).
  WRITE: / |Smart Form { gv_form } - branch would be { gs_mig-branch_name }|.
  ULINE.
  TRY.
      DATA(gs_build) = zcl_ab_bolt_mig_svc=>build_files( is_mig = gs_mig is_setup = gs_setup ).
      LOOP AT gs_build-infos INTO DATA(gs_info).
        WRITE: / gs_info-kind, gs_info-size, gs_info-path.
      ENDLOOP.
      WRITE: / |{ lines( gs_build-infos ) } file(s). Complexity: { gs_build-complexity } - { gs_build-complexity_info }|.
      LOOP AT gs_build-warnings INTO DATA(gv_warning).
        WRITE: / |Warning: { gv_warning }| COLOR COL_NEGATIVE.
      ENDLOOP.
    CATCH zcx_ab_bolt INTO DATA(gx_build).
      WRITE: / gx_build->get_text( ) COLOR COL_NEGATIVE.
  ENDTRY.

  " ---- 2. download to the PC -------------------------------------------------
  IF cb_down = abap_true AND sy-batch = abap_false AND gs_build IS NOT INITIAL.
    ULINE.
    LOOP AT gs_build-files INTO DATA(gs_file).
      DATA(gv_name) = substring_after( val = gs_file-path sub = `/` occ = -1 ).
      DATA(gt_bin) = cl_bcs_convert=>xstring_to_solix( gs_file-content ).
      cl_gui_frontend_services=>gui_download(
        EXPORTING
          bin_filesize = xstrlen( gs_file-content )
          filename     = |{ p_path }\\{ gv_name }|
          filetype     = 'BIN'
        CHANGING
          data_tab     = gt_bin
        EXCEPTIONS
          OTHERS       = 1 ).
      WRITE: / COND string( WHEN sy-subrc = 0 THEN |Saved { p_path }\\{ gv_name }|
                            ELSE |Could not save { gv_name } (does the folder { p_path } exist?)| ).
    ENDLOOP.
  ENDIF.

  " ---- 3. GitHub and AI ----------------------------------------------------
  IF cb_gh = abap_true.
    ULINE.
    TRY.
        DATA(go_github) = zcl_ab_bolt_github=>for_stored_token( ).
        DATA(gs_user) = go_github->verify_token( ).
        WRITE: / |GitHub: connected as { gs_user-login } ({ gs_user-name }), scopes: { COND string( WHEN gs_user-scopes IS INITIAL THEN `fine-grained token` ELSE gs_user-scopes ) }|.
        IF gs_setup-gh_repo IS NOT INITIAL.
          DATA(gs_repo) = go_github->check_repo( gs_setup-gh_repo ).
          WRITE: / |Repository { gs_repo-full_name }: { COND string( WHEN gs_repo-private = abap_true THEN `private` ELSE `public` ) }, | &&
                   |default branch { gs_repo-default_branch }, { COND string( WHEN gs_repo-can_push = abap_true THEN `push access` ELSE `read-only` ) }|.
        ELSE.
          WRITE: / `No target repository set yet.`.
        ENDIF.
      CATCH zcx_ab_bolt INTO DATA(gx_gh).
        WRITE: / gx_gh->get_text( ) COLOR COL_NEGATIVE.
    ENDTRY.
  ENDIF.

  IF cb_ai = abap_true.
    ULINE.
    TRY.
        WRITE: / zcl_ab_bolt_ai=>test( gs_setup ).
      CATCH zcx_ab_bolt INTO DATA(gx_ai).
        WRITE: / gx_ai->get_text( ) COLOR COL_NEGATIVE.
    ENDTRY.
  ENDIF.
