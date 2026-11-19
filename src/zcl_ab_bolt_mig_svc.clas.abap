"! <p class="shorttext synchronized">Bolt - migration workflow on GitHub</p>
"! Everything a migration does on GitHub, in one place. Same flows, headings
"! and texts as Bolt Console's routes/migrations.js + statusFile.js:
"!   push             branch + every legacy file + Queued status file (one commit)
"!   read_status      the branch's status file, parsed
"!   respond          confirm ("Manual activity confirmed" - the ONLY thing that
"!                    releases a WAITING_ON hand-off) / problem / question /
"!                    change / concern, with attachments
"!   set_stop         Stop requested / Resumed
"!   add_legacy_docs  more reference documents onto <branch>/
"!   ai_summary       plain-language summary of the legacy grab
"! The legacy files are produced HERE, on the system the app runs in - no
"! manual download: legacy grab snapshot (.md) + driver sources, the Smart Form
"! XML export, and every custom Smart Style the form uses.
"! No database writes: the RAP behaviour stores the results, so the same code
"! serves the Fiori app and the background job.
CLASS zcl_ab_bolt_mig_svc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_mig,
        form_name   TYPE string,
        form_descr  TYPE string,
        form_slug   TYPE string,
        branch_name TYPE string,
        serial_no   TYPE i,
        run_no      TYPE i,
        prev_branch TYPE string,
      END OF ty_mig.

    "! A file the user picked in the browser (base64 content).
    TYPES:
      BEGIN OF ty_upload,
        name    TYPE string,
        content TYPE string,
      END OF ty_upload,
      ty_t_upload TYPE STANDARD TABLE OF ty_upload WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_file_info,
        path TYPE string,
        name TYPE string,
        kind TYPE zabt_bolt_file-file_kind,
        size TYPE i,
      END OF ty_file_info,
      ty_t_file_info TYPE STANDARD TABLE OF ty_file_info WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_read,
        found   TYPE abap_bool,
        sha     TYPE string,
        status  TYPE zcl_ab_bolt_status_file=>ty_status,
        entries TYPE zcl_ab_bolt_status_file=>ty_t_entry,
      END OF ty_read.

    TYPES:
      BEGIN OF ty_build,
        files           TYPE zcl_ab_bolt_github=>ty_t_file,
        infos           TYPE ty_t_file_info,
        complexity      TYPE zabt_bolt_mig-complexity,
        complexity_info TYPE string,
        warnings        TYPE string_table,
      END OF ty_build.

    TYPES:
      BEGIN OF ty_push,
        commit_sha      TYPE string,
        adopted         TYPE abap_bool,
        files           TYPE ty_t_file_info,
        complexity      TYPE zabt_bolt_mig-complexity,
        complexity_info TYPE string,
        warnings        TYPE string_table,
        read            TYPE ty_read,
      END OF ty_push.

    TYPES:
      BEGIN OF ty_action,
        read       TYPE ty_read,
        files      TYPE ty_t_file_info,
        commit_sha TYPE string,
      END OF ty_action.

    "! Response kinds of the communication panel.
    CONSTANTS:
      BEGIN OF gc_kind,
        confirm  TYPE string VALUE `confirm`,
        problem  TYPE string VALUE `problem`,
        question TYPE string VALUE `question`,
        change   TYPE string VALUE `change`,
        concern  TYPE string VALUE `concern`,
      END OF gc_kind.

    CLASS-METHODS from_row
      IMPORTING is_row        TYPE zabt_bolt_mig
                iv_prev       TYPE string OPTIONAL
      RETURNING VALUE(rs_mig) TYPE ty_mig.

    "! Branch of a migration: <prefix>-<form>, and <prefix>-<form>-r<n> for a re-process run.
    CLASS-METHODS branch_for
      IMPORTING iv_form_name     TYPE csequence
                iv_run_no        TYPE i
                is_setup         TYPE zabt_bolt_setup
      RETURNING VALUE(rv_branch) TYPE string.

    "! Every legacy file of one form, produced on this system.
    CLASS-METHODS build_files
      IMPORTING is_mig          TYPE ty_mig
                is_setup        TYPE zabt_bolt_setup
      RETURNING VALUE(rs_build) TYPE ty_build
      RAISING   zcx_ab_bolt.

    CLASS-METHODS push
      IMPORTING is_mig         TYPE ty_mig
      RETURNING VALUE(rs_push) TYPE ty_push
      RAISING   zcx_ab_bolt.

    CLASS-METHODS read_status
      IMPORTING is_mig         TYPE ty_mig
      RETURNING VALUE(rs_read) TYPE ty_read
      RAISING   zcx_ab_bolt.

    "! iv_kind: confirm / problem / question / change / concern.
    CLASS-METHODS respond
      IMPORTING is_mig           TYPE ty_mig
                iv_kind          TYPE string
                iv_text          TYPE string OPTIONAL
                it_files         TYPE ty_t_upload OPTIONAL
      RETURNING VALUE(rs_action) TYPE ty_action
      RAISING   zcx_ab_bolt.

    CLASS-METHODS set_stop
      IMPORTING is_mig         TYPE ty_mig
                iv_stop        TYPE abap_bool
                iv_note        TYPE string OPTIONAL
      RETURNING VALUE(rs_read) TYPE ty_read
      RAISING   zcx_ab_bolt.

    "! Legacy documents added on the Migration page - same reference folder as
    "! at creation (<branch>/), one commit.
    CLASS-METHODS add_legacy_docs
      IMPORTING is_mig           TYPE ty_mig
                it_files         TYPE ty_t_upload
      RETURNING VALUE(rs_action) TYPE ty_action
      RAISING   zcx_ab_bolt.

    CLASS-METHODS ai_summary
      IMPORTING is_mig         TYPE ty_mig
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_ab_bolt.

    "! Files sent from the browser as JSON [{"name":"a.pdf","content":"<base64>"}].
    CLASS-METHODS parse_uploads
      IMPORTING iv_json         TYPE string
      RETURNING VALUE(rt_files) TYPE ty_t_upload
      RAISING   zcx_ab_bolt.

    "! Milliseconds since 1970 (JavaScript Date.now()) - the concerns/<ts> folder name.
    CLASS-METHODS epoch_ms
      RETURNING VALUE(rv_ms) TYPE string.

    "! History event of a response kind.
    CLASS-METHODS event_of
      IMPORTING iv_kind         TYPE string
      RETURNING VALUE(rv_event) TYPE zabt_bolt_hist-hist_event.

    CLASS-METHODS safe_name
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rv_name) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS status_path
      IMPORTING is_mig         TYPE ty_mig
      RETURNING VALUE(rv_path) TYPE string.

    CLASS-METHODS update_status
      IMPORTING is_mig         TYPE ty_mig
                iv_heading     TYPE string
                iv_entry_text  TYPE string
                is_change      TYPE zcl_ab_bolt_status_file=>ty_change OPTIONAL
      RETURNING VALUE(rs_read) TYPE ty_read
      RAISING   zcx_ab_bolt.

    "! Pushes files to <branch>/concerns/<ms>/ and returns the sentence to append
    "! to the status entry (attachConcernFiles in routes/migrations.js).
    CLASS-METHODS attach
      IMPORTING is_mig   TYPE ty_mig
                it_files TYPE ty_t_upload
      EXPORTING ev_note  TYPE string
                et_files TYPE ty_t_file_info
      RAISING   zcx_ab_bolt.

    CLASS-METHODS to_read
      IMPORTING is_content     TYPE zcl_ab_bolt_github=>ty_content
      RETURNING VALUE(rs_read) TYPE ty_read.

    CLASS-METHODS add_text_file
      IMPORTING iv_path  TYPE string
                iv_name  TYPE string
                iv_kind  TYPE zabt_bolt_file-file_kind
                iv_text  TYPE string
      CHANGING  cs_build TYPE ty_build.
ENDCLASS.



CLASS zcl_ab_bolt_mig_svc IMPLEMENTATION.

  METHOD from_row.
    rs_mig = VALUE #( form_name   = condense( CONV string( is_row-form_name ) )
                      form_descr  = condense( CONV string( is_row-form_descr ) )
                      form_slug   = condense( CONV string( is_row-form_slug ) )
                      branch_name = condense( CONV string( is_row-branch_name ) )
                      serial_no   = is_row-serial_no
                      run_no      = is_row-run_no
                      prev_branch = iv_prev ).
    IF rs_mig-form_slug IS INITIAL.
      rs_mig-form_slug = zcl_ab_bolt_status_file=>form_slug( rs_mig-form_name ).
    ENDIF.
  ENDMETHOD.


  METHOD branch_for.
    DATA(lv_name) = condense( CONV string( iv_form_name ) ).
    IF iv_run_no > 1.
      lv_name = |{ lv_name }-r{ iv_run_no }|.
    ENDIF.
    rv_branch = zcl_ab_bolt_status_file=>branch_name( iv_display_name = lv_name
                                                       iv_prefix       = condense( CONV string( is_setup-gh_branch_pfx ) ) ).
  ENDMETHOD.


  METHOD safe_name.
    rv_name = condense( iv_name ).
    REPLACE ALL OCCURRENCES OF REGEX '[\\/:*?"<>|]' IN rv_name WITH '_'.
    IF rv_name IS INITIAL.
      rv_name = `file`.
    ENDIF.
  ENDMETHOD.


  METHOD epoch_ms.
    DATA lv_ts   TYPE timestampl.
    DATA lv_date TYPE d.
    DATA lv_time TYPE t.
    DATA lv_ms   TYPE p LENGTH 16 DECIMALS 0.
    GET TIME STAMP FIELD lv_ts.
    CONVERT TIME STAMP lv_ts TIME ZONE 'UTC' INTO DATE lv_date TIME lv_time.
    DATA(lv_days)  = CONV decfloat34( lv_date - CONV d( '19700101' ) ).
    DATA(lv_secs)  = CONV decfloat34( lv_time - CONV t( '000000' ) ).
    DATA(lv_frac)  = CONV decfloat34( frac( lv_ts ) ).
    DATA(lv_total) = ( lv_days * 86400 + lv_secs + lv_frac ) * 1000.
    lv_ms = trunc( lv_total ).
    rv_ms = condense( |{ lv_ms }| ).
  ENDMETHOD.


  METHOD event_of.
    rv_event = SWITCH #( iv_kind
                 WHEN gc_kind-confirm  THEN zcl_ab_bolt_config=>gc_event-confirmed
                 WHEN gc_kind-problem  THEN zcl_ab_bolt_config=>gc_event-problem
                 WHEN gc_kind-question THEN zcl_ab_bolt_config=>gc_event-question
                 WHEN gc_kind-change   THEN zcl_ab_bolt_config=>gc_event-change
                 ELSE zcl_ab_bolt_config=>gc_event-concern ).
  ENDMETHOD.


  METHOD parse_uploads.
    IF iv_json IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        /ui2/cl_json=>deserialize( EXPORTING json        = iv_json
                                             pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                   CHANGING  data        = rt_files ).
      CATCH cx_root INTO DATA(lx_json) ##CATCH_ALL.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |The attached files could not be read: { lx_json->get_text( ) }| ).
    ENDTRY.
    DELETE rt_files WHERE content IS INITIAL.
  ENDMETHOD.


  METHOD status_path.
    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).
    rv_path = zcl_ab_bolt_status_file=>file_path(
                iv_form_slug = is_mig-form_slug
                iv_folder    = zcl_ab_bolt_config=>clean_folder( iv_folder  = ls_setup-status_folder
                                                                 iv_default = zcl_ab_bolt_config=>gc_default_status ) ).
  ENDMETHOD.


  METHOD to_read.
    rs_read-found = is_content-found.
    rs_read-sha   = is_content-sha.
    IF is_content-found = abap_true.
      rs_read-status  = zcl_ab_bolt_status_file=>parse( is_content-text ).
      rs_read-entries = zcl_ab_bolt_status_file=>timeline( rs_read-status-body ).
    ENDIF.
  ENDMETHOD.


  METHOD read_status.
    rs_read = to_read( zcl_ab_bolt_github=>from_setup( )->get_file( iv_branch = is_mig-branch_name
                                                                     iv_path   = status_path( is_mig ) ) ).
  ENDMETHOD.


  METHOD add_text_file.
    DATA(lv_data) = zcl_ab_bolt_github=>to_utf8( iv_text ).
    APPEND VALUE #( path = iv_path content = lv_data ) TO cs_build-files.
    APPEND VALUE #( path = iv_path name = iv_name kind = iv_kind size = xstrlen( lv_data ) ) TO cs_build-infos.
  ENDMETHOD.


  METHOD build_files.
    DATA(lv_form) = to_upper( is_mig-form_name ).
    IF zcl_ab_bolt_form_catalog=>get( lv_form ) IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |Smart Form { lv_form } does not exist on system { sy-sysid }.| ).
    ENDIF.
    zcl_ab_bolt_config=>prefixes( EXPORTING is_setup   = is_setup
                                  IMPORTING ev_prefix1 = DATA(lv_p1)
                                            ev_prefix2 = DATA(lv_p2) ).

    " 1. legacy grab: <FORM>.md snapshot + driver/include sources
    TRY.
        DATA(lo_grab) = NEW zcl_ab_bolt_legacy_grab( iv_prefix1      = lv_p1
                                                     iv_prefix2      = lv_p2
                                                     iv_count_volume = xsdbool( is_setup-count_volume = abap_true ) ).
        LOOP AT lo_grab->grab_form( lv_form ) INTO DATA(ls_grab).
          DATA(lv_name) = safe_name( ls_grab-name ).
          add_text_file( EXPORTING iv_path  = |{ is_mig-branch_name }/{ lv_name }|
                                   iv_name  = lv_name
                                   iv_kind  = COND #( WHEN ls_grab-kind = `DRIVER` THEN zcl_ab_bolt_config=>gc_kind-driver
                                                      ELSE zcl_ab_bolt_config=>gc_kind-snapshot )
                                   iv_text  = ls_grab-content
                         CHANGING  cs_build = rs_build ).
        ENDLOOP.
      CATCH cx_root INTO DATA(lx_grab) ##CATCH_ALL.
        APPEND |Legacy grab of { lv_form } failed: { lx_grab->get_text( ) }| TO rs_build-warnings.
    ENDTRY.

    " 2. the Smart Form itself - same XML as SMARTFORMS > Utilities > Download Form
    DATA lv_xml TYPE string.
    TRY.
        lv_xml = zcl_ab_bolt_form_export=>export_xml( lv_form ).
        lv_name = |{ to_lower( translate( val = lv_form from = `/` to = `_` ) ) }.xml|.
        add_text_file( EXPORTING iv_path  = |{ is_mig-branch_name }/{ lv_name }|
                                 iv_name  = lv_name
                                 iv_kind  = zcl_ab_bolt_config=>gc_kind-xml
                                 iv_text  = lv_xml
                       CHANGING  cs_build = rs_build ).
        DATA(ls_signal) = zcl_ab_bolt_form_export=>complexity( lv_xml ).
        IF ls_signal-ok = abap_true.
          rs_build-complexity      = ls_signal-level.
          rs_build-complexity_info = ls_signal-headline.
        ENDIF.
      CATCH cx_root INTO DATA(lx_xml) ##CATCH_ALL.
        APPEND |Smart Form XML export failed ({ lx_xml->get_text( ) }).| TO rs_build-warnings.
    ENDTRY.

    " 3. every custom Smart Style the form uses
    IF lv_xml IS NOT INITIAL.
      LOOP AT zcl_ab_bolt_form_export=>styles_used( iv_xml = lv_xml iv_prefix1 = lv_p1 iv_prefix2 = lv_p2 ) INTO DATA(lv_style).
        TRY.
            lv_name = |style_{ to_lower( translate( val = lv_style from = `/` to = `_` ) ) }.xml|.
            add_text_file( EXPORTING iv_path  = |{ is_mig-branch_name }/{ lv_name }|
                                     iv_name  = lv_name
                                     iv_kind  = zcl_ab_bolt_config=>gc_kind-style
                                     iv_text  = zcl_ab_bolt_form_export=>export_style( lv_style )
                           CHANGING  cs_build = rs_build ).
          CATCH zcx_ab_bolt INTO DATA(lx_style).
            APPEND lx_style->get_text( ) TO rs_build-warnings.
        ENDTRY.
      ENDLOOP.
    ENDIF.

    IF rs_build-files IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt(
        iv_text = |No legacy files could be produced for { lv_form }: { concat_lines_of( table = rs_build-warnings sep = ` ` ) }| ).
    ENDIF.
  ENDMETHOD.


  METHOD push.
    DATA(ls_setup)  = zcl_ab_bolt_config=>get_setup( ).
    DATA(lo_github) = zcl_ab_bolt_github=>from_setup( ).
    DATA(lv_status_path) = status_path( is_mig ).

    " A branch of this name already there: ours from an earlier attempt whose
    " save did not finish (adopt it), or someone else's (refuse - never overwrite).
    IF lo_github->get_branch_sha( is_mig-branch_name ) IS NOT INITIAL.
      DATA(ls_existing) = lo_github->get_file( iv_branch = is_mig-branch_name iv_path = lv_status_path ).
      IF ls_existing-found = abap_true.
        rs_push-adopted = abap_true.
        rs_push-read    = to_read( ls_existing ).
        RETURN.
      ENDIF.
      RAISE EXCEPTION NEW zcx_ab_bolt(
        iv_text = |A branch named "{ is_mig-branch_name }" already exists in the repository but has no status file - | &&
                  |it was not created by this app and was left untouched. Stop this migration, or remove that branch on GitHub.| ).
    ENDIF.

    DATA(ls_build) = build_files( is_mig = is_mig is_setup = ls_setup ).
    rs_push-files           = ls_build-infos.
    rs_push-complexity      = ls_build-complexity.
    rs_push-complexity_info = ls_build-complexity_info.
    rs_push-warnings        = ls_build-warnings.

    " The Queued status file - in the SAME commit, so the branch never exists without it.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    DATA(lv_entry) = |Migration submitted with { lines( ls_build-infos ) } reference file(s).|.
    IF is_mig-run_no > 1.
      lv_entry = |{ lv_entry }{ lv_nl }{ lv_nl }Re-process run { is_mig-run_no } of { is_mig-form_name }| &&
                 |{ COND string( WHEN is_mig-prev_branch IS NOT INITIAL THEN | - the previous run on branch { is_mig-prev_branch } was stopped| ) }.|.
    ENDIF.
    lv_entry = |{ lv_entry }{ lv_nl }{ lv_nl }Sent by Bolt with Fiori from SAP system { sy-sysid } client { sy-mandt } | &&
               |by user { sy-uname } (serial no. { is_mig-serial_no }).|.
    IF rs_push-complexity IS NOT INITIAL.
      lv_entry = |{ lv_entry }{ lv_nl }Early complexity signal: { to_upper( rs_push-complexity ) } - { rs_push-complexity_info } | &&
                 |(structural read of the layout only - not the full risk score).|.
    ENDIF.
    LOOP AT rs_push-warnings INTO DATA(lv_warning).
      lv_entry = |{ lv_entry }{ lv_nl }Warning: { lv_warning }|.
    ENDLOOP.
    DATA(lv_status_text) = zcl_ab_bolt_status_file=>append_entry(
      iv_existing   = ``
      iv_title      = is_mig-form_name
      iv_heading    = `Queued`
      iv_entry_text = lv_entry
      is_change     = VALUE #( status     = `queued`   set_status     = abap_true
                               waiting_on = `engineer` set_waiting_on = abap_true
                               note       = `Waiting for the migration engineer to pick this up.` set_note = abap_true ) ).
    DATA(lt_files) = ls_build-files.
    DATA(lv_status_data) = zcl_ab_bolt_github=>to_utf8( lv_status_text ).
    APPEND VALUE #( path = lv_status_path content = lv_status_data ) TO lt_files.
    APPEND VALUE #( path = lv_status_path name = |{ is_mig-form_slug }_status.md|
                    kind = zcl_ab_bolt_config=>gc_kind-status size = xstrlen( lv_status_data ) ) TO rs_push-files.

    DATA(lv_base) = condense( CONV string( ls_setup-gh_base_branch ) ).
    IF lv_base IS INITIAL.
      lv_base = lo_github->default_branch( ).
    ENDIF.
    rs_push-commit_sha = lo_github->create_branch_with_files(
      iv_base_branch = lv_base
      iv_branch      = is_mig-branch_name
      it_files       = lt_files
      iv_message     = |Add reference documents for { is_mig-form_name }| ).

    rs_push-read-found   = abap_true.
    rs_push-read-status  = zcl_ab_bolt_status_file=>parse( lv_status_text ).
    rs_push-read-entries = zcl_ab_bolt_status_file=>timeline( rs_push-read-status-body ).
  ENDMETHOD.


  METHOD update_status.
    DATA(lo_github) = zcl_ab_bolt_github=>from_setup( ).
    DATA(lv_path) = status_path( is_mig ).

    " Read-modify-write with the blob SHA: if the engineer (or another user)
    " wrote in between, GitHub refuses and we re-apply on the fresh copy.
    DO 3 TIMES.
      DATA(ls_content) = lo_github->get_file( iv_branch = is_mig-branch_name iv_path = lv_path ).
      DATA(lv_text) = zcl_ab_bolt_status_file=>append_entry(
        iv_existing   = COND #( WHEN ls_content-found = abap_true THEN ls_content-text )
        iv_title      = is_mig-form_name
        iv_heading    = iv_heading
        iv_entry_text = iv_entry_text
        is_change     = is_change ).
      DATA(lv_conflict) = lo_github->put_file( iv_branch  = is_mig-branch_name
                                               iv_path    = lv_path
                                               iv_text    = lv_text
                                               iv_sha     = ls_content-sha
                                               iv_message = |Status: { iv_heading }| ).
      IF lv_conflict = abap_false.
        rs_read = to_read( lo_github->get_file( iv_branch = is_mig-branch_name iv_path = lv_path ) ).
        RETURN.
      ENDIF.
    ENDDO.
    RAISE EXCEPTION NEW zcx_ab_bolt(
      iv_text = `The status file kept changing while saving (three attempts) - refresh and try again.` ).
  ENDMETHOD.


  METHOD attach.
    DATA lt_push  TYPE zcl_ab_bolt_github=>ty_t_file.
    DATA lt_names TYPE string_table.

    CLEAR: ev_note, et_files.
    IF it_files IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_folder) = |{ is_mig-branch_name }/concerns/{ epoch_ms( ) }|.
    LOOP AT it_files INTO DATA(ls_upload).
      DATA(lv_name) = safe_name( ls_upload-name ).
      DATA(lv_data) = cl_http_utility=>decode_x_base64( ls_upload-content ).
      APPEND VALUE #( path = |{ lv_folder }/{ lv_name }| content = lv_data ) TO lt_push.
      APPEND VALUE #( path = |{ lv_folder }/{ lv_name }| name = lv_name
                      kind = zcl_ab_bolt_config=>gc_kind-attach size = xstrlen( lv_data ) ) TO et_files.
      APPEND lv_name TO lt_names.
    ENDLOOP.
    DATA(lv_list) = concat_lines_of( table = lt_names sep = `, ` ).
    DATA(lv_nl2) = |{ cl_abap_char_utilities=>newline }{ cl_abap_char_utilities=>newline }|.
    TRY.
        zcl_ab_bolt_github=>from_setup( )->add_files(
          iv_branch  = is_mig-branch_name
          it_files   = lt_push
          iv_message = |Attach { lines( lt_push ) } file(s) to a concern on { is_mig-form_name }| ).
        ev_note = |{ lv_nl2 }Attached: { lv_list } (pushed to `{ lv_folder }/`)|.
      CATCH zcx_ab_bolt INTO DATA(lx_push).
        " Same fallback text as the web app: the message still goes through.
        ev_note = |{ lv_nl2 }Attached in Bolt with Fiori: { lv_list } - couldn't push to the branch: { lx_push->get_text( ) }|.
        CLEAR et_files.
    ENDTRY.
  ENDMETHOD.


  METHOD respond.
    DATA lv_attached TYPE string.

    DATA(lv_kind) = to_lower( condense( iv_kind ) ).
    DATA(lv_text) = zcl_ab_bolt_status_file=>trim( iv_text ).

    IF lv_kind = gc_kind-confirm.
      DATA(ls_current) = read_status( is_mig ).
      IF ls_current-status-stop = abap_true.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `This migration is stopped. Resume it first.` ).
      ENDIF.
      IF ls_current-status-waiting_on IS INITIAL OR ls_current-status-waiting_on = `engineer`.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Nothing is waiting for your confirmation right now.` ).
      ENDIF.
    ELSEIF lv_text IS INITIAL AND it_files IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Type your concern first.` ).
    ENDIF.

    attach( EXPORTING is_mig   = is_mig
                      it_files = it_files
            IMPORTING ev_note  = lv_attached
                      et_files = rs_action-files ).

    IF lv_kind = gc_kind-confirm.
      DATA(lv_note) = zcl_ab_bolt_status_file=>trim( |{ lv_text }{ lv_attached }| ).
      rs_action-read = update_status(
        is_mig        = is_mig
        iv_heading    = `Manual activity confirmed`
        iv_entry_text = COND #( WHEN lv_note IS NOT INITIAL
                                THEN |Client confirmed the manual step is done: { lv_note }|
                                ELSE `Client confirmed the manual step is done.` )
        is_change     = VALUE #( status     = `in_progress` set_status     = abap_true
                                 waiting_on = `engineer`    set_waiting_on = abap_true
                                 note       = ``            set_note       = abap_true ) ).
      RETURN.
    ENDIF.

    rs_action-read = update_status(
      is_mig        = is_mig
      iv_heading    = SWITCH #( lv_kind
                        WHEN gc_kind-problem  THEN `Problem reported`
                        WHEN gc_kind-question THEN `Question`
                        WHEN gc_kind-change   THEN `Change requested`
                        ELSE `Concern raised` )
      iv_entry_text = zcl_ab_bolt_status_file=>trim( |{ lv_text }{ lv_attached }| )
      is_change     = VALUE #( status     = `open_for_concerns` set_status     = abap_true
                               waiting_on = `engineer`          set_waiting_on = abap_true
                               note       = ``                  set_note       = abap_true ) ).
  ENDMETHOD.


  METHOD set_stop.
    DATA(lv_note) = zcl_ab_bolt_status_file=>trim( iv_note ).
    rs_read = update_status(
      is_mig        = is_mig
      iv_heading    = COND #( WHEN iv_stop = abap_true THEN `Stop requested` ELSE `Resumed` )
      iv_entry_text = COND #( WHEN iv_stop = abap_false THEN `Client resumed the migration.`
                              WHEN lv_note IS NOT INITIAL THEN |Client requested a stop: { lv_note }|
                              ELSE `Client requested a stop. No further migration activity should proceed until resumed.` )
      is_change     = VALUE #( stop = iv_stop set_stop = abap_true ) ).
  ENDMETHOD.


  METHOD add_legacy_docs.
    DATA lt_push TYPE zcl_ab_bolt_github=>ty_t_file.

    IF it_files IS INITIAL.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Choose at least one file.` ).
    ENDIF.
    LOOP AT it_files INTO DATA(ls_upload).
      DATA(lv_name) = safe_name( ls_upload-name ).
      DATA(lv_data) = cl_http_utility=>decode_x_base64( ls_upload-content ).
      APPEND VALUE #( path = |{ is_mig-branch_name }/{ lv_name }| content = lv_data ) TO lt_push.
      APPEND VALUE #( path = |{ is_mig-branch_name }/{ lv_name }| name = lv_name
                      kind = zcl_ab_bolt_config=>gc_kind-legacy size = xstrlen( lv_data ) ) TO rs_action-files.
    ENDLOOP.
    rs_action-commit_sha = zcl_ab_bolt_github=>from_setup( )->add_files(
      iv_branch  = is_mig-branch_name
      it_files   = lt_push
      iv_message = |Add reference documents for { is_mig-form_name }| ).
  ENDMETHOD.


  METHOD ai_summary.
    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).
    DATA(ls_snapshot) = zcl_ab_bolt_github=>from_setup( )->get_file(
                          iv_branch = is_mig-branch_name
                          iv_path   = |{ is_mig-branch_name }/{ is_mig-form_name }.md| ).
    IF ls_snapshot-found = abap_false.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |The legacy-grab snapshot { is_mig-form_name }.md is not on the branch.| ).
    ENDIF.
    DATA(lv_grab) = ls_snapshot-text.
    IF strlen( lv_grab ) > 60000.
      lv_grab = substring( val = lv_grab len = 60000 ).
    ENDIF.
    rv_text = zcl_ab_bolt_ai=>complete(
      is_setup  = ls_setup
      iv_prompt = |You are helping a business user understand a SAP Smart Form that is being migrated to an Adobe Form. | &&
                  |Below is the automatic legacy-grab snapshot of the form { is_mig-form_name }. In plain language and | &&
                  |at most 8 short bullet points, explain: what the form is for, which data it prints, which program | &&
                  |prints it, how complex the migration looks and what needs the business's attention. | &&
                  |Do not invent anything that is not in the snapshot.| &&
                  |{ cl_abap_char_utilities=>newline }{ cl_abap_char_utilities=>newline }{ lv_grab }| ).
  ENDMETHOD.

ENDCLASS.
