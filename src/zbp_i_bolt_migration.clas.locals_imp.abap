"! Migration actions. Every GitHub interaction is delegated to
"! ZCL_BOLT_MIGRATION_SVC (no DB writes there); this handler stores the
"! outcome through EML in local mode, so a failed GitHub call is still saved
"! as a FAILED send with its reason (the background job retries it), while a
"! refused client action (e.g. "nothing waiting for confirmation") changes
"! nothing and shows the reason.
CLASS lhc_migration DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    TYPES ty_s_mig TYPE STRUCTURE FOR READ RESULT zi_bolt_migration\\Migration.
    TYPES ty_t_mig TYPE TABLE FOR READ RESULT zi_bolt_migration\\Migration.

    CLASS-DATA gv_cid TYPE i.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Migration RESULT result.

    METHODS commitselection FOR MODIFY
      IMPORTING keys FOR ACTION Migration~commitSelection RESULT result.

    METHODS refreshall FOR MODIFY
      IMPORTING keys FOR ACTION Migration~refreshAll RESULT result.

    METHODS importfromgithub FOR MODIFY
      IMPORTING keys FOR ACTION Migration~importFromGitHub RESULT result.

    METHODS pushtogithub FOR MODIFY
      IMPORTING keys FOR ACTION Migration~pushToGitHub RESULT result.

    METHODS refreshstatus FOR MODIFY
      IMPORTING keys FOR ACTION Migration~refreshStatus RESULT result.

    METHODS confirmmanual FOR MODIFY
      IMPORTING keys FOR ACTION Migration~confirmManual RESULT result.

    METHODS raiseconcern FOR MODIFY
      IMPORTING keys FOR ACTION Migration~raiseConcern RESULT result.

    METHODS setstop FOR MODIFY
      IMPORTING keys FOR ACTION Migration~setStop RESULT result.

    METHODS addreferencefile FOR MODIFY
      IMPORTING keys FOR ACTION Migration~addReferenceFile RESULT result.

    METHODS withdraw FOR MODIFY
      IMPORTING keys FOR ACTION Migration~withdraw RESULT result.

    METHODS aisummary FOR MODIFY
      IMPORTING keys FOR ACTION Migration~aiSummary RESULT result.

    METHODS next_cid
      RETURNING VALUE(rv_cid) TYPE string.

    METHODS to_svc
      IMPORTING is_mig        TYPE ty_s_mig
      RETURNING VALUE(rs_mig) TYPE zcl_bolt_migration_svc=>ty_mig.

    "! Header fields from the status file + its timeline as STATUS log rows.
    METHODS apply_read
      IMPORTING is_mig  TYPE ty_s_mig
                is_read TYPE zcl_bolt_migration_svc=>ty_read.

    METHODS add_log
      IMPORTING is_mig     TYPE ty_s_mig
                iv_heading TYPE string
                iv_text    TYPE string
                iv_actor   TYPE string DEFAULT `app`.

    METHODS add_files
      IMPORTING is_mig   TYPE ty_s_mig
                it_files TYPE zcl_bolt_migration_svc=>ty_t_file_info.

    METHODS actor_of
      IMPORTING iv_heading      TYPE string
      RETURNING VALUE(rv_actor) TYPE string.

    METHODS read_migrations
      IMPORTING it_uuid       TYPE string_table OPTIONAL
      RETURNING VALUE(rt_mig) TYPE ty_t_mig.
ENDCLASS.


CLASS lhc_migration IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Everyone who reaches the app (PFCG role with the service) may work with
    " migrations; withdrawing is limited to administrators inside withdraw.
    result = VALUE #( %action-commitSelection  = if_abap_behv=>auth-allowed
                      %action-refreshAll       = if_abap_behv=>auth-allowed
                      %action-importFromGitHub = if_abap_behv=>auth-allowed
                      %action-pushToGitHub     = if_abap_behv=>auth-allowed
                      %action-refreshStatus    = if_abap_behv=>auth-allowed
                      %action-confirmManual    = if_abap_behv=>auth-allowed
                      %action-raiseConcern     = if_abap_behv=>auth-allowed
                      %action-setStop          = if_abap_behv=>auth-allowed
                      %action-addReferenceFile = if_abap_behv=>auth-allowed
                      %action-withdraw         = if_abap_behv=>auth-allowed
                      %action-aiSummary        = if_abap_behv=>auth-allowed ).
  ENDMETHOD.


  METHOD next_cid.
    gv_cid += 1.
    rv_cid = |BOLT{ gv_cid }|.
  ENDMETHOD.


  METHOD to_svc.
    rs_mig = VALUE #( form_name   = condense( CONV string( is_mig-FormName ) )
                      system_id   = is_mig-SystemId
                      branch_name = condense( CONV string( is_mig-BranchName ) )
                      form_slug   = condense( CONV string( is_mig-FormSlug ) )
                      serial_no   = is_mig-SerialNo ).
  ENDMETHOD.


  METHOD actor_of.
    rv_actor = SWITCH #( iv_heading
                 WHEN `Manual activity confirmed` OR `Problem reported` OR `Question` OR `Change requested`
                   OR `Concern raised` OR `Stop requested` OR `Resumed` THEN `client`
                 WHEN `Queued` THEN `app`
                 ELSE `engineer` ).
  ENDMETHOD.


  METHOD read_migrations.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS
      WITH VALUE #( FOR lv_uuid IN it_uuid ( MigUuid = CONV #( lv_uuid ) ) )
      RESULT rt_mig.
  ENDMETHOD.


  METHOD add_log.
    DATA lt_cba TYPE TABLE FOR CREATE zi_bolt_migration\\Migration\_Log.
    APPEND VALUE #( %tky    = is_mig-%tky
                    %target = VALUE #( ( %cid      = next_cid( )
                                         LogSource = 'APP'
                                         SeqNo     = 0
                                         EntryAt   = zcl_bolt_config=>iso_now( )
                                         Heading   = substring( val = iv_heading len = nmin( val1 = 120 val2 = strlen( iv_heading ) ) )
                                         Actor     = iv_actor
                                         LogText   = iv_text
                                         CreatedAt = zcl_bolt_config=>now( ) ) ) ) TO lt_cba.
    MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration
        CREATE BY \_Log
        FIELDS ( LogSource SeqNo EntryAt Heading Actor LogText CreatedAt )
        WITH lt_cba.
  ENDMETHOD.


  METHOD add_files.
    DATA lt_cba TYPE TABLE FOR CREATE zi_bolt_migration\\Migration\_File.
    IF it_files IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_now) = zcl_bolt_config=>now( ).
    APPEND VALUE #( %tky    = is_mig-%tky
                    %target = VALUE #( FOR ls_file IN it_files
                                       ( %cid      = next_cid( )
                                         FilePath  = ls_file-path
                                         FileName  = ls_file-name
                                         Kind      = ls_file-kind
                                         SizeBytes = ls_file-size
                                         PushedAt  = lv_now
                                         CreatedBy = sy-uname ) ) ) TO lt_cba.
    MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration
        CREATE BY \_File
        FIELDS ( FilePath FileName Kind SizeBytes PushedAt CreatedBy )
        WITH lt_cba.
  ENDMETHOD.


  METHOD apply_read.
    DATA lt_del TYPE TABLE FOR DELETE zi_bolt_migration\\MigrationLog.
    DATA lt_cba TYPE TABLE FOR CREATE zi_bolt_migration\\Migration\_Log.

    DATA(lv_now) = zcl_bolt_config=>now( ).
    IF is_read-found = abap_false.
      MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
        ENTITY Migration
          UPDATE FIELDS ( LastSyncAt )
          WITH VALUE #( ( %tky = is_mig-%tky LastSyncAt = lv_now ) ).
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration
        UPDATE FIELDS ( Status StatusLabel WaitingOn StatusNote StopFlag ClaimedBy StatusUpdated StatusSha LastSyncAt )
        WITH VALUE #( ( %tky          = is_mig-%tky
                        Status        = is_read-status-status
                        StatusLabel   = is_read-status-label
                        WaitingOn     = is_read-status-waiting_on
                        StatusNote    = is_read-status-note
                        StopFlag      = is_read-status-stop
                        ClaimedBy     = is_read-status-claimed_by
                        StatusUpdated = is_read-status-updated_at
                        StatusSha     = is_read-sha
                        LastSyncAt    = lv_now ) ).

    " Same file as last time - the timeline rows are already current.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration BY \_Log
        FIELDS ( LogSource )
        WITH VALUE #( ( %tky = is_mig-%tky ) )
      RESULT DATA(lt_logs).
    IF is_read-sha IS NOT INITIAL AND is_read-sha = is_mig-StatusSha
       AND line_exists( lt_logs[ LogSource = 'STATUS' ] ).
      RETURN.
    ENDIF.

    lt_del = VALUE #( FOR ls_log IN lt_logs WHERE ( LogSource = 'STATUS' ) ( %tky = ls_log-%tky ) ).
    IF lt_del IS NOT INITIAL.
      MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
        ENTITY MigrationLog
          DELETE FROM lt_del.
    ENDIF.

    IF is_read-entries IS INITIAL.
      RETURN.
    ENDIF.
    APPEND VALUE #( %tky    = is_mig-%tky
                    %target = VALUE #( FOR ls_entry IN is_read-entries INDEX INTO lv_index
                                       ( %cid      = next_cid( )
                                         LogSource = 'STATUS'
                                         SeqNo     = lv_index
                                         EntryAt   = ls_entry-at
                                         Heading   = substring( val = ls_entry-heading
                                                                len = nmin( val1 = 120 val2 = strlen( ls_entry-heading ) ) )
                                         Actor     = actor_of( ls_entry-heading )
                                         LogText   = ls_entry-text
                                         CreatedAt = lv_now ) ) ) TO lt_cba.
    MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration
        CREATE BY \_Log
        FIELDS ( LogSource SeqNo EntryAt Heading Actor LogText CreatedAt )
        WITH lt_cba.
  ENDMETHOD.


  METHOD commitselection.
    DATA lt_create  TYPE TABLE FOR CREATE zi_bolt_migration\\Migration.
    DATA lt_log_cba TYPE TABLE FOR CREATE zi_bolt_migration\\Migration\_Log.
    DATA lv_form    TYPE tdsfname.
    DATA lv_desc    TYPE string.

    DATA(ls_key) = keys[ 1 ].
    DATA(ls_setup) = zcl_bolt_config=>get_setup( ).
    IF ls_setup-gh_destination IS INITIAL OR ls_setup-gh_owner IS INITIAL OR ls_setup-gh_repo IS INITIAL.
      APPEND VALUE #( %cid = ls_key-%cid ) TO failed-migration.
      APPEND VALUE #( %cid = ls_key-%cid
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                    text     = `Connect GitHub in Configuration first.` ) ) TO reported-migration.
      RETURN.
    ENDIF.
    DATA(ls_system) = zcl_bolt_config=>get_system( ls_key-%param-SystemId ).
    IF ls_system IS INITIAL.
      APPEND VALUE #( %cid = ls_key-%cid ) TO failed-migration.
      APPEND VALUE #( %cid = ls_key-%cid
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                    text     = |Source system { ls_key-%param-SystemId } is not configured.| ) )
        TO reported-migration.
      RETURN.
    ENDIF.

    " Forms already in migration can't be selected again (one form = one branch).
    SELECT form_name, serial_no FROM zbolt_mig
      WHERE withdrawn = @space
      ORDER BY form_name
      INTO TABLE @DATA(lt_taken).
    SELECT MAX( serial_no ) FROM zbolt_mig INTO @DATA(lv_serial).

    DATA(lv_prefix) = COND string( WHEN ls_setup-gh_branch_prefix IS NOT INITIAL
                                   THEN condense( CONV string( ls_setup-gh_branch_prefix ) ) ).
    DATA(lv_selection) = ls_key-%param-Selection.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_selection WITH cl_abap_char_utilities=>newline.
    SPLIT lv_selection AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).

    DATA lt_seen TYPE string_table.
    LOOP AT lt_lines INTO DATA(lv_line).
      CLEAR: lv_form, lv_desc.
      SPLIT lv_line AT '|' INTO DATA(lv_name_raw) lv_desc.
      DATA(lv_name) = to_upper( condense( lv_name_raw ) ).
      IF lv_name IS INITIAL OR line_exists( lt_seen[ table_line = lv_name ] ).
        CONTINUE.
      ENDIF.
      APPEND lv_name TO lt_seen.
      lv_form = lv_name.

      READ TABLE lt_taken INTO DATA(ls_taken) WITH KEY form_name = lv_form BINARY SEARCH.
      IF sy-subrc = 0.
        APPEND VALUE #( %cid = ls_key-%cid
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                      text     = |{ lv_name } is already in migration (serial no. { ls_taken-serial_no }) - skipped.| ) )
          TO reported-migration.
        CONTINUE.
      ENDIF.

      lv_serial += 1.
      DATA(lv_cid) = next_cid( ).
      APPEND VALUE #( %cid            = lv_cid
                      SerialNo        = lv_serial
                      FormName        = lv_form
                      FormDescription = condense( lv_desc )
                      SystemId        = ls_system-system_id
                      SapClient       = ls_system-sap_client
                      BranchName      = zcl_bolt_status_file=>branch_name( iv_display_name = lv_name iv_prefix = lv_prefix )
                      FormSlug        = zcl_bolt_status_file=>form_slug( lv_name )
                      PushStatus      = zcl_bolt_config=>gc_push-pending
                      PushAttempts    = 0
                      StatusLabel     = `Sending to GitHub`
                      Withdrawn       = abap_false ) TO lt_create.
      APPEND VALUE #( %cid_ref = lv_cid
                      %target  = VALUE #( ( %cid      = next_cid( )
                                            LogSource = 'APP'
                                            SeqNo     = 0
                                            EntryAt   = zcl_bolt_config=>iso_now( )
                                            Heading   = `Selected for migration`
                                            Actor     = `client`
                                            LogText   = |Selected and committed by SAP user { sy-uname } from system { ls_system-system_id }| &&
                                                        |{ COND string( WHEN ls_system-sap_client IS NOT INITIAL THEN | client { ls_system-sap_client }| ) } | &&
                                                        |(serial no. { lv_serial }).|
                                            CreatedAt = zcl_bolt_config=>now( ) ) ) ) TO lt_log_cba.
    ENDLOOP.

    IF lt_create IS INITIAL.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration
        CREATE FIELDS ( SerialNo FormName FormDescription SystemId SapClient BranchName FormSlug
                        PushStatus PushAttempts StatusLabel Withdrawn )
        WITH lt_create
        CREATE BY \_Log
        FIELDS ( LogSource SeqNo EntryAt Heading Actor LogText CreatedAt )
        WITH lt_log_cba
      MAPPED DATA(ls_mapped)
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS
      WITH VALUE #( FOR ls_map IN ls_mapped-migration ( %tky = ls_map-%tky ) )
      RESULT DATA(lt_new).
    result = VALUE #( FOR ls_new IN lt_new ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_new ) ) ).
  ENDMETHOD.


  METHOD pushtogithub.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      IF ls_mig-Withdrawn = abap_true.
        APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
        APPEND VALUE #( %tky = ls_mig-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |{ ls_mig-FormName } was withdrawn.| ) ) TO reported-migration.
        CONTINUE.
      ENDIF.
      IF ls_mig-PushStatus = zcl_bolt_config=>gc_push-pushed.
        APPEND VALUE #( %tky = ls_mig-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-information
                                                      text     = |{ ls_mig-FormName } is already on GitHub.| ) ) TO reported-migration.
        CONTINUE.
      ENDIF.

      TRY.
          DATA(ls_push) = zcl_bolt_migration_svc=>push( to_svc( ls_mig ) ).
          DATA(lv_summary) = COND string(
            WHEN ls_push-adopted = abap_true
            THEN |Branch { ls_mig-BranchName } was already on GitHub with its status file (an earlier send whose save did not finish) - linked to it, nothing overwritten.|
            ELSE |Created branch { ls_mig-BranchName } and pushed { lines( ls_push-files ) } reference file(s) and the status file in one commit.| ).
          MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
            ENTITY Migration
              UPDATE FIELDS ( PushStatus PushMessage PushAttempts PushedAt FilesPushed CommitSha Complexity ComplexityText )
              WITH VALUE #( ( %tky           = ls_mig-%tky
                              PushStatus     = zcl_bolt_config=>gc_push-pushed
                              PushMessage    = lv_summary
                              PushAttempts   = ls_mig-PushAttempts + 1
                              PushedAt       = zcl_bolt_config=>now( )
                              FilesPushed    = lines( ls_push-files )
                              CommitSha      = ls_push-commit_sha
                              Complexity     = ls_push-complexity
                              ComplexityText = ls_push-complexity_text ) ).
          add_files( is_mig = ls_mig it_files = ls_push-files ).
          add_log( is_mig = ls_mig iv_heading = `Sent to GitHub` iv_text = lv_summary ).
          IF ls_push-complexity IS NOT INITIAL.
            add_log( is_mig     = ls_mig
                     iv_heading = `Complexity signal`
                     iv_text    = |{ to_upper( ls_push-complexity ) } - { ls_push-complexity_text } | &&
                                  |(structural read of the layout only - not the full risk score, which also needs business | &&
                                  |criticality, driver complexity and volume).| ).
          ENDIF.
          LOOP AT ls_push-warnings INTO DATA(lv_warning).
            add_log( is_mig = ls_mig iv_heading = `Warning` iv_text = lv_warning ).
          ENDLOOP.
          apply_read( is_mig = ls_mig is_read = ls_push-read ).
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                        text     = |{ ls_mig-FormName } sent to GitHub.| ) ) TO reported-migration.

        CATCH zcx_bolt INTO DATA(lx_error).
          DATA(lv_text) = lx_error->get_text( ).
          MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
            ENTITY Migration
              UPDATE FIELDS ( PushStatus PushMessage PushAttempts StatusLabel )
              WITH VALUE #( ( %tky         = ls_mig-%tky
                              PushStatus   = zcl_bolt_config=>gc_push-failed
                              PushMessage  = lv_text
                              PushAttempts = ls_mig-PushAttempts + 1
                              StatusLabel  = `Sending failed` ) ).
          add_log( is_mig = ls_mig iv_heading = `Sending to GitHub failed` iv_text = lv_text ).
          " Warning, not failed: the FAILED state and its reason must be saved.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                        text     = |{ ls_mig-FormName }: { lv_text }| ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after WHERE ( Withdrawn = abap_false )
                      ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD refreshstatus.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      IF ls_mig-PushStatus <> zcl_bolt_config=>gc_push-pushed.
        CONTINUE.
      ENDIF.
      TRY.
          apply_read( is_mig = ls_mig is_read = zcl_bolt_migration_svc=>read_status( to_svc( ls_mig ) ) ).
        CATCH zcx_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                        text     = |{ ls_mig-FormName }: { lx_error->get_text( ) }| ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD refreshall.
    DATA lt_uuid TYPE string_table.

    DATA(ls_key) = keys[ 1 ].
    DATA(lv_pushed) = zcl_bolt_config=>gc_push-pushed.
    SELECT mig_uuid, status, last_sync_at FROM zbolt_mig
      WHERE withdrawn = @space AND push_status = @lv_pushed
      ORDER BY serial_no
      INTO TABLE @DATA(lt_rows).

    " A completed migration rarely changes - read it again at most once a day
    " (its own Refresh button always reads it).
    DATA lv_today  TYPE c LENGTH 22.
    DATA lv_synced TYPE c LENGTH 22.
    lv_today = |{ zcl_bolt_config=>now( ) DECIMALS = 0 }|.
    LOOP AT lt_rows INTO DATA(ls_row).
      lv_synced = |{ ls_row-last_sync_at DECIMALS = 0 }|.
      IF ls_row-status = 'completed' AND ls_row-last_sync_at IS NOT INITIAL AND lv_synced(8) = lv_today(8).
        CONTINUE.
      ENDIF.
      APPEND CONV string( ls_row-mig_uuid ) TO lt_uuid.
    ENDLOOP.

    DATA(lt_mig) = read_migrations( lt_uuid ).
    DATA lv_errors TYPE i.
    LOOP AT lt_mig INTO DATA(ls_mig).
      TRY.
          apply_read( is_mig = ls_mig is_read = zcl_bolt_migration_svc=>read_status( to_svc( ls_mig ) ) ).
        CATCH zcx_bolt INTO DATA(lx_error).
          lv_errors += 1.
          IF lv_errors <= 3.
            APPEND VALUE #( %cid = ls_key-%cid
                            %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                          text     = |{ ls_mig-FormName }: { lx_error->get_text( ) }| ) ) TO reported-migration.
          ENDIF.
      ENDTRY.
    ENDLOOP.

    DATA(lt_after) = read_migrations( lt_uuid ).
    result = VALUE #( FOR ls_after IN lt_after ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD importfromgithub.
    DATA lt_create  TYPE TABLE FOR CREATE zi_bolt_migration\\Migration.
    DATA lt_log_cba TYPE TABLE FOR CREATE zi_bolt_migration\\Migration\_Log.
    DATA lt_known   TYPE string_table.

    DATA(ls_key) = keys[ 1 ].
    SELECT branch_name FROM zbolt_mig INTO TABLE @DATA(lt_branches).
    lt_known = VALUE #( FOR ls_branch IN lt_branches ( condense( CONV string( ls_branch-branch_name ) ) ) ).
    SORT lt_known.

    TRY.
        DATA(lt_imports) = zcl_bolt_migration_svc=>import_branches( lt_known ).
      CATCH zcx_bolt INTO DATA(lx_error).
        APPEND VALUE #( %cid = ls_key-%cid ) TO failed-migration.
        APPEND VALUE #( %cid = ls_key-%cid
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = lx_error->get_text( ) ) ) TO reported-migration.
        RETURN.
    ENDTRY.
    IF lt_imports IS INITIAL.
      APPEND VALUE #( %cid = ls_key-%cid
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-information
                                                    text     = `No migration branches on GitHub that this app does not know yet.` ) )
        TO reported-migration.
      RETURN.
    ENDIF.

    SELECT MAX( serial_no ) FROM zbolt_mig INTO @DATA(lv_serial).
    DATA(ls_system) = zcl_bolt_config=>get_default_system( ).
    DATA(lv_now) = zcl_bolt_config=>now( ).

    LOOP AT lt_imports INTO DATA(ls_import).
      lv_serial += 1.
      DATA(lv_cid) = next_cid( ).
      APPEND VALUE #( %cid          = lv_cid
                      SerialNo      = lv_serial
                      FormName      = ls_import-form_name
                      SystemId      = ls_system-system_id
                      SapClient     = ls_system-sap_client
                      BranchName    = ls_import-branch_name
                      FormSlug      = ls_import-form_slug
                      PushStatus    = zcl_bolt_config=>gc_push-pushed
                      PushMessage   = `Imported from GitHub - created before this app (e.g. by the Bolt web console).`
                      PushedAt      = lv_now
                      Status        = ls_import-read-status-status
                      StatusLabel   = ls_import-read-status-label
                      WaitingOn     = ls_import-read-status-waiting_on
                      StatusNote    = ls_import-read-status-note
                      StopFlag      = ls_import-read-status-stop
                      ClaimedBy     = ls_import-read-status-claimed_by
                      StatusUpdated = ls_import-read-status-updated_at
                      StatusSha     = ls_import-read-sha
                      LastSyncAt    = lv_now
                      Withdrawn     = abap_false ) TO lt_create.

      APPEND VALUE #( %cid_ref = lv_cid ) TO lt_log_cba ASSIGNING FIELD-SYMBOL(<lfs_cba>).
      APPEND VALUE #( %cid      = next_cid( )
                      LogSource = 'APP'
                      SeqNo     = 0
                      EntryAt   = zcl_bolt_config=>iso_now( )
                      Heading   = `Imported from GitHub`
                      Actor     = `app`
                      LogText   = |Branch { ls_import-branch_name } existed on GitHub before this app; imported by { sy-uname }.|
                      CreatedAt = lv_now ) TO <lfs_cba>-%target.
      LOOP AT ls_import-read-entries INTO DATA(ls_entry).
        DATA(lv_index) = sy-tabix.
        APPEND VALUE #( %cid      = next_cid( )
                        LogSource = 'STATUS'
                        SeqNo     = lv_index
                        EntryAt   = ls_entry-at
                        Heading   = substring( val = ls_entry-heading
                                               len = nmin( val1 = 120 val2 = strlen( ls_entry-heading ) ) )
                        Actor     = actor_of( ls_entry-heading )
                        LogText   = ls_entry-text
                        CreatedAt = lv_now ) TO <lfs_cba>-%target.
      ENDLOOP.
    ENDLOOP.

    MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration
        CREATE FIELDS ( SerialNo FormName SystemId SapClient BranchName FormSlug PushStatus PushMessage PushedAt
                        Status StatusLabel WaitingOn StatusNote StopFlag ClaimedBy StatusUpdated StatusSha
                        LastSyncAt Withdrawn )
        WITH lt_create
        CREATE BY \_Log
        FIELDS ( LogSource SeqNo EntryAt Heading Actor LogText CreatedAt )
        WITH lt_log_cba
      MAPPED DATA(ls_mapped)
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS
      WITH VALUE #( FOR ls_map IN ls_mapped-migration ( %tky = ls_map-%tky ) )
      RESULT DATA(lt_new).
    result = VALUE #( FOR ls_new IN lt_new ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_new ) ) ).
  ENDMETHOD.


  METHOD confirmmanual.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      TRY.
          DATA(ls_action) = zcl_bolt_migration_svc=>confirm( is_mig       = to_svc( ls_mig )
                                                             iv_note      = ls_key-%param-Note
                                                             iv_file_name = CONV #( ls_key-%param-FileName )
                                                             iv_file_b64  = ls_key-%param-FileContent ).
          add_files( is_mig = ls_mig it_files = ls_action-files ).
          add_log( is_mig     = ls_mig
                   iv_heading = `Confirmed the manual step`
                   iv_text    = COND #( WHEN ls_key-%param-Note IS NOT INITIAL THEN ls_key-%param-Note
                                        ELSE `Confirmed without a note.` )
                   iv_actor   = `client` ).
          apply_read( is_mig = ls_mig is_read = ls_action-read ).
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text(
                                   severity = if_abap_behv_message=>severity-success
                                   text     = `Confirmation submitted - the engineer has been notified and the migration is now In Progress.` ) )
            TO reported-migration.
        CATCH zcx_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD raiseconcern.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      TRY.
          DATA(ls_action) = zcl_bolt_migration_svc=>concern( is_mig       = to_svc( ls_mig )
                                                             iv_kind      = condense( CONV string( ls_key-%param-Kind ) )
                                                             iv_text      = ls_key-%param-Text
                                                             iv_file_name = CONV #( ls_key-%param-FileName )
                                                             iv_file_b64  = ls_key-%param-FileContent ).
          add_files( is_mig = ls_mig it_files = ls_action-files ).
          add_log( is_mig = ls_mig iv_heading = `Raised a concern` iv_text = ls_key-%param-Text iv_actor = `client` ).
          apply_read( is_mig = ls_mig is_read = ls_action-read ).
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                        text     = `Submitted - the engineer has been notified.` ) )
            TO reported-migration.
        CATCH zcx_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD setstop.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      DATA(lv_stop) = xsdbool( ls_key-%param-StopRequested = abap_true ).
      TRY.
          DATA(ls_read) = zcl_bolt_migration_svc=>set_stop( is_mig  = to_svc( ls_mig )
                                                            iv_stop = lv_stop
                                                            iv_note = ls_key-%param-Note ).
          add_log( is_mig     = ls_mig
                   iv_heading = COND #( WHEN lv_stop = abap_true THEN `Requested a stop` ELSE `Resumed the migration` )
                   iv_text    = ls_key-%param-Note
                   iv_actor   = `client` ).
          apply_read( is_mig = ls_mig is_read = ls_read ).
        CATCH zcx_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD addreferencefile.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      IF ls_mig-PushStatus <> zcl_bolt_config=>gc_push-pushed.
        APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
        APPEND VALUE #( %tky = ls_mig-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `Send the migration to GitHub first.` ) ) TO reported-migration.
        CONTINUE.
      ENDIF.
      TRY.
          DATA(ls_file) = zcl_bolt_migration_svc=>add_reference_file( is_mig       = to_svc( ls_mig )
                                                                      iv_file_name = CONV #( ls_key-%param-FileName )
                                                                      iv_file_b64  = ls_key-%param-FileContent ).
          add_files( is_mig = ls_mig it_files = VALUE #( ( ls_file ) ) ).
          add_log( is_mig     = ls_mig
                   iv_heading = `Attached a reference file`
                   iv_text    = |{ ls_file-name } ({ ls_file-size } bytes) pushed to { ls_file-path }.|
                   iv_actor   = `client` ).
        CATCH zcx_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD withdraw.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      READ TABLE keys INTO DATA(ls_key) WITH KEY MigUuid = ls_mig-MigUuid.
      IF zcl_bolt_config=>is_admin( ) = abap_false.
        APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
        APPEND VALUE #( %tky = ls_mig-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `Only an administrator (Configuration > Administrators) can withdraw a migration.` ) )
          TO reported-migration.
        CONTINUE.
      ENDIF.
      TRY.
          DATA(lv_branch_note) = ``.
          IF ls_key-%param-DeleteBranch = abap_true AND ls_mig-PushStatus = zcl_bolt_config=>gc_push-pushed.
            zcl_bolt_migration_svc=>delete_branch( to_svc( ls_mig ) ).
            lv_branch_note = | Branch { ls_mig-BranchName } deleted on GitHub.|.
          ENDIF.
          MODIFY ENTITIES OF zi_bolt_migration IN LOCAL MODE
            ENTITY Migration
              UPDATE FIELDS ( Withdrawn PushStatus StatusLabel )
              WITH VALUE #( ( %tky        = ls_mig-%tky
                              Withdrawn   = abap_true
                              PushStatus  = zcl_bolt_config=>gc_push-withdrawn
                              StatusLabel = `Withdrawn` ) ).
          add_log( is_mig     = ls_mig
                   iv_heading = `Withdrawn`
                   iv_text    = |Withdrawn by { sy-uname }.{ lv_branch_note } { ls_key-%param-Reason }| ).
        CATCH zcx_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD aisummary.
    READ ENTITIES OF zi_bolt_migration IN LOCAL MODE
      ENTITY Migration ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_mig).

    LOOP AT lt_mig INTO DATA(ls_mig).
      TRY.
          DATA(lv_text) = zcl_bolt_migration_svc=>ai_summary( to_svc( ls_mig ) ).
          add_log( is_mig = ls_mig iv_heading = `AI summary` iv_text = lv_text ).
          APPEND VALUE #( %tky = ls_mig-%tky %param-ResultText = lv_text ) TO result.
        CATCH zcx_bolt INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_mig-%tky ) TO failed-migration.
          APPEND VALUE #( %tky = ls_mig-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->get_text( ) ) ) TO reported-migration.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
