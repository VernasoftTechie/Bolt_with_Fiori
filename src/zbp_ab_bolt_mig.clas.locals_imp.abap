"! Migration actions. Every GitHub interaction is delegated to
"! ZCL_AB_BOLT_MIG_SVC (no DB writes there); this handler stores the outcome
"! through EML in local mode:
"!   - basic status in ZABT_BOLT_MIG (status, waiting on, stop, dates, counts)
"!   - one ZABT_BOLT_HIST row per event (no texts)
"!   - one ZABT_BOLT_FILE row per file put on the branch
"! The communication texts themselves stay in the branch's status file and
"! are read live (ZAB_CDS_CE_BOLT_TIMELN). A failed GitHub send is still
"! saved as FAILED with its reason (warning message, not "failed", so the
"! save is not rolled back); a refused client action changes nothing.
CLASS lhc_migration DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    TYPES ty_s_mig TYPE STRUCTURE FOR READ RESULT zab_cds_i_bolt_mig\\Migration.
    TYPES ty_t_mig TYPE TABLE FOR READ RESULT zab_cds_i_bolt_mig\\Migration.

    CLASS-DATA gv_cid TYPE i.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Migration RESULT result.

    METHODS commitselection FOR MODIFY
      IMPORTING keys FOR ACTION Migration~commitSelection RESULT result.

    METHODS refreshall FOR MODIFY
      IMPORTING keys FOR ACTION Migration~refreshAll RESULT result.

    METHODS pushtogithub FOR MODIFY
      IMPORTING keys FOR ACTION Migration~pushToGitHub RESULT result.

    METHODS refreshstatus FOR MODIFY
      IMPORTING keys FOR ACTION Migration~refreshStatus RESULT result.

    METHODS respond FOR MODIFY
      IMPORTING keys FOR ACTION Migration~respond RESULT result.

    METHODS requeststop FOR MODIFY
      IMPORTING keys FOR ACTION Migration~requestStop RESULT result.

    METHODS resume FOR MODIFY
      IMPORTING keys FOR ACTION Migration~resume RESULT result.

    METHODS savelegacydocs FOR MODIFY
      IMPORTING keys FOR ACTION Migration~saveLegacyDocs RESULT result.

    METHODS aisummary FOR MODIFY
      IMPORTING keys FOR ACTION Migration~aiSummary RESULT result.

    METHODS next_cid
      RETURNING VALUE(rv_cid) TYPE string.

    METHODS to_svc
      IMPORTING is_mig        TYPE ty_s_mig
      RETURNING VALUE(rs_mig) TYPE zcl_ab_bolt_mig_svc=>ty_mig.

    "! Stores the status-file header as basic status fields and writes ONE
    "! history row: iv_event when the client caused the change, else STATUS
    "! (engineer) when status / waiting on / stop changed on the branch.
    METHODS apply_read
      IMPORTING is_mig        TYPE ty_s_mig
                is_read       TYPE zcl_ab_bolt_mig_svc=>ty_read
                iv_event      TYPE zabt_bolt_hist-hist_event OPTIONAL
                iv_commit_sha TYPE string OPTIONAL.

    METHODS add_hist
      IMPORTING is_mig        TYPE ty_s_mig
                iv_event      TYPE zabt_bolt_hist-hist_event
                iv_actor      TYPE zabt_bolt_hist-actor DEFAULT zcl_ab_bolt_config=>gc_actor-client
                iv_status     TYPE zabt_bolt_mig-mig_status OPTIONAL
                iv_waiting_on TYPE zabt_bolt_mig-waiting_on OPTIONAL
                iv_stopped    TYPE abap_boolean OPTIONAL
                iv_commit_sha TYPE string OPTIONAL.

    METHODS add_files
      IMPORTING is_mig        TYPE ty_s_mig
                it_files      TYPE zcl_ab_bolt_mig_svc=>ty_t_file_info
                iv_commit_sha TYPE string OPTIONAL.

    METHODS read_back
      IMPORTING it_keys       TYPE ty_t_mig
      RETURNING VALUE(rt_mig) TYPE ty_t_mig.

    METHODS msg
      IMPORTING iv_severity   TYPE if_abap_behv_message=>t_severity
                iv_text       TYPE string
      RETURNING VALUE(ro_msg) TYPE REF TO if_abap_behv_message.

    METHODS cut
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    "! Refused when the migration cannot take client actions right now.
    METHODS refusal
      IMPORTING is_mig         TYPE ty_s_mig
                iv_need_pushed TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS lhc_migration IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Everyone who reaches the app (PFCG role with the service) may work with
    " migrations - the same as everyone who could open the web app.
    result = VALUE #( %action-commitSelection = if_abap_behv=>auth-allowed
                      %action-refreshAll      = if_abap_behv=>auth-allowed
                      %action-pushToGitHub    = if_abap_behv=>auth-allowed
                      %action-refreshStatus   = if_abap_behv=>auth-allowed
                      %action-respond         = if_abap_behv=>auth-allowed
                      %action-requestStop     = if_abap_behv=>auth-allowed
                      %action-resume          = if_abap_behv=>auth-allowed
                      %action-saveLegacyDocs  = if_abap_behv=>auth-allowed
                      %action-aiSummary       = if_abap_behv=>auth-allowed ).
  ENDMETHOD.


  METHOD next_cid.
    gv_cid += 1.
    rv_cid = |BOLT{ gv_cid }|.
  ENDMETHOD.


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


  METHOD cut.
    rv_text = COND #( WHEN strlen( iv_text ) > 255 THEN substring( val = iv_text len = 255 ) ELSE iv_text ).
  ENDMETHOD.


  METHOD to_svc.
    DATA lv_prev TYPE string.
    IF is_mig-ReprocessOf IS NOT INITIAL.
      SELECT SINGLE branch_name FROM zabt_bolt_mig WHERE mig_uuid = @is_mig-ReprocessOf INTO @DATA(lv_branch).
      IF sy-subrc = 0.
        lv_prev = condense( CONV string( lv_branch ) ).
      ENDIF.
    ENDIF.
    rs_mig = zcl_ab_bolt_mig_svc=>from_row(
               is_row  = VALUE #( form_name   = is_mig-FormName
                                  form_descr  = is_mig-FormDescr
                                  form_slug   = is_mig-FormSlug
                                  branch_name = is_mig-BranchName
                                  serial_no   = is_mig-SerialNo
                                  run_no      = is_mig-RunNo )
               iv_prev = lv_prev ).
  ENDMETHOD.


  METHOD refusal.
    CLEAR rv_text.
    IF is_mig-Superseded = abap_true.
      rv_text = |{ is_mig-FormName } (serial no. { is_mig-SerialNo }) was replaced by a re-process run - work on the newer one.|.
    ELSEIF iv_need_pushed = abap_true AND is_mig-PushStatus <> zcl_ab_bolt_config=>gc_push-pushed.
      rv_text = |{ is_mig-FormName } is not on GitHub yet - use "Send to GitHub" first.|.
    ENDIF.
  ENDMETHOD.


  METHOD read_back.
    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS
      WITH VALUE #( FOR ls_key IN it_keys ( %tky = ls_key-%tky ) )
      RESULT rt_mig.
  ENDMETHOD.


  METHOD add_hist.
    DATA lt_cba TYPE TABLE FOR CREATE zab_cds_i_bolt_mig\\Migration\_History.
    APPEND VALUE #( %tky    = is_mig-%tky
                    %target = VALUE #( ( %cid      = next_cid( )
                                         EventAt   = zcl_ab_bolt_config=>now( )
                                         HistEvent = iv_event
                                         Actor     = iv_actor
                                         EventUser = COND #( WHEN iv_actor = zcl_ab_bolt_config=>gc_actor-engineer THEN `` ELSE sy-uname )
                                         MigStatus = COND #( WHEN iv_status IS SUPPLIED THEN iv_status ELSE is_mig-MigStatus )
                                         WaitingOn = COND #( WHEN iv_waiting_on IS SUPPLIED THEN iv_waiting_on ELSE is_mig-WaitingOn )
                                         Stopped   = COND #( WHEN iv_stopped IS SUPPLIED THEN iv_stopped ELSE is_mig-Stopped )
                                         CommitSha = iv_commit_sha ) ) ) TO lt_cba.
    MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration
        CREATE BY \_History
        FIELDS ( EventAt HistEvent Actor EventUser MigStatus WaitingOn Stopped CommitSha )
        WITH lt_cba.
  ENDMETHOD.


  METHOD add_files.
    DATA lt_cba TYPE TABLE FOR CREATE zab_cds_i_bolt_mig\\Migration\_File.
    IF it_files IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_now) = zcl_ab_bolt_config=>now( ).
    APPEND VALUE #( %tky    = is_mig-%tky
                    %target = VALUE #( FOR ls_file IN it_files
                                       ( %cid      = next_cid( )
                                         FileKind  = ls_file-kind
                                         FileName  = ls_file-name
                                         FilePath  = ls_file-path
                                         SizeBytes = ls_file-size
                                         CommitSha = iv_commit_sha
                                         PushedAt  = lv_now
                                         PushedBy  = sy-uname
                                         Removed   = abap_false ) ) ) TO lt_cba.
    MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration
        CREATE BY \_File
        FIELDS ( FileKind FileName FilePath SizeBytes CommitSha PushedAt PushedBy Removed )
        WITH lt_cba.
  ENDMETHOD.


  METHOD apply_read.
    DATA(lv_now) = zcl_ab_bolt_config=>now( ).
    IF is_read-found = abap_false.
      MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
        ENTITY Migration
          UPDATE FIELDS ( LastSyncAt )
          WITH VALUE #( ( %tky = is_mig-%tky LastSyncAt = lv_now ) ).
      RETURN.
    ENDIF.

    DATA(lv_status)  = CONV zabt_bolt_mig-mig_status( is_read-status-status ).
    DATA(lv_waiting) = CONV zabt_bolt_mig-waiting_on( is_read-status-waiting_on ).
    DATA(lv_stop)    = CONV abap_boolean( is_read-status-stop ).
    DATA(lv_changed) = xsdbool( lv_status <> is_mig-MigStatus OR lv_waiting <> is_mig-WaitingOn OR lv_stop <> is_mig-Stopped ).

    " Dates for the progress analysis: first pick-up, completion, last stop.
    DATA(lv_picked) = is_mig-PickedUpAt.
    IF lv_picked IS INITIAL AND ( is_read-status-claimed_by IS NOT INITIAL
                                  OR ( lv_status IS NOT INITIAL AND lv_status <> zcl_ab_bolt_config=>gc_status-queued ) ).
      lv_picked = lv_now.
    ENDIF.
    DATA(lv_completed) = is_mig-CompletedAt.
    IF lv_status = zcl_ab_bolt_config=>gc_status-completed AND lv_completed IS INITIAL.
      lv_completed = lv_now.
    ENDIF.
    DATA(lv_stopped_at) = is_mig-StoppedAt.
    IF lv_stop = abap_true AND is_mig-Stopped = abap_false.
      lv_stopped_at = lv_now.
    ENDIF.

    MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration
        UPDATE FIELDS ( MigStatus WaitingOn Stopped ClaimedBy StatusUpdated StatusSha LastSyncAt PickedUpAt CompletedAt StoppedAt )
        WITH VALUE #( ( %tky          = is_mig-%tky
                        MigStatus     = lv_status
                        WaitingOn     = lv_waiting
                        Stopped       = lv_stop
                        ClaimedBy     = is_read-status-claimed_by
                        StatusUpdated = is_read-status-updated_at
                        StatusSha     = is_read-sha
                        LastSyncAt    = lv_now
                        PickedUpAt    = lv_picked
                        CompletedAt   = lv_completed
                        StoppedAt     = lv_stopped_at ) ).

    IF iv_event IS NOT INITIAL.
      add_hist( is_mig        = is_mig
                iv_event      = iv_event
                iv_status     = lv_status
                iv_waiting_on = lv_waiting
                iv_stopped    = lv_stop
                iv_commit_sha = iv_commit_sha ).
    ELSEIF lv_changed = abap_true.
      add_hist( is_mig        = is_mig
                iv_event      = zcl_ab_bolt_config=>gc_event-status
                iv_actor      = zcl_ab_bolt_config=>gc_actor-engineer
                iv_status     = lv_status
                iv_waiting_on = lv_waiting
                iv_stopped    = lv_stop ).
    ENDIF.
  ENDMETHOD.


  METHOD commitselection.
    " The Smart Forms tab's Next > Commit: one new migration per selected form,
    " with the next serial number. A form already in migration or completed
    " cannot be selected again; a STOPPED form can - that starts a re-process
    " run on a new branch (<prefix>-<form>-r<n>) and closes the stopped one.
    TYPES:
      BEGIN OF ty_last,
        form_name   TYPE zabt_bolt_mig-form_name,
        run_no      TYPE zabt_bolt_mig-run_no,
        mig_uuid    TYPE zabt_bolt_mig-mig_uuid,
        serial_no   TYPE zabt_bolt_mig-serial_no,
        mig_status  TYPE zabt_bolt_mig-mig_status,
        stopped     TYPE zabt_bolt_mig-stopped,
        superseded  TYPE zabt_bolt_mig-superseded,
      END OF ty_last.
    DATA lt_last   TYPE SORTED TABLE OF ty_last WITH UNIQUE KEY form_name.
    DATA lt_all    TYPE STANDARD TABLE OF ty_last WITH EMPTY KEY.
    DATA lt_create TYPE TABLE FOR CREATE zab_cds_i_bolt_mig\\Migration.
    DATA lt_hist   TYPE TABLE FOR CREATE zab_cds_i_bolt_mig\\Migration\_History.
    DATA lt_old    TYPE STANDARD TABLE OF ty_last WITH EMPTY KEY.
    DATA lt_seen   TYPE string_table.

    DATA(ls_key) = keys[ 1 ].
    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).

    " No connection gate: a form committed while GitHub is not ready (not connected,
    " repository not set, network down) is kept as a DRAFT with its serial number -
    " PENDING/FAILED on the Drafts tab - and sent with "Send to GitHub" or by the
    " job until its initial load is on GitHub.
    DATA(lv_not_live) = COND string(
      WHEN ls_setup-gh_token_set = abap_false THEN `GitHub is not connected yet`
      WHEN ls_setup-gh_repo IS INITIAL        THEN `no target repository is set yet`
      WHEN ls_setup-gh_can_push = abap_false  THEN `the GitHub token cannot push to the target repository` ).

    " One commit at a time on this system, so two users never get the same serial number.
    CALL FUNCTION 'ENQUEUE_E_TABLE'
      EXPORTING
        mode_rstable   = 'E'
        tabname        = 'ZABT_BOLT_MIG'
        varkey         = 'BOLT_SERIAL'
        _scope         = '2'
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      APPEND VALUE #( %cid = ls_key-%cid ) TO failed-migration.
      APPEND VALUE #( %cid = ls_key-%cid %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                     iv_text     = `Another user is committing a selection right now - try again in a moment.` ) )
        TO reported-migration.
      RETURN.
    ENDIF.

    SELECT form_name, run_no, mig_uuid, serial_no, mig_status, stopped, superseded FROM zabt_bolt_mig
      ORDER BY form_name, run_no DESCENDING
      INTO TABLE @lt_all.
    LOOP AT lt_all INTO DATA(ls_row).
      IF NOT line_exists( lt_last[ form_name = ls_row-form_name ] ).
        lt_last = VALUE #( BASE lt_last ( ls_row ) ).
      ENDIF.
    ENDLOOP.
    SELECT MAX( serial_no ) FROM zabt_bolt_mig INTO @DATA(lv_serial).

    DATA(lv_names) = ls_key-%param-FormNames.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_names WITH `,`.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_names WITH `,`.
    SPLIT lv_names AT `,` INTO TABLE DATA(lt_names).

    LOOP AT lt_names INTO DATA(lv_raw).
      DATA(lv_name) = to_upper( condense( lv_raw ) ).
      IF lv_name IS INITIAL OR line_exists( lt_seen[ table_line = lv_name ] ).
        CONTINUE.
      ENDIF.
      APPEND lv_name TO lt_seen.

      DATA(ls_form) = zcl_ab_bolt_form_catalog=>get( lv_name ).
      IF ls_form IS INITIAL.
        APPEND VALUE #( %cid = ls_key-%cid %msg = msg( iv_severity = if_abap_behv_message=>severity-warning
                                                       iv_text     = |{ lv_name } does not exist on system { sy-sysid } - skipped.| ) )
          TO reported-migration.
        CONTINUE.
      ENDIF.

      DATA(lv_run) = 1.
      DATA lv_prev TYPE sysuuid_x16.
      CLEAR lv_prev.
      READ TABLE lt_last INTO DATA(ls_last) WITH TABLE KEY form_name = ls_form-form_name.
      IF sy-subrc = 0.
        IF ls_last-mig_status = zcl_ab_bolt_config=>gc_status-completed.
          APPEND VALUE #( %cid = ls_key-%cid %msg = msg( iv_severity = if_abap_behv_message=>severity-warning
                                                         iv_text     = |{ lv_name } is already migrated (serial no. { ls_last-serial_no }) - skipped.| ) )
            TO reported-migration.
          CONTINUE.
        ENDIF.
        IF ls_last-stopped = abap_false.
          APPEND VALUE #( %cid = ls_key-%cid %msg = msg( iv_severity = if_abap_behv_message=>severity-warning
                                                         iv_text     = |{ lv_name } is already in migration (serial no. { ls_last-serial_no }) - skipped.| ) )
            TO reported-migration.
          CONTINUE.
        ENDIF.
        " Stopped: re-process run.
        lv_run  = ls_last-run_no + 1.
        lv_prev = ls_last-mig_uuid.
        APPEND ls_last TO lt_old.
      ENDIF.

      lv_serial += 1.
      DATA(lv_cid) = next_cid( ).
      APPEND VALUE #( %cid         = lv_cid
                      SerialNo     = lv_serial
                      FormName     = ls_form-form_name
                      FormDescr    = ls_form-description
                      DevPackage   = ls_form-dev_package
                      DriverProgs  = cut( ls_form-driver_progs )
                      OutputTypes  = cut( ls_form-output_types )
                      RunNo        = lv_run
                      ReprocessOf  = lv_prev
                      Superseded   = abap_false
                      BranchName   = zcl_ab_bolt_mig_svc=>branch_for( iv_form_name = ls_form-form_name
                                                                      iv_run_no    = lv_run
                                                                      is_setup     = ls_setup )
                      FormSlug     = zcl_ab_bolt_status_file=>form_slug( CONV #( ls_form-form_name ) )
                      PushStatus   = zcl_ab_bolt_config=>gc_push-pending
                      PushAttempts = 0
                      MigStatus    = zcl_ab_bolt_config=>gc_status-queued
                      WaitingOn    = `engineer`
                      Stopped      = abap_false
                      SourceSysid  = sy-sysid
                      SourceClient = sy-mandt ) TO lt_create.
      APPEND VALUE #( %cid_ref = lv_cid
                      %target  = VALUE #( ( %cid      = next_cid( )
                                            EventAt   = zcl_ab_bolt_config=>now( )
                                            HistEvent = zcl_ab_bolt_config=>gc_event-committed
                                            Actor     = zcl_ab_bolt_config=>gc_actor-client
                                            EventUser = sy-uname
                                            MigStatus = zcl_ab_bolt_config=>gc_status-queued
                                            WaitingOn = `engineer`
                                            Stopped   = abap_false ) ) ) TO lt_hist.
    ENDLOOP.

    IF lt_create IS INITIAL.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration
        CREATE FIELDS ( SerialNo FormName FormDescr DevPackage DriverProgs OutputTypes RunNo ReprocessOf Superseded
                        BranchName FormSlug PushStatus PushAttempts MigStatus WaitingOn Stopped SourceSysid SourceClient )
        WITH lt_create
        CREATE BY \_History
        FIELDS ( EventAt HistEvent Actor EventUser MigStatus WaitingOn Stopped )
        WITH lt_hist
      MAPPED DATA(ls_mapped).

    " The stopped runs that were re-processed are closed (no Resume any more).
    IF lt_old IS NOT INITIAL.
      MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
        ENTITY Migration
          UPDATE FIELDS ( Superseded )
          WITH VALUE #( FOR ls_o IN lt_old ( MigUuid = ls_o-mig_uuid Superseded = abap_true ) ).
      READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
        ENTITY Migration ALL FIELDS
        WITH VALUE #( FOR ls_o IN lt_old ( MigUuid = ls_o-mig_uuid ) )
        RESULT DATA(lt_old_mig).
      LOOP AT lt_old_mig INTO DATA(ls_old_mig).
        add_hist( is_mig = ls_old_mig iv_event = zcl_ab_bolt_config=>gc_event-reprocessed ).
      ENDLOOP.
    ENDIF.

    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS
      WITH VALUE #( FOR ls_map IN ls_mapped-migration ( %tky = ls_map-%tky ) )
      RESULT DATA(lt_new).
    APPEND VALUE #( %cid = ls_key-%cid
                    %msg = msg( iv_severity = COND #( WHEN lv_not_live IS INITIAL THEN if_abap_behv_message=>severity-success
                                                      ELSE if_abap_behv_message=>severity-warning )
                                iv_text     = COND #( WHEN lv_not_live IS INITIAL
                                                      THEN |{ lines( lt_new ) } Smart Form(s) committed for migration.|
                                                      ELSE |{ lines( lt_new ) } Smart Form(s) saved as drafts - { lv_not_live }. Send them from the Drafts tab once Setup is complete.| ) ) )
      TO reported-migration.
    result = VALUE #( FOR ls_new IN lt_new ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_new ) ) ).
  ENDMETHOD.


  METHOD pushtogithub.
    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      DATA(lv_refusal) = refusal( is_mig = ls_mig iv_need_pushed = abap_false ).
      IF lv_refusal IS INITIAL AND ls_mig-Stopped = abap_true.
        lv_refusal = |{ ls_mig-FormName } is stopped - resume it first, or select it again for a re-process run.|.
      ENDIF.
      IF lv_refusal IS NOT INITIAL.
        APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
        APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                       iv_text     = lv_refusal ) ) TO reported-migration.
        CONTINUE.
      ENDIF.
      IF ls_mig-PushStatus = zcl_ab_bolt_config=>gc_push-pushed.
        APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-information
                                                       iv_text     = |{ ls_mig-FormName } is already on GitHub.| ) ) TO reported-migration.
        CONTINUE.
      ENDIF.

      TRY.
          DATA(ls_push) = zcl_ab_bolt_mig_svc=>push( to_svc( ls_mig ) ).
          DATA(lv_summary) = COND string(
            WHEN ls_push-adopted = abap_true
            THEN |Branch { ls_mig-BranchName } was already on GitHub with its status file - linked to it, nothing overwritten.|
            ELSE |Created branch { ls_mig-BranchName } with { lines( ls_push-files ) } file(s) in one commit| &&
                 |{ COND string( WHEN ls_push-warnings IS NOT INITIAL THEN | ({ lines( ls_push-warnings ) } warning(s) - see the status file)| ) }.| ).
          MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
            ENTITY Migration
              UPDATE FIELDS ( PushStatus PushMsg PushAttempts PushedAt FilesCount CommitSha Complexity ComplexityInfo )
              WITH VALUE #( ( %tky           = ls_mig-%tky
                              PushStatus     = zcl_ab_bolt_config=>gc_push-pushed
                              PushMsg        = cut( lv_summary )
                              PushAttempts   = ls_mig-PushAttempts + 1
                              PushedAt       = zcl_ab_bolt_config=>now( )
                              FilesCount     = lines( ls_push-files )
                              CommitSha      = ls_push-commit_sha
                              Complexity     = ls_push-complexity
                              ComplexityInfo = cut( ls_push-complexity_info ) ) ).
          add_files( is_mig = ls_mig it_files = ls_push-files iv_commit_sha = ls_push-commit_sha ).
          apply_read( is_mig        = ls_mig
                      is_read       = ls_push-read
                      iv_event      = zcl_ab_bolt_config=>gc_event-pushed
                      iv_commit_sha = ls_push-commit_sha ).
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-success
                                                         iv_text     = |{ ls_mig-FormName }: { lv_summary }| ) ) TO reported-migration.

        CATCH zcx_ab_bolt INTO DATA(lx_error).
          DATA(lv_text) = lx_error->get_text( ).
          MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
            ENTITY Migration
              UPDATE FIELDS ( PushStatus PushMsg PushAttempts )
              WITH VALUE #( ( %tky         = ls_mig-%tky
                              PushStatus   = zcl_ab_bolt_config=>gc_push-failed
                              PushMsg      = cut( lv_text )
                              PushAttempts = ls_mig-PushAttempts + 1 ) ).
          add_hist( is_mig = ls_mig iv_event = zcl_ab_bolt_config=>gc_event-push_failed
                    iv_actor = COND #( WHEN sy-batch = abap_true THEN zcl_ab_bolt_config=>gc_actor-system   " the sync job
                                       ELSE zcl_ab_bolt_config=>gc_actor-client ) ).                    " sent by hand
          " Warning, not failed: the FAILED state and its reason must be saved.
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-warning
                                                         iv_text     = |{ ls_mig-FormName }: { lv_text }| ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    result = VALUE #( FOR ls_after IN read_back( lt_mig ) ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD refreshstatus.
    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig) WHERE PushStatus = zcl_ab_bolt_config=>gc_push-pushed.
      TRY.
          apply_read( is_mig = ls_mig is_read = zcl_ab_bolt_mig_svc=>read_status( to_svc( ls_mig ) ) ).
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-warning
                                                         iv_text     = |{ ls_mig-FormName }: { lx_error->get_text( ) }| ) )
            TO reported-migration.
      ENDTRY.
    ENDLOOP.

    result = VALUE #( FOR ls_after IN read_back( lt_mig ) ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD refreshall.
    " Every migration that can still change: on GitHub, not completed, not replaced.
    DATA(ls_key) = keys[ 1 ].
    SELECT mig_uuid FROM zabt_bolt_mig
      WHERE push_status = @zcl_ab_bolt_config=>gc_push-pushed
        AND superseded  = @abap_false
        AND mig_status <> @zcl_ab_bolt_config=>gc_status-completed
      ORDER BY serial_no
      INTO TABLE @DATA(lt_uuid).

    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS
      WITH VALUE #( FOR ls_uuid IN lt_uuid ( MigUuid = ls_uuid-mig_uuid ) )
      RESULT DATA(lt_mig).

    DATA lv_errors TYPE i.
    DATA(lv_now) = zcl_ab_bolt_config=>now( ).
    LOOP AT lt_mig INTO DATA(ls_mig).
      " Shared throttle: a status read in the last minute (by another user, a screen's
      " 2-minute refresh or the job) is not read again - keeps GitHub's rate limit
      " (5,000 calls per hour per token) safe however many screens are open.
      IF ls_mig-LastSyncAt IS NOT INITIAL.
        TRY.
            IF cl_abap_tstmp=>subtract( tstmp1 = lv_now tstmp2 = ls_mig-LastSyncAt ) < zcl_ab_bolt_config=>gc_resync_secs.
              CONTINUE.
            ENDIF.
          CATCH cx_parameter_invalid ##NO_HANDLER.
            " unreadable time stamp - read the status
        ENDTRY.
      ENDIF.
      TRY.
          apply_read( is_mig = ls_mig is_read = zcl_ab_bolt_mig_svc=>read_status( to_svc( ls_mig ) ) ).
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          lv_errors += 1.
          IF lv_errors <= 3.
            APPEND VALUE #( %cid = ls_key-%cid %msg = msg( iv_severity = if_abap_behv_message=>severity-warning
                                                           iv_text     = |{ ls_mig-FormName }: { lx_error->get_text( ) }| ) )
              TO reported-migration.
          ENDIF.
      ENDTRY.
    ENDLOOP.

    result = VALUE #( FOR ls_after IN read_back( lt_mig ) ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD respond.
    " The communication panel: I've done this - confirm / Report a problem /
    " Ask a question / Request a change / Raise a concern (+ attachments).
    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      TRY.
          DATA(lv_refusal) = refusal( ls_mig ).
          IF lv_refusal IS NOT INITIAL.
            RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = lv_refusal ).
          ENDIF.
          DATA(lv_kind) = to_lower( condense( CONV string( ls_key-%param-Kind ) ) ).
          DATA(ls_action) = zcl_ab_bolt_mig_svc=>respond(
                              is_mig   = to_svc( ls_mig )
                              iv_kind  = lv_kind
                              iv_text  = ls_key-%param-Text
                              it_files = zcl_ab_bolt_mig_svc=>parse_uploads( ls_key-%param-FilesJson ) ).
          add_files( is_mig = ls_mig it_files = ls_action-files ).
          IF ls_action-files IS NOT INITIAL.
            MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
              ENTITY Migration
                UPDATE FIELDS ( FilesCount )
                WITH VALUE #( ( %tky = ls_mig-%tky FilesCount = ls_mig-FilesCount + lines( ls_action-files ) ) ).
          ENDIF.
          apply_read( is_mig   = ls_mig
                      is_read  = ls_action-read
                      iv_event = zcl_ab_bolt_mig_svc=>event_of( lv_kind ) ).
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = msg( iv_severity = if_abap_behv_message=>severity-success
                                      iv_text     = SWITCH #( lv_kind
                                                      WHEN zcl_ab_bolt_mig_svc=>gc_kind-confirm
                                                        THEN `Confirmation submitted - the engineer has been notified and the migration is now In Progress.`
                                                      WHEN zcl_ab_bolt_mig_svc=>gc_kind-problem
                                                        THEN `Problem submitted - the engineer has been notified.`
                                                      WHEN zcl_ab_bolt_mig_svc=>gc_kind-question
                                                        THEN `Question submitted - the engineer has been notified.`
                                                      WHEN zcl_ab_bolt_mig_svc=>gc_kind-change
                                                        THEN `Change request submitted - the engineer has been notified.`
                                                      ELSE `Concern submitted - the engineer has been notified.` ) ) )
            TO reported-migration.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                         iv_text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    result = VALUE #( FOR ls_after IN read_back( lt_mig ) ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD requeststop.
    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      TRY.
          DATA(lv_refusal) = refusal( is_mig = ls_mig iv_need_pushed = abap_false ).
          IF lv_refusal IS INITIAL AND ls_mig-MigStatus = zcl_ab_bolt_config=>gc_status-completed.
            lv_refusal = |{ ls_mig-FormName } is completed - use Raise a concern for any follow-up.|.
          ENDIF.
          IF lv_refusal IS INITIAL AND ls_mig-Stopped = abap_true.
            lv_refusal = |{ ls_mig-FormName } is already stopped.|.
          ENDIF.
          IF lv_refusal IS NOT INITIAL.
            RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = lv_refusal ).
          ENDIF.

          IF ls_mig-PushStatus = zcl_ab_bolt_config=>gc_push-pushed.
            apply_read( is_mig   = ls_mig
                        is_read  = zcl_ab_bolt_mig_svc=>set_stop( is_mig  = to_svc( ls_mig )
                                                                 iv_stop = abap_true
                                                                 iv_note = ls_key-%param-Reason )
                        iv_event = zcl_ab_bolt_config=>gc_event-stopped ).
          ELSE.
            " Never reached GitHub: nothing to tell the engineer - a local stop.
            MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
              ENTITY Migration
                UPDATE FIELDS ( Stopped StoppedAt )
                WITH VALUE #( ( %tky = ls_mig-%tky Stopped = abap_true StoppedAt = zcl_ab_bolt_config=>now( ) ) ).
            add_hist( is_mig = ls_mig iv_event = zcl_ab_bolt_config=>gc_event-stopped iv_stopped = abap_true ).
          ENDIF.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = msg( iv_severity = if_abap_behv_message=>severity-success
                                      iv_text     = |{ ls_mig-FormName } stopped. You can resume it, or select it again | &&
                                                    |on the Smart Forms tab for a re-process run.| ) ) TO reported-migration.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                         iv_text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    result = VALUE #( FOR ls_after IN read_back( lt_mig ) ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD resume.
    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      TRY.
          DATA(lv_refusal) = refusal( is_mig = ls_mig iv_need_pushed = abap_false ).
          IF lv_refusal IS INITIAL AND ls_mig-Stopped = abap_false.
            lv_refusal = |{ ls_mig-FormName } is not stopped.|.
          ENDIF.
          IF lv_refusal IS NOT INITIAL.
            RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = lv_refusal ).
          ENDIF.

          IF ls_mig-PushStatus = zcl_ab_bolt_config=>gc_push-pushed.
            apply_read( is_mig   = ls_mig
                        is_read  = zcl_ab_bolt_mig_svc=>set_stop( is_mig = to_svc( ls_mig ) iv_stop = abap_false )
                        iv_event = zcl_ab_bolt_config=>gc_event-resumed ).
          ELSE.
            MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
              ENTITY Migration
                UPDATE FIELDS ( Stopped )
                WITH VALUE #( ( %tky = ls_mig-%tky Stopped = abap_false ) ).
            add_hist( is_mig = ls_mig iv_event = zcl_ab_bolt_config=>gc_event-resumed iv_stopped = abap_false ).
          ENDIF.
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-success
                                                         iv_text     = |{ ls_mig-FormName } resumed.| ) ) TO reported-migration.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                         iv_text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    result = VALUE #( FOR ls_after IN read_back( lt_mig ) ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD savelegacydocs.
    " "Legacy documents" > Save changes: added files are pushed to <branch>/ in
    " one commit; removed files only leave this list - the branch is untouched,
    " because the engineer may be working from it (same as the web app).
    DATA lt_remove TYPE TABLE FOR UPDATE zab_cds_i_bolt_mig\\File.

    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      TRY.
          DATA(lt_add) = zcl_ab_bolt_mig_svc=>parse_uploads( ls_key-%param-FilesJson ).
          DATA(lv_ids) = condense( ls_key-%param-RemoveIds ).
          SPLIT lv_ids AT `,` INTO TABLE DATA(lt_ids).
          DELETE lt_ids WHERE table_line IS INITIAL.
          IF lt_add IS INITIAL AND lt_ids IS INITIAL.
            RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `Nothing to save - add or remove a file first.` ).
          ENDIF.
          IF lt_add IS NOT INITIAL.
            DATA(lv_refusal) = refusal( ls_mig ).
            IF lv_refusal IS NOT INITIAL.
              RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = lv_refusal ).
            ENDIF.
          ENDIF.

          DATA(lv_added) = 0.
          IF lt_add IS NOT INITIAL.
            DATA(ls_action) = zcl_ab_bolt_mig_svc=>add_legacy_docs( is_mig = to_svc( ls_mig ) it_files = lt_add ).
            add_files( is_mig = ls_mig it_files = ls_action-files iv_commit_sha = ls_action-commit_sha ).
            lv_added = lines( ls_action-files ).
            add_hist( is_mig = ls_mig iv_event = zcl_ab_bolt_config=>gc_event-docs_added iv_commit_sha = ls_action-commit_sha ).
          ENDIF.

          DATA(lv_removed) = 0.
          IF lt_ids IS NOT INITIAL.
            READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
              ENTITY Migration BY \_File ALL FIELDS
              WITH VALUE #( ( %tky = ls_mig-%tky ) )
              RESULT DATA(lt_files).
            CLEAR lt_remove.
            LOOP AT lt_files INTO DATA(ls_file) WHERE Removed = abap_false.
              DATA(lv_hex) = to_upper( CONV string( ls_file-FileUuid ) ).
              LOOP AT lt_ids INTO DATA(lv_id).
                IF to_upper( condense( lv_id ) ) = lv_hex.
                  APPEND VALUE #( %tky      = ls_file-%tky
                                  Removed   = abap_true
                                  RemovedAt = zcl_ab_bolt_config=>now( )
                                  RemovedBy = sy-uname ) TO lt_remove.
                ENDIF.
              ENDLOOP.
            ENDLOOP.
            IF lt_remove IS NOT INITIAL.
              MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
                ENTITY File
                  UPDATE FIELDS ( Removed RemovedAt RemovedBy )
                  WITH lt_remove.
              lv_removed = lines( lt_remove ).
              add_hist( is_mig = ls_mig iv_event = zcl_ab_bolt_config=>gc_event-docs_removed ).
            ENDIF.
          ENDIF.

          IF lv_added > 0.
            MODIFY ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
              ENTITY Migration
                UPDATE FIELDS ( FilesCount )
                WITH VALUE #( ( %tky = ls_mig-%tky FilesCount = ls_mig-FilesCount + lv_added ) ).
          ENDIF.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = msg( iv_severity = if_abap_behv_message=>severity-success
                                      iv_text     = |Legacy documents saved: { lv_added } added (pushed to the branch), | &&
                                                    |{ lv_removed } removed from this list (left untouched on the branch).| ) )
            TO reported-migration.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                         iv_text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    result = VALUE #( FOR ls_after IN read_back( lt_mig ) ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD aisummary.
    READ ENTITIES OF zab_cds_i_bolt_mig IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      TRY.
          DATA(lv_refusal) = refusal( ls_mig ).
          IF lv_refusal IS NOT INITIAL.
            RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = lv_refusal ).
          ENDIF.
          APPEND VALUE #( %tky = ls_mig-%tky %param-Text = zcl_ab_bolt_mig_svc=>ai_summary( to_svc( ls_mig ) ) ) TO result.
        CATCH zcx_ab_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky %msg = msg( iv_severity = if_abap_behv_message=>severity-error
                                                         iv_text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
