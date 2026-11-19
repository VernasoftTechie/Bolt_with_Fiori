"! <p class="shorttext synchronized">Bolt - outbound HTTPS call (GitHub, AI provider)</p>
"! One place for every outbound call. Two ways to reach the endpoint, both set
"! on the Setup page:
"!   - URL (default): CL_HTTP_CLIENT=>CREATE_BY_URL with the SSL client
"!     identity of the setup (ANONYM by default). The root certificate of the
"!     endpoint must be in that PSE (STRUST); a proxy, if the system needs one,
"!     comes from the system-wide HTTP client proxy settings (SICF).
"!   - SM59 destination (optional): when filled it wins - host, TLS and proxy
"!     then come from the destination.
"! Never opens a logon popup, so it is safe in background jobs.
CLASS zcl_ab_bolt_http DEFINITION
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
      BEGIN OF ty_endpoint,
        base_url    TYPE string,
        destination TYPE rfcdest,
        ssl_id      TYPE ssfapplssl,
      END OF ty_endpoint.

    TYPES:
      BEGIN OF ty_response,
        code    TYPE i,
        reason  TYPE string,
        body    TYPE string,
        headers TYPE tihttpnvp,
      END OF ty_response.

    "! Sends one request. iv_path is appended to the base URL (or, with a
    "! destination, to the destination's path prefix). Raises only when the
    "! call itself could not be made (address, network, TLS); an HTTP error
    "! status (4xx/5xx) is returned for the caller to explain.
    CLASS-METHODS call
      IMPORTING is_endpoint        TYPE ty_endpoint
                iv_method          TYPE string
                iv_path            TYPE string
                iv_body            TYPE string      OPTIONAL
                it_headers         TYPE ty_t_header OPTIONAL
                iv_timeout         TYPE i           DEFAULT 120
      RETURNING VALUE(rs_response) TYPE ty_response
      RAISING   zcx_ab_bolt.

    "! Value of one response header (case-insensitive), blank when absent.
    CLASS-METHODS header_value
      IMPORTING is_response     TYPE ty_response
                iv_name         TYPE string
      RETURNING VALUE(rv_value) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS where
      IMPORTING is_endpoint    TYPE ty_endpoint
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.



CLASS zcl_ab_bolt_http IMPLEMENTATION.

  METHOD where.
    rv_text = COND #( WHEN is_endpoint-destination IS NOT INITIAL
                      THEN |SM59 destination { is_endpoint-destination }|
                      ELSE condense( is_endpoint-base_url ) ).
  ENDMETHOD.


  METHOD call.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_subrc  TYPE sysubrc.

    IF is_endpoint-destination IS NOT INITIAL.
      cl_http_client=>create_by_destination(
        EXPORTING
          destination              = is_endpoint-destination
        IMPORTING
          client                   = lo_client
        EXCEPTIONS
          argument_not_found       = 1
          destination_not_found    = 2
          destination_no_authority = 3
          plugin_not_active        = 4
          internal_error           = 5
          OTHERS                   = 6 ).
      lv_subrc = sy-subrc.
      IF lv_subrc = 0.
        cl_http_utility=>set_request_uri( request = lo_client->request
                                          uri     = iv_path ).
      ENDIF.
    ELSE.
      DATA(lv_base) = condense( is_endpoint-base_url ).
      IF lv_base IS INITIAL.
        RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = `No address is configured for this connection - set it on the Setup page.` ).
      ENDIF.
      WHILE strlen( lv_base ) > 1 AND substring( val = lv_base off = strlen( lv_base ) - 1 len = 1 ) = `/`.
        lv_base = substring( val = lv_base len = strlen( lv_base ) - 1 ).
      ENDWHILE.
      cl_http_client=>create_by_url(
        EXPORTING
          url                = |{ lv_base }{ iv_path }|
          ssl_id             = COND #( WHEN is_endpoint-ssl_id IS NOT INITIAL THEN is_endpoint-ssl_id ELSE 'ANONYM' )
        IMPORTING
          client             = lo_client
        EXCEPTIONS
          argument_not_found = 1
          plugin_not_active  = 4
          internal_error     = 5
          OTHERS             = 6 ).
      lv_subrc = sy-subrc.
    ENDIF.
    IF lv_subrc <> 0.
      DATA(lv_reason) = SWITCH string( lv_subrc
        WHEN 1 THEN `the address is not valid`
        WHEN 2 THEN `the destination does not exist in SM59`
        WHEN 3 THEN `you are not authorized to use the destination`
        WHEN 4 THEN `the HTTP/HTTPS plug-in of the ICM is not active (SMICM)`
        ELSE |error { lv_subrc }| ).
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |{ where( is_endpoint ) } cannot be used: { lv_reason }.| ).
    ENDIF.

    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.
    lo_client->request->set_method( iv_method ).
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
      " SAP's SSL texts continue with internal trace parts after '#' - keep the reason only,
      " so the reason and the fix fit into one message on the screen.
      SPLIT lv_message AT '#' INTO lv_message DATA(lv_trace) ##NEEDED.
      DATA(lv_pse) = COND string( WHEN is_endpoint-ssl_id IS INITIAL THEN `ANONYM` ELSE CONV string( is_endpoint-ssl_id ) ).
      RAISE EXCEPTION NEW zcx_ab_bolt(
        iv_text = COND #( WHEN lv_message CS `SSL` OR lv_message CS `CERT`
                          THEN |{ condense( lv_message ) }. Import the server's root + intermediate certificate in STRUST, PSE SSL client { lv_pse }, then restart the ICM.|
                          ELSE |Call to { where( is_endpoint ) } failed: { condense( lv_message ) }. Check the network/proxy (SICF > Client > Proxy Settings).| ) ).
    ENDIF.

    lo_client->response->get_status( IMPORTING code   = rs_response-code
                                               reason = rs_response-reason ).
    rs_response-body = lo_client->response->get_cdata( ).
    lo_client->response->get_header_fields( CHANGING fields = rs_response-headers ).
    lo_client->close( EXCEPTIONS OTHERS = 1 ).
  ENDMETHOD.


  METHOD header_value.
    DATA(lv_name) = to_lower( iv_name ).
    LOOP AT is_response-headers INTO DATA(ls_field).
      IF to_lower( ls_field-name ) = lv_name.
        rv_value = ls_field-value.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
