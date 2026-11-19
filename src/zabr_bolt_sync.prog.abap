*&---------------------------------------------------------------------*
*& Report ZABR_BOLT_SYNC
*&---------------------------------------------------------------------*
*& Bolt - background job (Z_AB_HR_BOLT_SYNC, every 15 minutes):
*&   1. sends every committed migration that is not on GitHub yet (PENDING)
*&      or whose send failed (FAILED), up to P_MAX attempts - the web app's
*&      "auto-heal" of a failed branch creation
*&   2. reads the status file of every open migration from its branch, so
*&      the Migration tab and the history table are current even when nobody
*&      has the app open.
*& Through the RAP business object (EML), exactly as the Fiori app does.
*&---------------------------------------------------------------------*
REPORT zabr_bolt_sync.

PARAMETERS cb_push AS CHECKBOX DEFAULT abap_true.
PARAMETERS cb_stat AS CHECKBOX DEFAULT abap_true.
PARAMETERS p_max   TYPE i DEFAULT 5.

START-OF-SELECTION.
  DATA gt_push TYPE TABLE FOR ACTION IMPORT zab_cds_i_bolt_mig\\Migration~pushToGitHub.

  IF cb_push = abap_true.
    SELECT mig_uuid, form_name, push_attempts FROM zabt_bolt_mig
      WHERE ( push_status = @zcl_ab_bolt_config=>gc_push-pending OR push_status = @zcl_ab_bolt_config=>gc_push-failed )
        AND stopped    = @abap_false
        AND superseded = @abap_false
        AND push_attempts < @p_max
      ORDER BY serial_no
      INTO TABLE @DATA(gt_open).
    WRITE: / |{ lines( gt_open ) } migration(s) to send to GitHub.|.

    " One migration per LUW: a slow or failing one never holds back the others.
    LOOP AT gt_open INTO DATA(gs_open).
      gt_push = VALUE #( ( MigUuid = gs_open-mig_uuid ) ).
      MODIFY ENTITIES OF zab_cds_i_bolt_mig
        ENTITY Migration
          EXECUTE pushToGitHub FROM gt_push
        RESULT DATA(gt_result)
        FAILED DATA(gs_failed)
        REPORTED DATA(gs_reported).
      COMMIT ENTITIES RESPONSE OF zab_cds_i_bolt_mig
        FAILED DATA(gs_commit_failed)
        REPORTED DATA(gs_commit_reported).
      DATA(gv_state) = COND string( WHEN gs_failed IS NOT INITIAL OR gs_commit_failed IS NOT INITIAL THEN `refused`
                                    WHEN gt_result IS NOT INITIAL THEN CONV string( gt_result[ 1 ]-%param-PushStatus )
                                    ELSE `?` ).
      WRITE: / gs_open-form_name, gv_state.
      LOOP AT gs_reported-migration INTO DATA(gs_msg).
        IF gs_msg-%msg IS BOUND.
          WRITE: / `   `, gs_msg-%msg->if_message~get_text( ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDIF.

  IF cb_stat = abap_true.
    MODIFY ENTITIES OF zab_cds_i_bolt_mig
      ENTITY Migration
        EXECUTE refreshAll FROM VALUE #( ( %cid = 'SYNC' ) )
      RESULT DATA(gt_refreshed)
      REPORTED DATA(gs_refresh_reported).
    COMMIT ENTITIES.
    WRITE: / |Status read from GitHub for { lines( gt_refreshed ) } open migration(s).|.
    LOOP AT gs_refresh_reported-migration INTO DATA(gs_rmsg).
      IF gs_rmsg-%msg IS BOUND.
        WRITE: / `   `, gs_rmsg-%msg->if_message~get_text( ).
      ENDIF.
    ENDLOOP.
  ENDIF.
