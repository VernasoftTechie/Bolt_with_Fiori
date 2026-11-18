"! Buffer between setAiKey (interaction phase) and the saver (save phase):
"! the API key is written to ZBOLT_SECRET only in save_modified, the
"! RAP-sanctioned place for additional database writes.
CLASS lcl_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA gv_key_pending TYPE abap_bool.
    CLASS-DATA gv_key         TYPE string.
ENDCLASS.


CLASS lhc_setup DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Setup RESULT result.

    METHODS initialize FOR MODIFY
      IMPORTING keys FOR ACTION Setup~initialize RESULT result.

    METHODS testgithub FOR MODIFY
      IMPORTING keys FOR ACTION Setup~testGitHub RESULT result.

    METHODS testai FOR MODIFY
      IMPORTING keys FOR ACTION Setup~testAi RESULT result.

    METHODS setaikey FOR MODIFY
      IMPORTING keys FOR ACTION Setup~setAiKey RESULT result.
ENDCLASS.


CLASS lhc_setup IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Changing the connections is an administrator task (Configuration >
    " Administrators; blank list = everyone). Running the tests is not.
    DATA(lv_admin) = COND #( WHEN zcl_bolt_config=>is_admin( ) = abap_true
                             THEN if_abap_behv=>auth-allowed
                             ELSE if_abap_behv=>auth-unauthorized ).
    result = VALUE #( %update             = lv_admin
                      %action-initialize  = if_abap_behv=>auth-allowed
                      %action-testGitHub  = if_abap_behv=>auth-allowed
                      %action-testAi      = if_abap_behv=>auth-allowed
                      %action-setAiKey    = lv_admin ).
  ENDMETHOD.


  METHOD initialize.
    " Creates the one setup row (and a local DEV source system) the first time
    " the app opens; afterwards it only returns the existing row.
    DATA(ls_key) = keys[ 1 ].
    DATA(lv_id) = zcl_bolt_config=>gc_setup_id.

    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH VALUE #( ( SetupId = lv_id ) )
      RESULT DATA(lt_existing).

    IF lt_existing IS INITIAL.
      MODIFY ENTITIES OF zi_bolt_setup IN LOCAL MODE
        ENTITY Setup
          CREATE FIELDS ( SetupId CustomerName GhBaseBranch GhBranchPrefix AiProvider AiMaxTokens
                          FormPrefix1 FormPrefix2 CountVolume )
          WITH VALUE #( ( %cid           = 'SETUP'
                          SetupId        = lv_id
                          CustomerName   = ``
                          GhBaseBranch   = zcl_bolt_config=>gc_default_base
                          GhBranchPrefix = zcl_bolt_config=>gc_default_prefix
                          AiProvider     = zcl_bolt_config=>gc_provider_none
                          AiMaxTokens    = 2000
                          FormPrefix1    = 'Z'
                          FormPrefix2    = 'Y'
                          CountVolume    = abap_true ) ).

      " A first source system: this system itself.
      SELECT COUNT( * ) FROM zbolt_system INTO @DATA(lv_systems).
      IF lv_systems = 0.
        MODIFY ENTITIES OF zi_bolt_system
          ENTITY SourceSystem
            CREATE FIELDS ( SystemId Description SapClient ServicePath IsLocal IsDefault SortOrder )
            WITH VALUE #( ( %cid        = 'SYSTEM'
                            SystemId    = 'DEV'
                            Description = |This system ({ sy-sysid })|
                            SapClient   = sy-mandt
                            ServicePath = zcl_bolt_config=>gc_default_path
                            IsLocal     = abap_true
                            IsDefault   = abap_true
                            SortOrder   = 10 ) )
          FAILED DATA(ls_sys_failed)
          REPORTED DATA(ls_sys_reported).
        IF ls_sys_failed IS NOT INITIAL OR ls_sys_reported IS NOT INITIAL.
          " Not fatal: the system can always be added in Configuration > SAP systems.
          CLEAR: ls_sys_failed, ls_sys_reported.
        ENDIF.
      ENDIF.
    ENDIF.

    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH VALUE #( ( SetupId = lv_id ) )
      RESULT DATA(lt_setup).
    result = VALUE #( FOR ls_setup IN lt_setup ( %cid = ls_key-%cid %param = CORRESPONDING #( ls_setup ) ) ).
  ENDMETHOD.


  METHOD testgithub.
    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      DATA lv_status TYPE zbolt_setup-gh_status.
      DATA lv_text   TYPE string.
      TRY.
          lv_text = NEW zcl_bolt_github( iv_destination = ls_setup-GhDestination
                                         iv_owner       = CONV #( ls_setup-GhOwner )
                                         iv_repo        = CONV #( ls_setup-GhRepo ) )->test_access( ).
          lv_status = zcl_bolt_config=>gc_ok.
        CATCH zcx_bolt INTO DATA(lx_error).
          lv_text   = lx_error->get_text( ).
          lv_status = zcl_bolt_config=>gc_error.
      ENDTRY.
      MODIFY ENTITIES OF zi_bolt_setup IN LOCAL MODE
        ENTITY Setup
          UPDATE FIELDS ( GhStatus GhStatusText GhCheckedAt )
          WITH VALUE #( ( %tky         = ls_setup-%tky
                          GhStatus     = lv_status
                          GhStatusText = substring( val = lv_text len = nmin( val1 = 255 val2 = strlen( lv_text ) ) )
                          GhCheckedAt  = zcl_bolt_config=>now( ) ) ).
      APPEND VALUE #( %tky = ls_setup-%tky
                      %msg = new_message_with_text(
                               severity = COND #( WHEN lv_status = zcl_bolt_config=>gc_ok
                                                  THEN if_abap_behv_message=>severity-success
                                                  ELSE if_abap_behv_message=>severity-warning )
                               text     = lv_text ) ) TO reported-setup.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD testai.
    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      DATA lv_status TYPE zbolt_setup-ai_status.
      DATA lv_text   TYPE string.
      DATA(ls_row) = VALUE zbolt_setup( ai_provider    = ls_setup-AiProvider
                                        ai_model       = ls_setup-AiModel
                                        ai_destination = ls_setup-AiDestination
                                        ai_base_path   = ls_setup-AiBasePath
                                        ai_max_tokens  = ls_setup-AiMaxTokens ).
      TRY.
          lv_text   = zcl_bolt_ai=>test( ls_row ).
          lv_status = zcl_bolt_config=>gc_ok.
        CATCH zcx_bolt INTO DATA(lx_error).
          lv_text   = lx_error->get_text( ).
          lv_status = zcl_bolt_config=>gc_error.
      ENDTRY.
      MODIFY ENTITIES OF zi_bolt_setup IN LOCAL MODE
        ENTITY Setup
          UPDATE FIELDS ( AiStatus AiStatusText AiCheckedAt )
          WITH VALUE #( ( %tky         = ls_setup-%tky
                          AiStatus     = lv_status
                          AiStatusText = substring( val = lv_text len = nmin( val1 = 255 val2 = strlen( lv_text ) ) )
                          AiCheckedAt  = zcl_bolt_config=>now( ) ) ).
      APPEND VALUE #( %tky = ls_setup-%tky
                      %msg = new_message_with_text(
                               severity = COND #( WHEN lv_status = zcl_bolt_config=>gc_ok
                                                  THEN if_abap_behv_message=>severity-success
                                                  ELSE if_abap_behv_message=>severity-warning )
                               text     = lv_text ) ) TO reported-setup.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD setaikey.
    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_setup).

    LOOP AT lt_setup INTO DATA(ls_setup).
      READ TABLE keys INTO DATA(ls_key) WITH KEY SetupId = ls_setup-SetupId.
      DATA(lv_key) = condense( ls_key-%param-ApiKey ).
      lcl_buffer=>gv_key         = lv_key.
      lcl_buffer=>gv_key_pending = abap_true.
      MODIFY ENTITIES OF zi_bolt_setup IN LOCAL MODE
        ENTITY Setup
          UPDATE FIELDS ( AiKeySet AiStatus AiStatusText )
          WITH VALUE #( ( %tky         = ls_setup-%tky
                          AiKeySet     = xsdbool( lv_key IS NOT INITIAL )
                          AiStatus     = ``
                          AiStatusText = COND #( WHEN lv_key IS NOT INITIAL
                                                 THEN `API key saved - run Test connection.`
                                                 ELSE `API key removed.` ) ) ).
    ENDLOOP.

    READ ENTITIES OF zi_bolt_setup IN LOCAL MODE
      ENTITY Setup ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.

ENDCLASS.


CLASS lsc_zi_bolt_setup DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.
ENDCLASS.


CLASS lsc_zi_bolt_setup IMPLEMENTATION.

  METHOD save_modified.
    IF lcl_buffer=>gv_key_pending = abap_false.
      RETURN.
    ENDIF.
    DATA(lv_secret_id) = zcl_bolt_config=>gc_secret_ai_key.
    IF lcl_buffer=>gv_key IS INITIAL.
      DELETE FROM zbolt_secret WHERE secret_id = @lv_secret_id.
    ELSE.
      DATA(ls_secret) = VALUE zbolt_secret( secret_id    = lv_secret_id
                                            secret_value = lcl_buffer=>gv_key
                                            changed_by   = sy-uname
                                            changed_at   = zcl_bolt_config=>now( ) ).
      MODIFY zbolt_secret FROM @ls_secret.
    ENDIF.
    CLEAR: lcl_buffer=>gv_key, lcl_buffer=>gv_key_pending.
  ENDMETHOD.


  METHOD cleanup_finalize.
    CLEAR: lcl_buffer=>gv_key, lcl_buffer=>gv_key_pending.
  ENDMETHOD.

ENDCLASS.
