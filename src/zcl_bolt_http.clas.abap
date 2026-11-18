"! <p class="shorttext synchronized">Bolt with Fiori - HTTP call through an SM59 destination</p>
"! One place for every outbound call (GitHub, the other SAP systems, the AI
"! provider). Host, port, TLS, proxy and logon all live in the SM59
"! destination, never in this code - see docs/03_client_connectivity.md.
"! Never opens a logon popup, so it is safe in background jobs.
CLASS zcl_bolt_http DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_header,
        name  TYPE string,
        value TYPE string,
      END OF ty_header,
      ty_t_header TYPE STANDARD TABLE OF ty_header WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_response,
        code   TYPE i,
        reason TYPE string,
        body   TYPE string,
      END OF ty_response.

    "! Sends one request and returns status code + body. Raises only when the
    "! call itself could not be made (destination missing, network, TLS) -
    "! an HTTP error status (4xx/5xx) is returned for the caller to explain.
    CLASS-METHODS call
      IMPORTING iv_destination     TYPE rfcdest
                iv_method          TYPE string
                iv_uri             TYPE string
                iv_body            TYPE string      OPTIONAL
                it_headers         TYPE ty_t_header OPTIONAL
                iv_timeout         TYPE i           DEFAULT 120
      RETURNING VALUE(rs_response) TYPE ty_response
      RAISING   zcx_bolt.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_bolt_http IMPLEMENTATION.

  METHOD call.
    DATA lo_client TYPE REF TO if_http_client.

    IF iv_destination IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt( iv_text = `No SM59 destination is configured for this connection - set it in Configuration.` ).
    ENDIF.

    cl_http_client=>create_by_destination(
      EXPORTING
        destination              = iv_destination
      IMPORTING
        client                   = lo_client
      EXCEPTIONS
        argument_not_found       = 1
        destination_not_found    = 2
        destination_no_authority = 3
        plugin_not_active        = 4
        internal_error           = 5
        OTHERS                   = 6 ).
    IF sy-subrc <> 0.
      DATA(lv_reason) = SWITCH string( sy-subrc
        WHEN 2 THEN `it does not exist in SM59`
        WHEN 3 THEN `you are not authorized to use it`
        WHEN 4 THEN `the HTTP/HTTPS plug-in of the ICM is not active`
        ELSE |error { sy-subrc }| ).
      RAISE EXCEPTION NEW zcx_bolt( iv_text = |SM59 destination { iv_destination } cannot be used: { lv_reason }.| ).
    ENDIF.

    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.
    lo_client->request->set_method( iv_method ).
    cl_http_utility=>set_request_uri( request = lo_client->request
                                      uri     = iv_uri ).
    LOOP AT it_headers INTO DATA(ls_header).
      lo_client->request->set_header_field( name  = ls_header-name
                                            value = ls_header-value ).
    ENDLOOP.
    IF iv_body IS NOT INITIAL.
      lo_client->request->set_cdata( iv_body ).
    ENDIF.

    lo_client->send(
      EXPORTING
        timeout                    = iv_timeout
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        http_invalid_timeout       = 4
        OTHERS                     = 5 ).
    IF sy-subrc = 0.
      lo_client->receive(
        EXCEPTIONS
          http_communication_failure = 1
          http_invalid_state         = 2
          http_processing_failed     = 3
          OTHERS                     = 4 ).
    ENDIF.
    IF sy-subrc <> 0.
      DATA lv_message TYPE string.
      lo_client->get_last_error( IMPORTING message = lv_message ).
      lo_client->close( EXCEPTIONS OTHERS = 1 ).
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = |Call through SM59 destination { iv_destination } failed: { lv_message }. | &&
                  |Check host, port, SSL (STRUST) and proxy settings of the destination.| ).
    ENDIF.

    lo_client->response->get_status( IMPORTING code   = rs_response-code
                                               reason = rs_response-reason ).
    rs_response-body = lo_client->response->get_cdata( ).
    lo_client->close( EXCEPTIONS OTHERS = 1 ).
  ENDMETHOD.

ENDCLASS.
