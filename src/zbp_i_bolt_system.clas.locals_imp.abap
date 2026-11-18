CLASS lhc_sourcesystem DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR SourceSystem RESULT result.

    METHODS testconnection FOR MODIFY
      IMPORTING keys FOR ACTION SourceSystem~testConnection RESULT result.
ENDCLASS.


CLASS lhc_sourcesystem IMPLEMENTATION.

  METHOD get_global_authorizations.
    " Adding/changing/removing a system is an administrator task.
    DATA(lv_admin) = COND #( WHEN zcl_bolt_config=>is_admin( ) = abap_true
                             THEN if_abap_behv=>auth-allowed
                             ELSE if_abap_behv=>auth-unauthorized ).
    result = VALUE #( %create                = lv_admin
                      %update                = lv_admin
                      %delete                = lv_admin
                      %action-testConnection = if_abap_behv=>auth-allowed ).
  ENDMETHOD.


  METHOD testconnection.
    READ ENTITIES OF zi_bolt_system IN LOCAL MODE
      ENTITY SourceSystem ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_systems).

    LOOP AT lt_systems INTO DATA(ls_system).
      DATA lv_status TYPE zbolt_system-status.
      DATA lv_text   TYPE string.
      DATA(ls_row) = VALUE zbolt_system( system_id    = ls_system-SystemId
                                         sap_client   = ls_system-SapClient
                                         destination  = ls_system-Destination
                                         service_path = ls_system-ServicePath
                                         is_local     = ls_system-IsLocal ).
      TRY.
          lv_text   = zcl_bolt_source=>test_system( ls_row ).
          lv_status = zcl_bolt_config=>gc_ok.
        CATCH zcx_bolt INTO DATA(lx_error).
          lv_text   = lx_error->get_text( ).
          lv_status = zcl_bolt_config=>gc_error.
      ENDTRY.
      MODIFY ENTITIES OF zi_bolt_system IN LOCAL MODE
        ENTITY SourceSystem
          UPDATE FIELDS ( Status StatusText CheckedAt )
          WITH VALUE #( ( %tky       = ls_system-%tky
                          Status     = lv_status
                          StatusText = substring( val = lv_text len = nmin( val1 = 255 val2 = strlen( lv_text ) ) )
                          CheckedAt  = zcl_bolt_config=>now( ) ) ).
      APPEND VALUE #( %tky = ls_system-%tky
                      %msg = new_message_with_text(
                               severity = COND #( WHEN lv_status = zcl_bolt_config=>gc_ok
                                                  THEN if_abap_behv_message=>severity-success
                                                  ELSE if_abap_behv_message=>severity-warning )
                               text     = lv_text ) ) TO reported-sourcesystem.
    ENDLOOP.

    READ ENTITIES OF zi_bolt_system IN LOCAL MODE
      ENTITY SourceSystem ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.

ENDCLASS.
