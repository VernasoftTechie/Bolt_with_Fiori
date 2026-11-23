"! <p class="shorttext synchronized">Bolt - system info query (ZAB_CDS_CE_BOLT_SYSINFO)</p>
"! One row about the system the app was launched in - there is no system
"! selection: the logged-on system is the source of the Smart Forms. Also
"! tells the screen whether the user is a Bolt administrator and whether
"! everything is connected (header chips + LIVE, same rule as the web app:
"! GitHub token + target repository with push access + AI provider ready).
CLASS zcl_ab_bolt_q_sysinfo DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

    CONSTANTS gc_version TYPE c LENGTH 20 VALUE '2.1.5'.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_ab_bolt_q_sysinfo IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA lt_rows TYPE STANDARD TABLE OF zab_cds_ce_bolt_sysinfo WITH EMPTY KEY.

    DATA(ls_setup) = zcl_ab_bolt_config=>get_setup( ).
    DATA(lv_token) = xsdbool( ls_setup-gh_token_set = abap_true ).
    DATA(lv_repo)  = xsdbool( lv_token = abap_true AND ls_setup-gh_repo IS NOT INITIAL AND ls_setup-gh_can_push = abap_true ).
    DATA(lv_ai)    = xsdbool( ls_setup IS NOT INITIAL AND zcl_ab_bolt_ai=>is_ready( ls_setup ) = abap_true ).
    SELECT COUNT( * ) FROM zabt_bolt_drvix INTO @DATA(lv_index).

    DATA(lv_host) = CONV zab_cds_ce_bolt_sysinfo-hostname( sy-host ).

    APPEND VALUE #( systemid      = sy-sysid
                    client        = sy-mandt
                    hostname      = lv_host
                    username      = sy-uname
                    customername  = ls_setup-customer_name
                    setupexists   = xsdbool( ls_setup IS NOT INITIAL )
                    isadmin       = zcl_ab_bolt_config=>is_admin( )
                    adminsdefined = xsdbool( ls_setup-admin_users IS NOT INITIAL )
                    githubready   = lv_token
                    repoready     = lv_repo
                    aiready       = lv_ai
                    live          = xsdbool( lv_token = abap_true AND lv_repo = abap_true AND lv_ai = abap_true )
                    repourl       = COND #( WHEN ls_setup-gh_repo IS NOT INITIAL
                                            THEN |https://github.com/{ zcl_ab_bolt_github=>parse_repo( ls_setup-gh_repo )-full_name }| )
                    indexbuilt    = xsdbool( lv_index > 0 )
                    appversion    = gc_version ) TO lt_rows.

    " RAP terminates when a query option the request contains is not read by the
    " provider - the UI5 model always sends $skip/$top (and may send $orderby).
    " One row: sorting changes nothing, paging can only skip it.
    io_request->get_sort_elements( ).
    DATA(lo_paging) = io_request->get_paging( ).
    DATA(lv_offset) = lo_paging->get_offset( ).

    IF io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( lt_rows ) ).
    ENDIF.
    IF io_request->is_data_requested( ) = abap_true.
      IF lv_offset > 0.
        CLEAR lt_rows.
      ENDIF.
      io_response->set_data( lt_rows ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
