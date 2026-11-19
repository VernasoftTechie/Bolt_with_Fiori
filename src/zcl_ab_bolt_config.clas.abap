"! <p class="shorttext synchronized">Bolt - configuration access and shared constants</p>
"! Read-only access to the setup row (ZABT_BOLT_SETUP) and the stored secrets
"! (ZABT_BOLT_SECRT), plus the constants every other class uses. Writes happen
"! only through the RAP business object ZAB_CDS_I_BOLT_SETUP.
"!
"! Nothing client-specific is hard-coded: every value a client could differ in
"! (client name, repository, branch prefix, folders, GitHub/AI endpoints,
"! Smart Form name prefixes, administrators) lives in the setup row and is
"! maintained on the Setup page. The defaults below are only what a
"! brand-new setup row starts with.
CLASS zcl_ab_bolt_config DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      gc_setup_id        TYPE zabt_bolt_setup-setup_id      VALUE 'DEFAULT',
      gc_default_api     TYPE zabt_bolt_setup-gh_api_url    VALUE 'https://api.github.com',
      gc_default_ssl_id  TYPE zabt_bolt_setup-ssl_id        VALUE 'ANONYM',
      gc_default_prefix  TYPE zabt_bolt_setup-gh_branch_pfx VALUE 'vernasofttechie',
      gc_default_status  TYPE zabt_bolt_setup-status_folder VALUE 'docs/legacy_grab',
      gc_default_library TYPE zabt_bolt_setup-lib_folder    VALUE 'docs/global_data',
      gc_default_forms   TYPE zabt_bolt_setup-form_prefixes VALUE 'Z,Y',
      gc_default_tokens  TYPE zabt_bolt_setup-ai_max_tokens VALUE 4096.

    CONSTANTS:
      BEGIN OF gc_secret,
        github_token TYPE zabt_bolt_secrt-secret_id VALUE 'GITHUB_TOKEN',
        ai_key       TYPE zabt_bolt_secrt-secret_id VALUE 'AI_KEY',
      END OF gc_secret.

    CONSTANTS:
      BEGIN OF gc_check,
        ok    TYPE zabt_bolt_setup-gh_check_res VALUE 'OK',
        error TYPE zabt_bolt_setup-gh_check_res VALUE 'ERROR',
      END OF gc_check.

    CONSTANTS:
      BEGIN OF gc_provider,
        mock      TYPE zabt_bolt_setup-ai_provider VALUE 'mock',
        openai    TYPE zabt_bolt_setup-ai_provider VALUE 'openai',
        anthropic TYPE zabt_bolt_setup-ai_provider VALUE 'anthropic',
      END OF gc_provider.

    CONSTANTS:
      BEGIN OF gc_push,
        pending TYPE zabt_bolt_mig-push_status VALUE 'PENDING',
        pushed  TYPE zabt_bolt_mig-push_status VALUE 'PUSHED',
        failed  TYPE zabt_bolt_mig-push_status VALUE 'FAILED',
      END OF gc_push.

    "! Status values of the branch status file (statusParse.js STATUS_LABELS).
    CONSTANTS:
      BEGIN OF gc_status,
        queued              TYPE zabt_bolt_mig-mig_status VALUE 'queued',
        in_progress         TYPE zabt_bolt_mig-mig_status VALUE 'in_progress',
        interface_completed TYPE zabt_bolt_mig-mig_status VALUE 'interface_completed',
        waiting_manual      TYPE zabt_bolt_mig-mig_status VALUE 'waiting_manual',
        layout_in_progress  TYPE zabt_bolt_mig-mig_status VALUE 'layout_in_progress',
        completed           TYPE zabt_bolt_mig-mig_status VALUE 'completed',
        open_for_concerns   TYPE zabt_bolt_mig-mig_status VALUE 'open_for_concerns',
      END OF gc_status.

    CONSTANTS:
      BEGIN OF gc_event,
        committed    TYPE zabt_bolt_hist-hist_event VALUE 'COMMITTED',
        pushed       TYPE zabt_bolt_hist-hist_event VALUE 'PUSHED',
        push_failed  TYPE zabt_bolt_hist-hist_event VALUE 'PUSH_FAILED',
        status       TYPE zabt_bolt_hist-hist_event VALUE 'STATUS',
        confirmed    TYPE zabt_bolt_hist-hist_event VALUE 'CONFIRMED',
        problem      TYPE zabt_bolt_hist-hist_event VALUE 'PROBLEM',
        question     TYPE zabt_bolt_hist-hist_event VALUE 'QUESTION',
        change       TYPE zabt_bolt_hist-hist_event VALUE 'CHANGE',
        concern      TYPE zabt_bolt_hist-hist_event VALUE 'CONCERN',
        stopped      TYPE zabt_bolt_hist-hist_event VALUE 'STOPPED',
        resumed      TYPE zabt_bolt_hist-hist_event VALUE 'RESUMED',
        docs_added   TYPE zabt_bolt_hist-hist_event VALUE 'DOCS_ADDED',
        docs_removed TYPE zabt_bolt_hist-hist_event VALUE 'DOCS_REMOVED',
        reprocessed  TYPE zabt_bolt_hist-hist_event VALUE 'REPROCESSED',
      END OF gc_event.

    CONSTANTS:
      BEGIN OF gc_actor,
        client   TYPE zabt_bolt_hist-actor VALUE 'CLIENT',
        engineer TYPE zabt_bolt_hist-actor VALUE 'ENGINEER',
        system   TYPE zabt_bolt_hist-actor VALUE 'SYSTEM',
      END OF gc_actor.

    CONSTANTS:
      BEGIN OF gc_kind,
        snapshot TYPE zabt_bolt_file-file_kind VALUE 'SNAPSHOT',
        xml      TYPE zabt_bolt_file-file_kind VALUE 'XML',
        style    TYPE zabt_bolt_file-file_kind VALUE 'STYLE',
        driver   TYPE zabt_bolt_file-file_kind VALUE 'DRIVER',
        status   TYPE zabt_bolt_file-file_kind VALUE 'STATUS',
        legacy   TYPE zabt_bolt_file-file_kind VALUE 'LEGACY',
        attach   TYPE zabt_bolt_file-file_kind VALUE 'ATTACH',
      END OF gc_kind.

    "! The setup row with every blank convention filled with its default.
    "! Initial SETUP_ID = the app was never set up on this system.
    CLASS-METHODS get_setup
      RETURNING VALUE(rs_setup) TYPE zabt_bolt_setup.

    "! A brand-new setup row (what the Setup page starts with).
    CLASS-METHODS default_setup
      RETURNING VALUE(rs_setup) TYPE zabt_bolt_setup.

    "! True when ADMIN_USERS is blank (first set-up: everybody may configure)
    "! or lists the user. Replaces the web app's admin password.
    CLASS-METHODS is_admin
      IMPORTING iv_user         TYPE syuname DEFAULT sy-uname
      RETURNING VALUE(rv_admin) TYPE abap_bool.

    CLASS-METHODS get_secret
      IMPORTING iv_secret_id    TYPE zabt_bolt_secrt-secret_id
      RETURNING VALUE(rv_value) TYPE string.

    "! Stored form of a secret: base64 of the UTF-8 bytes, so it is not legible
    "! at a glance in SE16. Not encryption - protect the table (S_TABU_NAM), see
    "! docs/03_client_connectivity.md.
    CLASS-METHODS encode_secret
      IMPORTING iv_value       TYPE string
      RETURNING VALUE(rv_code) TYPE string.

    CLASS-METHODS decode_secret
      IMPORTING iv_code         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS now
      RETURNING VALUE(rv_ts) TYPE timestampl.

    "! Current UTC time as 2026-11-18T10:42:00.123Z (same as JavaScript toISOString).
    CLASS-METHODS iso_now
      RETURNING VALUE(rv_iso) TYPE string.

    "! First and second custom Smart Form name prefix of the setup (default Z and Y).
    CLASS-METHODS prefixes
      IMPORTING is_setup   TYPE zabt_bolt_setup
      EXPORTING ev_prefix1 TYPE string
                ev_prefix2 TYPE string.

    "! Library sub-folder of a category - the same folders the web app used.
    CLASS-METHODS library_subfolder
      IMPORTING iv_category      TYPE zabt_bolt_lib-lib_category
      RETURNING VALUE(rv_folder) TYPE string.

    "! Message variables for RAP messages with standard message 00(001)
    "! ("&1&2&3&4..."): new_message_with_text keeps only 50 characters, this
    "! carries up to 200. A blank at a 50-character boundary becomes a
    "! non-breaking space (it would be lost in the substitution); longer texts
    "! end with an ellipsis.
    CLASS-METHODS msg_vars
      IMPORTING iv_text TYPE csequence
      EXPORTING ev_v1   TYPE symsgv
                ev_v2   TYPE symsgv
                ev_v3   TYPE symsgv
                ev_v4   TYPE symsgv.

    "! Removes blanks and trailing slashes from a repository folder setting.
    CLASS-METHODS clean_folder
      IMPORTING iv_folder        TYPE csequence
                iv_default       TYPE csequence
      RETURNING VALUE(rv_folder) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_ab_bolt_config IMPLEMENTATION.

  METHOD default_setup.
    rs_setup = VALUE #( setup_id      = gc_setup_id
                        gh_api_url    = gc_default_api
                        ssl_id        = gc_default_ssl_id
                        gh_branch_pfx = gc_default_prefix
                        status_folder = gc_default_status
                        lib_folder    = gc_default_library
                        ai_provider   = gc_provider-mock
                        ai_max_tokens = gc_default_tokens
                        form_prefixes = gc_default_forms
                        count_volume  = abap_true ).
  ENDMETHOD.


  METHOD get_setup.
    SELECT SINGLE * FROM zabt_bolt_setup
      WHERE setup_id = @gc_setup_id
      INTO @rs_setup.
    IF sy-subrc <> 0.
      CLEAR rs_setup.
      RETURN.
    ENDIF.
    DATA(ls_default) = default_setup( ).
    IF rs_setup-gh_api_url IS INITIAL.
      rs_setup-gh_api_url = ls_default-gh_api_url.
    ENDIF.
    IF rs_setup-ssl_id IS INITIAL.
      rs_setup-ssl_id = ls_default-ssl_id.
    ENDIF.
    IF rs_setup-status_folder IS INITIAL.
      rs_setup-status_folder = ls_default-status_folder.
    ENDIF.
    IF rs_setup-lib_folder IS INITIAL.
      rs_setup-lib_folder = ls_default-lib_folder.
    ENDIF.
    IF rs_setup-form_prefixes IS INITIAL.
      rs_setup-form_prefixes = ls_default-form_prefixes.
    ENDIF.
    IF rs_setup-ai_provider IS INITIAL.
      rs_setup-ai_provider = ls_default-ai_provider.
    ENDIF.
    IF rs_setup-ai_max_tokens <= 0.
      rs_setup-ai_max_tokens = ls_default-ai_max_tokens.
    ENDIF.
  ENDMETHOD.


  METHOD is_admin.
    SELECT SINGLE admin_users FROM zabt_bolt_setup
      WHERE setup_id = @gc_setup_id
      INTO @DATA(lv_admins).
    DATA(lv_list) = condense( to_upper( CONV string( lv_admins ) ) ).
    IF lv_list IS INITIAL.
      rv_admin = abap_true.
      RETURN.
    ENDIF.
    SPLIT lv_list AT ',' INTO TABLE DATA(lt_users).
    DATA(lv_me) = to_upper( CONV string( iv_user ) ).
    LOOP AT lt_users INTO DATA(lv_user).
      IF condense( lv_user ) = lv_me.
        rv_admin = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
    rv_admin = abap_false.
  ENDMETHOD.


  METHOD get_secret.
    SELECT SINGLE secret_value FROM zabt_bolt_secrt
      WHERE secret_id = @iv_secret_id
      INTO @DATA(lv_code).
    IF sy-subrc <> 0.
      CLEAR rv_value.
      RETURN.
    ENDIF.
    rv_value = decode_secret( lv_code ).
  ENDMETHOD.


  METHOD encode_secret.
    IF iv_value IS INITIAL.
      CLEAR rv_code.
      RETURN.
    ENDIF.
    rv_code = cl_http_utility=>encode_x_base64(
                cl_abap_codepage=>convert_to( source = iv_value codepage = `UTF-8` ) ).
  ENDMETHOD.


  METHOD decode_secret.
    IF iv_code IS INITIAL.
      CLEAR rv_value.
      RETURN.
    ENDIF.
    TRY.
        rv_value = cl_abap_codepage=>convert_from( source   = cl_http_utility=>decode_x_base64( iv_code )
                                                   codepage = `UTF-8` ).
      CATCH cx_root ##CATCH_ALL.
        CLEAR rv_value.
    ENDTRY.
  ENDMETHOD.


  METHOD now.
    GET TIME STAMP FIELD rv_ts.
  ENDMETHOD.


  METHOD iso_now.
    DATA lv_ts  TYPE timestampl.
    DATA lv_txt TYPE c LENGTH 30.
    GET TIME STAMP FIELD lv_ts.
    lv_txt = |{ lv_ts DECIMALS = 3 }|.
    CONDENSE lv_txt NO-GAPS.
    rv_iso = |{ lv_txt(4) }-{ lv_txt+4(2) }-{ lv_txt+6(2) }T{ lv_txt+8(2) }:{ lv_txt+10(2) }:{ lv_txt+12(2) }.{ lv_txt+15(3) }Z|.
  ENDMETHOD.


  METHOD prefixes.
    DATA(lv_list) = condense( to_upper( CONV string( is_setup-form_prefixes ) ) ).
    IF lv_list IS INITIAL.
      lv_list = gc_default_forms.
    ENDIF.
    SPLIT lv_list AT ',' INTO ev_prefix1 ev_prefix2.
    ev_prefix1 = condense( ev_prefix1 ).
    ev_prefix2 = condense( ev_prefix2 ).
    IF ev_prefix1 IS INITIAL.
      ev_prefix1 = `Z`.
    ENDIF.
  ENDMETHOD.


  METHOD library_subfolder.
    rv_folder = SWITCH #( iv_category
                  WHEN 'logo'            THEN `logos`
                  WHEN 'smartstyle'      THEN `styles`
                  WHEN 'naming_standard' THEN `naming_standards`
                  WHEN 'policy'          THEN `policies`
                  ELSE `other` ).
  ENDMETHOD.


  METHOD msg_vars.
    DATA lt_parts TYPE STANDARD TABLE OF symsgv WITH EMPTY KEY.

    CLEAR: ev_v1, ev_v2, ev_v3, ev_v4.
    DATA(lv_nbsp) = cl_abap_conv_in_ce=>uccp( '00A0' ).
    DATA(lv_text) = condense( CONV string( iv_text ) ).
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_text WITH ` `.
    IF strlen( lv_text ) > 200.
      lv_text = substring( val = lv_text len = 199 ) && cl_abap_conv_in_ce=>uccp( '2026' ).
    ENDIF.

    DATA(lv_off) = 0.
    WHILE lv_off < strlen( lv_text ) AND lines( lt_parts ) < 4.
      DATA(lv_len) = nmin( val1 = 50 val2 = strlen( lv_text ) - lv_off ).
      DATA(lv_part) = substring( val = lv_text off = lv_off len = lv_len ).
      " Blanks at either end of a part would be dropped by the substitution.
      IF substring( val = lv_part len = 1 ) = ` `.
        lv_part = lv_nbsp && substring( val = lv_part off = 1 ).
      ENDIF.
      IF strlen( lv_part ) > 1 AND substring( val = lv_part off = strlen( lv_part ) - 1 len = 1 ) = ` `.
        lv_part = substring( val = lv_part len = strlen( lv_part ) - 1 ) && lv_nbsp.
      ENDIF.
      APPEND CONV symsgv( lv_part ) TO lt_parts.
      lv_off += lv_len.
    ENDWHILE.

    ev_v1 = VALUE #( lt_parts[ 1 ] OPTIONAL ).
    ev_v2 = VALUE #( lt_parts[ 2 ] OPTIONAL ).
    ev_v3 = VALUE #( lt_parts[ 3 ] OPTIONAL ).
    ev_v4 = VALUE #( lt_parts[ 4 ] OPTIONAL ).
  ENDMETHOD.


  METHOD clean_folder.
    rv_folder = condense( CONV string( iv_folder ) ).
    WHILE rv_folder IS NOT INITIAL AND substring( val = rv_folder off = strlen( rv_folder ) - 1 len = 1 ) = `/`.
      rv_folder = substring( val = rv_folder len = strlen( rv_folder ) - 1 ).
    ENDWHILE.
    WHILE rv_folder IS NOT INITIAL AND substring( val = rv_folder len = 1 ) = `/`.
      rv_folder = substring( val = rv_folder off = 1 ).
    ENDWHILE.
    IF rv_folder IS INITIAL.
      rv_folder = condense( CONV string( iv_default ) ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
