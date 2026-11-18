"! <p class="shorttext synchronized">Bolt with Fiori - exception with a plain-language text</p>
"! Every error the app can hit (GitHub, SM59, source system, AI) is raised as
"! this one class with a complete sentence the user can act on - the text is
"! what the Fiori screen and the status-file log show.
CLASS zcx_bolt DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    DATA gv_text TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        textid   LIKE textid   OPTIONAL
        previous LIKE previous OPTIONAL
        iv_text  TYPE string   OPTIONAL.

    METHODS if_message~get_text REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcx_bolt IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( textid = textid previous = previous ).
    gv_text = iv_text.
  ENDMETHOD.


  METHOD if_message~get_text.
    IF gv_text IS NOT INITIAL.
      result = gv_text.
    ELSE.
      result = super->if_message~get_text( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
