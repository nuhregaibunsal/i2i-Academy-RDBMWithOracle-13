SET SERVEROUTPUT ON

DECLARE
  v_raw      CLOB;
  v_inserted NUMBER;
  v_message  VARCHAR2(4000);
BEGIN
  v_raw :=
    'Clean Code|9780132350884|2008|Robert|Martin|1965|Prentice Hall|USA'  || '~' ||
    'Refactoring|9780201485677|1999|Martin|Fowler|1963|Addison-Wesley|USA' || '~' ||
    'The Pragmatic Programmer|9780201616224|1999|Andrew|Hunt|1964|Addison-Wesley|USA';

  book_mgmt_pkg.prc_import_books(
    p_raw      => v_raw,
    p_inserted => v_inserted,
    p_message  => v_message
  );

  DBMS_OUTPUT.PUT_LINE(v_message);
END;
/

VAR rc REFCURSOR
EXEC book_mgmt_pkg.prc_fetch_books(:rc);
PRINT rc
