"! <p class="shorttext synchronized">Bolt with Fiori - source API: legacy files of one Smart Form</p>
"! Serves ZCE_BOLT_SRC_FILE for the Bolt app on another system: runs the
"! legacy grab + XML export for the form in filter FORM_NAME on THIS system and
"! returns the files. FORM_NAME '*GLOBAL*' returns the SmartStyle and logo
"! inventories. Optional filters PREFIXES eq 'Z,Y' and COUNT_VOLUME eq 'X'.
"! Without a FORM_NAME filter nothing is returned (the grab is per form).
CLASS zcl_bolt_q_src_file DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_t_row TYPE STANDARD TABLE OF zce_bolt_src_file WITH EMPTY KEY.
ENDCLASS.



CLASS zcl_bolt_q_src_file IMPLEMENTATION.

  METHOD if_rap_query_provider~select.
    DATA lt_rows     TYPE ty_t_row.
    DATA lv_form     TYPE string.
    DATA lv_prefixes TYPE string VALUE `Z,Y`.
    DATA lv_volume   TYPE abap_bool VALUE abap_true.

    TRY.
        DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).
        LOOP AT lt_ranges INTO DATA(ls_range) WHERE range IS NOT INITIAL.
          DATA(lv_low) = condense( CONV string( ls_range-range[ 1 ]-low ) ).
          CASE ls_range-name.
            WHEN `FORM_NAME`.
              lv_form = to_upper( lv_low ).
            WHEN `PREFIXES`.
              lv_prefixes = lv_low.
            WHEN `COUNT_VOLUME`.
              lv_volume = xsdbool( lv_low = `X` ).
          ENDCASE.
        ENDLOOP.
      CATCH cx_rap_query_filter_no_range.
        CLEAR lv_form.
    ENDTRY.

    IF lv_form IS NOT INITIAL.
      DATA(ls_extract) = zcl_bolt_source=>get_files_local( iv_form_name    = lv_form
                                                           iv_prefixes     = lv_prefixes
                                                           iv_count_volume = lv_volume ).
      DATA(lv_message) = concat_lines_of( table = ls_extract-warnings sep = cl_abap_char_utilities=>newline ).
      LOOP AT ls_extract-files INTO DATA(ls_file).
        APPEND VALUE #( form_name    = lv_form
                        file_name    = ls_file-name
                        kind         = ls_file-kind
                        size_bytes   = strlen( ls_file-content )
                        content      = ls_file-content
                        prefixes     = lv_prefixes
                        count_volume = lv_volume
                        message      = lv_message ) TO lt_rows.
      ENDLOOP.
      IF lt_rows IS INITIAL AND lv_message IS NOT INITIAL.
        " Nothing extracted - still tell the caller why (one placeholder row).
        APPEND VALUE #( form_name = lv_form file_name = `*NONE*` kind = `NONE`
                        prefixes  = lv_prefixes count_volume = lv_volume message = lv_message ) TO lt_rows.
      ENDIF.
    ENDIF.

    IF io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( lt_rows ) ).
    ENDIF.
    IF io_request->is_data_requested( ) = abap_true.
      io_response->set_data( lt_rows ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
