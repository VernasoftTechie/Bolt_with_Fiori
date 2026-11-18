*&---------------------------------------------------------------------*
*& Report ZBOLT_R_SYNC
*&---------------------------------------------------------------------*
*& Bolt with Fiori - background safety net (schedule every 5-15 minutes
*& in SM36, see docs/04_installation.md):
*&   1. sends every migration still PENDING or FAILED to GitHub again
*&      (one commit per form, attempts capped by P_MAX) - covers a browser
*&      closed mid-send and a GitHub/network outage, the same job Bolt
*&      Console's branch reconciler did;
*&   2. reads the status file of every active migration from GitHub, so the
*&      Migration tab is current even before anyone presses Refresh.
*& Runs the business object's own actions (EML) - no separate logic.
*&---------------------------------------------------------------------*
REPORT zbolt_r_sync.

PARAMETERS p_push AS CHECKBOX DEFAULT abap_true.
PARAMETERS p_stat AS CHECKBOX DEFAULT abap_true.
PARAMETERS p_max  TYPE i DEFAULT 10.

START-OF-SELECTION.

  IF p_push = abap_true.
    DATA(lv_pending) = zcl_bolt_config=>gc_push-pending.
    DATA(lv_failed)  = zcl_bolt_config=>gc_push-failed.
    SELECT mig_uuid, form_name FROM zbolt_mig
      WHERE withdrawn = @space
        AND ( push_status = @lv_pending OR push_status = @lv_failed )
        AND push_attempts < @p_max
      ORDER BY serial_no
      INTO TABLE @DATA(lt_push).

    WRITE: / |Sending { lines( lt_push ) } migration(s) to GitHub.|.
    LOOP AT lt_push INTO DATA(ls_push).
      MODIFY ENTITIES OF zi_bolt_migration
        ENTITY Migration
          EXECUTE pushToGitHub FROM VALUE #( ( MigUuid = ls_push-mig_uuid ) )
        FAILED DATA(ls_push_failed)
        REPORTED DATA(ls_push_reported).
      COMMIT ENTITIES.
      LOOP AT ls_push_reported-migration INTO DATA(ls_push_msg) WHERE %msg IS BOUND.
        WRITE: / |  { ls_push-form_name }: { ls_push_msg-%msg->if_message~get_text( ) }|.
      ENDLOOP.
      IF ls_push_failed-migration IS NOT INITIAL.
        WRITE: / |  { ls_push-form_name }: not sent.|.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF p_stat = abap_true.
    MODIFY ENTITIES OF zi_bolt_migration
      ENTITY Migration
        EXECUTE refreshAll FROM VALUE #( ( %cid = 'SYNC' ) )
      RESULT DATA(lt_refreshed)
      FAILED DATA(ls_stat_failed)
      REPORTED DATA(ls_stat_reported).
    COMMIT ENTITIES.
    WRITE: / |Status read from GitHub for { lines( lt_refreshed ) } migration(s).|.
    LOOP AT ls_stat_reported-migration INTO DATA(ls_stat_msg) WHERE %msg IS BOUND.
      WRITE: / |  { ls_stat_msg-%msg->if_message~get_text( ) }|.
    ENDLOOP.
    IF ls_stat_failed-migration IS NOT INITIAL.
      WRITE: / `  The status refresh reported an error - see the messages above.`.
    ENDIF.
  ENDIF.
