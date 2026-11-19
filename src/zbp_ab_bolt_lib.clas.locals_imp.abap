"! Global reference library - same behaviour as GlobalLibrary.jsx:
"! several files at once, an optional provenance note, pushed in ONE commit to
"! <library folder>/<category folder>/ on the repository's default branch;
"! the list shows whether each file reached GitHub. Remove only takes a file
"! off this list - GitHub keeps it.
CLASS lhc_library DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    CLASS-DATA gv_cid TYPE i.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Library RESULT result.

    METHODS msg
      IMPORTING iv_severity   TYPE if_abap_behv_message=>t_severity
                iv_text       TYPE string
      RETURNING VALUE(ro_msg) TYPE REF TO if_abap_behv_message.

    METHODS upload FOR MODIFY
      IMPORTING keys FOR ACTION Library~upload RESULT result.
ENDCLASS.


CLASS lhc_library IMPLEMENTATION.

  METHOD msg.
    " Standard message 00(001) "&1&2&3&4...": up to 200 characters reach the screen
    " (new_message_with_text keeps only 50 on this release - BUILD_ISSUES_LOG B13).
    zcl_ab_bolt_config=>msg_vars( EXPORTING iv_text = iv_text
                                  IMPORTING ev_v1   = DATA(lv_v1)
                                            ev_v2   = DATA(lv_v2)
                                            ev_v3   = DATA(lv_v3)
                                            ev_v4   = DATA(lv_v4) ).
    ro_msg = new_message( id       = '00'
                          number   = '001'
                          severity = iv_severity
                          v1       = lv_v1
                          v2       = lv_v2
                          v3       = lv_v3
                          v4       = lv_v4 ).
  ENDMETHOD.


  METHOD get_global_authorizations.
    DATA(lv_admin) = COND #( WHEN zcl_ab_bolt_config=>is_admin( ) = abap_true
                             THEN if_abap_behv=>auth-allowed
                             ELSE if_abap_behv=>auth-unauthorized ).
    result = VALUE #( %delete        = lv_admin
                      %action-upload = lv_admin ).
  ENDMETHOD.


  METHOD upload.
    DATA lt_create TYPE TABLE FOR CREATE zab_cds_i_bolt_lib\\Library.
    DATA lt_push   TYPE zcl_ab_bolt_github=>ty_t_file.
    DATA lv_pushed TYPE abap_bool.
    DATA lv_msg    TYPE string.
    DATA lv_sha    TYPE string.

    DATA(ls_key) = keys[ 1 ].
    DATA(lv_category) = CONV zabt_bolt_lib-lib_category( to_lower( condense( CONV string( ls_key-%param-Category ) ) ) ).
    IF lv_category <> 'logo' AND lv_category <> 'smartstyle' AND lv_category <> 'naming_standard' AND lv_category <> 'policy'.
      APPEND VALUE #( %cid = ls_key-%cid ) TO failed-library.
      APPEND VALUE #( %cid = ls_key-%cid
                      %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                    iv_text     = `Choose a category first.` ) ) TO reported-library.
      RETURN.
    ENDIF.

    TRY.
        DATA(lt_files) = zcl_ab_bolt_mig_svc=>parse_uploads( ls_key-%param-FilesJson ).
      CATCH zcx_ab_bolt INTO DATA(lx_parse).
        APPEND VALUE #( %cid = ls_key-%cid ) TO failed-library.
        APPEND VALUE #( %cid = ls_key-%cid
                        %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                      iv_text     = lx_parse->get_text( ) ) ) TO reported-library.
        RETURN.
    ENDTRY.
    IF lt_files IS INITIAL.
      APPEND VALUE #( %cid = ls_key-%cid ) TO failed-library.
      APPEND VALUE #( %cid = ls_key-%cid
                      %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                    iv_text     = `Choose at least one file.` ) ) TO reported-library.
      RETURN.
    ENDIF.

    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).
    DATA(lv_folder) = |{ zcl_ab_bolt_config=>clean_folder( iv_folder  = ls_setup-lib_folder
                                                           iv_default = zcl_ab_bolt_config=>gc_default_library ) }/| &&
                      |{ zcl_ab_bolt_config=>library_subfolder( lv_category ) }|.

    LOOP AT lt_files INTO DATA(ls_file).
      DATA(lv_name) = zcl_ab_bolt_mig_svc=>safe_name( ls_file-name ).
      APPEND VALUE #( path = |{ lv_folder }/{ lv_name }| content = cl_http_utility=>decode_x_base64( ls_file-content ) )
        TO lt_push.
    ENDLOOP.

    " Saved in the list even when GitHub refuses - the list then says why (web app: "couldn't push").
    TRY.
        DATA(lo_github) = zcl_ab_bolt_github=>from_setup( ).
        DATA(lv_branch) = condense( CONV string( ls_setup-gh_base_branch ) ).
        IF lv_branch IS INITIAL.
          lv_branch = lo_github->default_branch( ).
        ENDIF.
        lv_sha = lo_github->add_files( iv_branch  = lv_branch
                                       it_files   = lt_push
                                       iv_message = |Add { lines( lt_push ) } file(s) to the global library ({ lv_category })| ).
        lv_pushed = abap_true.
        lv_msg = |Pushed to { lv_folder }/ on { lv_branch }.|.
      CATCH zcx_ab_bolt INTO DATA(lx_push).
        lv_pushed = abap_false.
        lv_msg = |Saved, but couldn't push to the repository: { lx_push->get_text( ) }|.
    ENDTRY.

    LOOP AT lt_push INTO DATA(ls_push).
      gv_cid += 1.
      APPEND VALUE #( %cid        = |LIB{ gv_cid }|
                      LibCategory = lv_category
                      FileName    = substring_after( val = ls_push-path sub = `/` occ = -1 )
                      FilePath    = ls_push-path
                      SizeBytes   = xstrlen( ls_push-content )
                      Provenance  = ls_key-%param-Provenance
                      Pushed      = lv_pushed
                      PushMsg     = COND #( WHEN strlen( lv_msg ) > 255 THEN substring( val = lv_msg len = 255 ) ELSE lv_msg )
                      CommitSha   = lv_sha ) TO lt_create.
    ENDLOOP.

    MODIFY ENTITIES OF zab_cds_i_bolt_lib IN LOCAL MODE
      ENTITY Library
        CREATE FIELDS ( LibCategory FileName FilePath SizeBytes Provenance Pushed PushMsg CommitSha )
        WITH lt_create
      MAPPED DATA(ls_mapped).

    APPEND VALUE #( %cid = ls_key-%cid
                    %msg = msg(
                             iv_severity = COND #( WHEN lv_pushed = abap_true THEN if_abap_behv_message=>severity-success
                                                ELSE if_abap_behv_message=>severity-warning )
                             iv_text     = |{ lines( lt_create ) } file(s) added to { zcl_ab_bolt_config=>library_subfolder( lv_category ) } - { lv_msg }| ) )
      TO reported-library.

    READ ENTITIES OF zab_cds_i_bolt_lib IN LOCAL MODE
      ENTITY Library ALL FIELDS
      WITH VALUE #( FOR ls_map IN ls_mapped-library ( %tky = ls_map-%tky ) )
      RESULT DATA(lt_new).
    result = VALUE #( FOR ls_new IN lt_new ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_new ) ) ).
  ENDMETHOD.

ENDCLASS.
