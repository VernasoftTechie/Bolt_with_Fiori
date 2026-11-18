"! <p class="shorttext synchronized">Bolt with Fiori - migration workflow on GitHub</p>
"! Everything a migration does on GitHub, in one place - the same flows as
"! Bolt Console's routes/migrations.js + statusFile.js:
"!   push            branch + reference files + Queued status file (one commit)
"!   read_status     the branch's status file, parsed
"!   confirm         "Manual activity confirmed" - the ONLY thing that releases
"!                   a WAITING_ON hand-off (rulebook s16 gate)
"!   concern         problem / question / change / concern
"!   set_stop        Stop requested / Resumed
"!   add_reference_file, delete_branch, import_branches, ai_summary
"! No database writes here: the RAP behaviour (ZBP_I_BOLT_MIGRATION) stores
"! the results, so the same code serves the Fiori app and the background job.
CLASS zcl_bolt_migration_svc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_mig,
        form_name   TYPE string,
        system_id   TYPE zbolt_system-system_id,
        branch_name TYPE string,
        form_slug   TYPE string,
        serial_no   TYPE i,
      END OF ty_mig.

    TYPES:
      BEGIN OF ty_file_info,
        path TYPE string,
        name TYPE string,
        kind TYPE string,
        size TYPE i,
      END OF ty_file_info,
      ty_t_file_info TYPE STANDARD TABLE OF ty_file_info WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_read,
        found   TYPE abap_bool,
        sha     TYPE string,
        status  TYPE zcl_bolt_status_file=>ty_status,
        entries TYPE zcl_bolt_status_file=>ty_t_entry,
      END OF ty_read.

    TYPES:
      BEGIN OF ty_push,
        commit_sha      TYPE string,
        adopted         TYPE abap_bool,
        files           TYPE ty_t_file_info,
        complexity      TYPE string,
        complexity_text TYPE string,
        warnings        TYPE string_table,
        read            TYPE ty_read,
      END OF ty_push.

    TYPES:
      BEGIN OF ty_action,
        read  TYPE ty_read,
        files TYPE ty_t_file_info,
      END OF ty_action.

    TYPES:
      BEGIN OF ty_import,
        branch_name TYPE string,
        form_name   TYPE string,
        form_slug   TYPE string,
        read        TYPE ty_read,
      END OF ty_import,
      ty_t_import TYPE STANDARD TABLE OF ty_import WITH EMPTY KEY.

    CLASS-METHODS push
      IMPORTING is_mig         TYPE ty_mig
      RETURNING VALUE(rs_push) TYPE ty_push
      RAISING   zcx_bolt.

    CLASS-METHODS read_status
      IMPORTING is_mig         TYPE ty_mig
      RETURNING VALUE(rs_read) TYPE ty_read
      RAISING   zcx_bolt.

    CLASS-METHODS confirm
      IMPORTING is_mig           TYPE ty_mig
                iv_note          TYPE string OPTIONAL
                iv_file_name     TYPE string OPTIONAL
                iv_file_b64      TYPE string OPTIONAL
      RETURNING VALUE(rs_action) TYPE ty_action
      RAISING   zcx_bolt.

    "! iv_kind: problem / question / change / anything else = concern.
    CLASS-METHODS concern
      IMPORTING is_mig           TYPE ty_mig
                iv_kind          TYPE string OPTIONAL
                iv_text          TYPE string OPTIONAL
                iv_file_name     TYPE string OPTIONAL
                iv_file_b64      TYPE string OPTIONAL
      RETURNING VALUE(rs_action) TYPE ty_action
      RAISING   zcx_bolt.

    CLASS-METHODS set_stop
      IMPORTING is_mig         TYPE ty_mig
                iv_stop        TYPE abap_bool
                iv_note        TYPE string OPTIONAL
      RETURNING VALUE(rs_read) TYPE ty_read
      RAISING   zcx_bolt.

    CLASS-METHODS add_reference_file
      IMPORTING is_mig         TYPE ty_mig
                iv_file_name   TYPE string
                iv_file_b64    TYPE string
      RETURNING VALUE(rs_file) TYPE ty_file_info
      RAISING   zcx_bolt.

    CLASS-METHODS delete_branch
      IMPORTING is_mig TYPE ty_mig
      RAISING   zcx_bolt.

    "! Migration branches on GitHub that this app does not know yet
    "! (it_known = branch names already in ZBOLT_MIG).
    CLASS-METHODS import_branches
      IMPORTING it_known          TYPE string_table
      RETURNING VALUE(rt_imports) TYPE ty_t_import
      RAISING   zcx_bolt.

    CLASS-METHODS ai_summary
      IMPORTING is_mig         TYPE ty_mig
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_bolt.

    "! "Sent from ... by SAP user X" - appended to every client-side entry.
    CLASS-METHODS signature
      RETURNING VALUE(rv_text) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS update_status
      IMPORTING is_mig         TYPE ty_mig
                iv_heading     TYPE string
                iv_entry_text  TYPE string
                is_change      TYPE zcl_bolt_status_file=>ty_change OPTIONAL
      RETURNING VALUE(rs_read) TYPE ty_read
      RAISING   zcx_bolt.

    "! Pushes one attached file to <branch>/concerns/<timestamp>/ and returns
    "! the sentence to append to the status entry (same as attachConcernFiles).
    CLASS-METHODS attach
      IMPORTING is_mig         TYPE ty_mig
                iv_file_name   TYPE string
                iv_file_b64    TYPE string
      EXPORTING ev_note        TYPE string
                es_file        TYPE ty_file_info
      RAISING   zcx_bolt.

    CLASS-METHODS to_read
      IMPORTING is_content     TYPE zcl_bolt_github=>ty_content
      RETURNING VALUE(rs_read) TYPE ty_read.

    CLASS-METHODS safe_name
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rv_name) TYPE string.
ENDCLASS.



CLASS zcl_bolt_migration_svc IMPLEMENTATION.

  METHOD signature.
    rv_text = |{ cl_abap_char_utilities=>newline }{ cl_abap_char_utilities=>newline }| &&
              |(Sent from Bolt with Fiori by SAP user { sy-uname }, system { sy-sysid } client { sy-mandt }.)|.
  ENDMETHOD.


  METHOD safe_name.
    rv_name = condense( iv_name ).
    REPLACE ALL OCCURRENCES OF REGEX '[\\/:*?"<>|]' IN rv_name WITH '_'.
    IF rv_name IS INITIAL.
      rv_name = `file`.
    ENDIF.
  ENDMETHOD.


  METHOD to_read.
    rs_read-found = is_content-found.
    rs_read-sha   = is_content-sha.
    IF is_content-found = abap_true.
      rs_read-status  = zcl_bolt_status_file=>parse( is_content-text ).
      rs_read-entries = zcl_bolt_status_file=>timeline( rs_read-status-body ).
    ENDIF.
  ENDMETHOD.


  METHOD read_status.
    DATA(lo_github) = zcl_bolt_github=>from_setup( ).
    rs_read = to_read( lo_github->get_file(
                         iv_branch = is_mig-branch_name
                         iv_path   = zcl_bolt_status_file=>file_path( is_mig-form_slug ) ) ).
  ENDMETHOD.


  METHOD push.
    DATA lt_files TYPE zcl_bolt_github=>ty_t_file.

    DATA(ls_setup)  = zcl_bolt_config=>get_setup( ).
    DATA(ls_system) = zcl_bolt_config=>get_system( is_mig-system_id ).
    IF ls_system IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = |Source system { is_mig-system_id } is not configured any more.| ).
    ENDIF.
    DATA(lo_github) = zcl_bolt_github=>from_setup( ).
    DATA(lv_status_path) = zcl_bolt_status_file=>file_path( is_mig-form_slug ).

    " A branch of this name already there: ours from an earlier attempt whose
    " save did not finish (adopt it), or someone else's (refuse - never overwrite).
    IF lo_github->get_branch_sha( is_mig-branch_name ) IS NOT INITIAL.
      DATA(ls_existing) = lo_github->get_file( iv_branch = is_mig-branch_name iv_path = lv_status_path ).
      IF ls_existing-found = abap_true.
        rs_push-adopted = abap_true.
        rs_push-read    = to_read( ls_existing ).
        RETURN.
      ENDIF.
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = |A branch named { is_mig-branch_name } already exists on GitHub but has no Bolt status file - | &&
                  |it was not created by this app and was left untouched. Withdraw this migration, or remove that branch on GitHub.| ).
    ENDIF.

    " 1. legacy files from the source system
    DATA(ls_extract) = zcl_bolt_source=>get_files( is_system       = ls_system
                                                   iv_form_name    = is_mig-form_name
                                                   iv_prefixes     = zcl_bolt_config=>prefixes( ls_setup )
                                                   iv_count_volume = xsdbool( ls_setup-count_volume = abap_true ) ).
    rs_push-warnings = ls_extract-warnings.
    IF ls_extract-files IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = |No legacy files could be extracted for { is_mig-form_name } on { is_mig-system_id }: | &&
                  |{ concat_lines_of( table = ls_extract-warnings sep = ` ` ) }| ).
    ENDIF.

    " 2. same layout Bolt Console used: <branch>/<file> for the reference files
    LOOP AT ls_extract-files INTO DATA(ls_file).
      DATA(lv_name) = safe_name( ls_file-name ).
      DATA(lv_path) = |{ is_mig-branch_name }/{ lv_name }|.
      DATA(lv_data) = zcl_bolt_github=>to_utf8( ls_file-content ).
      APPEND VALUE #( path = lv_path content = lv_data ) TO lt_files.
      APPEND VALUE #( path = lv_path name = lv_name kind = ls_file-kind size = xstrlen( lv_data ) ) TO rs_push-files.
      IF ls_file-kind = `XML`.
        DATA(ls_signal) = zcl_bolt_form_export=>complexity( ls_file-content ).
        IF ls_signal-ok = abap_true.
          rs_push-complexity      = ls_signal-level.
          rs_push-complexity_text = ls_signal-headline.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " 3. the Queued status file - in the SAME commit, so the branch never exists without it
    DATA(lv_nl) = cl_abap_char_utilities=>newline.
    DATA(lv_entry) = |Migration submitted with { lines( rs_push-files ) } reference file(s).|.
    lv_entry = |{ lv_entry }{ lv_nl }{ lv_nl }Sent by Bolt with Fiori from SAP system { is_mig-system_id }| &&
               |{ COND string( WHEN ls_system-sap_client IS NOT INITIAL THEN | client { ls_system-sap_client }| ) }| &&
               | by user { sy-uname } (serial no. { is_mig-serial_no }).|.
    IF rs_push-complexity IS NOT INITIAL.
      lv_entry = |{ lv_entry }{ lv_nl }Early complexity signal: { to_upper( rs_push-complexity ) } - { rs_push-complexity_text } | &&
                 |(structural read of the layout only - not the full risk score).|.
    ENDIF.
    LOOP AT rs_push-warnings INTO DATA(lv_warning).
      lv_entry = |{ lv_entry }{ lv_nl }Warning: { lv_warning }|.
    ENDLOOP.
    DATA(lv_status_text) = zcl_bolt_status_file=>append_entry(
      iv_existing   = ``
      iv_title      = is_mig-form_name
      iv_heading    = `Queued`
      iv_entry_text = lv_entry
      is_change     = VALUE #( status     = `queued`   set_status     = abap_true
                               waiting_on = `engineer` set_waiting_on = abap_true
                               note       = `Waiting for the migration engineer to pick this up.` set_note = abap_true ) ).
    APPEND VALUE #( path = lv_status_path content = zcl_bolt_github=>to_utf8( lv_status_text ) ) TO lt_files.

    rs_push-commit_sha = lo_github->create_branch_with_files(
      iv_base_branch = COND #( WHEN ls_setup-gh_base_branch IS NOT INITIAL
                               THEN condense( CONV string( ls_setup-gh_base_branch ) )
                               ELSE CONV string( zcl_bolt_config=>gc_default_base ) )
      iv_branch      = is_mig-branch_name
      it_files       = lt_files
      iv_message     = |Add reference documents for { is_mig-form_name }| ).

    rs_push-read-found   = abap_true.
    rs_push-read-status  = zcl_bolt_status_file=>parse( lv_status_text ).
    rs_push-read-entries = zcl_bolt_status_file=>timeline( rs_push-read-status-body ).
  ENDMETHOD.


  METHOD update_status.
    DATA(lo_github) = zcl_bolt_github=>from_setup( ).
    DATA(lv_path) = zcl_bolt_status_file=>file_path( is_mig-form_slug ).

    " Read-modify-write with the blob SHA: if the engineer (or another user)
    " wrote in between, GitHub refuses and we re-apply on the fresh copy.
    DO 3 TIMES.
      DATA(ls_content) = lo_github->get_file( iv_branch = is_mig-branch_name iv_path = lv_path ).
      DATA(lv_text) = zcl_bolt_status_file=>append_entry(
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
    RAISE EXCEPTION NEW zcx_bolt(
      iv_text = `The status file kept changing while saving (three attempts) - refresh and try again.` ).
  ENDMETHOD.


  METHOD attach.
    CLEAR: ev_note, es_file.
    IF iv_file_b64 IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lo_github) = zcl_bolt_github=>from_setup( ).
    DATA(lv_ts) = |{ zcl_bolt_config=>now( ) DECIMALS = 0 }|.
    DATA(lv_name) = safe_name( COND #( WHEN iv_file_name IS NOT INITIAL THEN iv_file_name ELSE `attachment` ) ).
    DATA(lv_folder) = |{ is_mig-branch_name }/concerns/{ lv_ts }|.
    DATA(lv_data) = cl_http_utility=>decode_x_base64( iv_file_b64 ).
    lo_github->add_files( iv_branch  = is_mig-branch_name
                          it_files   = VALUE #( ( path = |{ lv_folder }/{ lv_name }| content = lv_data ) )
                          iv_message = |Attach 1 file(s) to a concern on { is_mig-form_name }| ).
    ev_note = |{ cl_abap_char_utilities=>newline }{ cl_abap_char_utilities=>newline }Attached: { lv_name } (pushed to `{ lv_folder }/`)|.
    es_file = VALUE #( path = |{ lv_folder }/{ lv_name }| name = lv_name kind = `CONCERN` size = xstrlen( lv_data ) ).
  ENDMETHOD.


  METHOD confirm.
    DATA lv_attached TYPE string.

    DATA(ls_current) = read_status( is_mig ).
    IF ls_current-found = abap_false.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `The status file is not on the branch yet - nothing to confirm.` ).
    ENDIF.
    IF ls_current-status-stop = abap_true.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `This migration is stopped. Resume it first.` ).
    ENDIF.
    IF ls_current-status-waiting_on IS INITIAL OR ls_current-status-waiting_on = `engineer`.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `Nothing is waiting for your confirmation right now.` ).
    ENDIF.

    attach( EXPORTING is_mig       = is_mig
                      iv_file_name = iv_file_name
                      iv_file_b64  = iv_file_b64
            IMPORTING ev_note      = lv_attached
                      es_file      = DATA(ls_file) ).
    IF ls_file IS NOT INITIAL.
      APPEND ls_file TO rs_action-files.
    ENDIF.

    DATA(lv_note) = zcl_bolt_status_file=>trim( |{ iv_note }{ lv_attached }| ).
    rs_action-read = update_status(
      is_mig        = is_mig
      iv_heading    = `Manual activity confirmed`
      iv_entry_text = COND #( WHEN lv_note IS NOT INITIAL
                              THEN |Client confirmed the manual step is done: { lv_note }{ signature( ) }|
                              ELSE |Client confirmed the manual step is done.{ signature( ) }| )
      is_change     = VALUE #( status     = `in_progress` set_status     = abap_true
                               waiting_on = `engineer`    set_waiting_on = abap_true
                               note       = ``            set_note       = abap_true ) ).
  ENDMETHOD.


  METHOD concern.
    DATA lv_attached TYPE string.

    IF zcl_bolt_status_file=>trim( iv_text ) IS INITIAL AND iv_file_b64 IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `Type your concern first.` ).
    ENDIF.

    attach( EXPORTING is_mig       = is_mig
                      iv_file_name = iv_file_name
                      iv_file_b64  = iv_file_b64
            IMPORTING ev_note      = lv_attached
                      es_file      = DATA(ls_file) ).
    IF ls_file IS NOT INITIAL.
      APPEND ls_file TO rs_action-files.
    ENDIF.

    DATA(lv_heading) = SWITCH string( to_lower( iv_kind )
                         WHEN `problem`  THEN `Problem reported`
                         WHEN `question` THEN `Question`
                         WHEN `change`   THEN `Change requested`
                         ELSE `Concern raised` ).
    rs_action-read = update_status(
      is_mig        = is_mig
      iv_heading    = lv_heading
      iv_entry_text = |{ zcl_bolt_status_file=>trim( |{ iv_text }{ lv_attached }| ) }{ signature( ) }|
      is_change     = VALUE #( status     = `open_for_concerns` set_status     = abap_true
                               waiting_on = `engineer`          set_waiting_on = abap_true
                               note       = ``                  set_note       = abap_true ) ).
  ENDMETHOD.


  METHOD set_stop.
    DATA(lv_note) = zcl_bolt_status_file=>trim( iv_note ).
    DATA(lv_text) = COND string(
      WHEN iv_stop = abap_false THEN `Client resumed the migration.`
      WHEN lv_note IS NOT INITIAL THEN |Client requested a stop: { lv_note }|
      ELSE `Client requested a stop. No further migration activity should proceed until resumed.` ).
    rs_read = update_status(
      is_mig        = is_mig
      iv_heading    = COND #( WHEN iv_stop = abap_true THEN `Stop requested` ELSE `Resumed` )
      iv_entry_text = |{ lv_text }{ signature( ) }|
      is_change     = VALUE #( stop = iv_stop set_stop = abap_true ) ).
  ENDMETHOD.


  METHOD add_reference_file.
    DATA(lo_github) = zcl_bolt_github=>from_setup( ).
    DATA(lv_name) = safe_name( iv_file_name ).
    DATA(lv_data) = cl_http_utility=>decode_x_base64( iv_file_b64 ).
    IF lv_data IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = |The file { lv_name } is empty.| ).
    ENDIF.
    lo_github->add_files( iv_branch  = is_mig-branch_name
                          it_files   = VALUE #( ( path = |{ is_mig-branch_name }/{ lv_name }| content = lv_data ) )
                          iv_message = |Add reference documents for { is_mig-form_name }| ).
    rs_file = VALUE #( path = |{ is_mig-branch_name }/{ lv_name }| name = lv_name kind = `ATTACH` size = xstrlen( lv_data ) ).
  ENDMETHOD.


  METHOD delete_branch.
    zcl_bolt_github=>from_setup( )->delete_branch( is_mig-branch_name ).
  ENDMETHOD.


  METHOD import_branches.
    DATA(ls_setup) = zcl_bolt_config=>get_setup( ).
    DATA(lo_github) = zcl_bolt_github=>from_setup( ).
    DATA(lv_prefix) = condense( CONV string( ls_setup-gh_branch_prefix ) ).
    DATA(lv_head) = COND string( WHEN lv_prefix IS NOT INITIAL THEN |{ to_lower( lv_prefix ) }-| ).

    LOOP AT lo_github->list_branches( lv_head ) INTO DATA(lv_branch).
      IF line_exists( it_known[ table_line = lv_branch ] ).
        CONTINUE.
      ENDIF.
      " Bolt Console named the status file after the form: <branch> minus prefix.
      DATA(lv_rest) = substring( val = lv_branch off = strlen( lv_head ) ).
      DATA(lv_slug) = zcl_bolt_status_file=>form_slug( lv_rest ).
      DATA(ls_read) = to_read( lo_github->get_file( iv_branch = lv_branch
                                                     iv_path   = zcl_bolt_status_file=>file_path( lv_slug ) ) ).
      IF ls_read-found = abap_false.
        CONTINUE. " not a Bolt migration branch (no status file)
      ENDIF.
      APPEND VALUE #( branch_name = lv_branch
                      form_name   = COND #( WHEN ls_read-status-title IS NOT INITIAL
                                            THEN to_upper( ls_read-status-title )
                                            ELSE to_upper( lv_rest ) )
                      form_slug   = lv_slug
                      read        = ls_read ) TO rt_imports.
    ENDLOOP.
  ENDMETHOD.


  METHOD ai_summary.
    DATA(ls_setup) = zcl_bolt_config=>get_setup( ).
    DATA(lo_github) = zcl_bolt_github=>from_setup( ).
    DATA(ls_snapshot) = lo_github->get_file( iv_branch = is_mig-branch_name
                                             iv_path   = |{ is_mig-branch_name }/{ is_mig-form_name }.md| ).
    IF ls_snapshot-found = abap_false.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = |The legacy-grab snapshot { is_mig-form_name }.md is not on the branch.| ).
    ENDIF.
    DATA(lv_grab) = ls_snapshot-text.
    IF strlen( lv_grab ) > 60000.
      lv_grab = substring( val = lv_grab len = 60000 ).
    ENDIF.
    rv_text = zcl_bolt_ai=>complete(
      is_setup  = ls_setup
      iv_prompt = |You are helping a business user understand a SAP Smart Form that is being migrated to an Adobe Form. | &&
                  |Below is the automatic legacy-grab snapshot of the form { is_mig-form_name }. In plain language and | &&
                  |at most 8 short bullet points, explain: what the form is for, which data it prints, which program | &&
                  |prints it, how complex the migration looks and what needs the business's attention. | &&
                  |Do not invent anything that is not in the snapshot.| &&
                  |{ cl_abap_char_utilities=>newline }{ cl_abap_char_utilities=>newline }{ lv_grab }| ).
  ENDMETHOD.

ENDCLASS.
