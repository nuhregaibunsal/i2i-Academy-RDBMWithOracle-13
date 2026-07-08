CREATE OR REPLACE PACKAGE book_operations AS

  c_err_empty_input CONSTANT PLS_INTEGER := -20001;
  c_err_bad_format  CONSTANT PLS_INTEGER := -20002;
  c_err_mismatch    CONSTANT PLS_INTEGER := -20003;
  c_err_unexpected  CONSTANT PLS_INTEGER := -20099;

  FUNCTION fn_to_xml (p_raw IN CLOB) RETURN CLOB;

  FUNCTION fn_to_json (p_raw IN CLOB) RETURN CLOB;

  PROCEDURE prc_import_books (
    p_xml      IN  CLOB,
    p_json     IN  CLOB,
    p_inserted OUT NUMBER,
    p_message  OUT VARCHAR2
  );

  PROCEDURE prc_fetch_books (p_result OUT SYS_REFCURSOR);

END book_operations;

CREATE OR REPLACE PACKAGE BODY book_operations AS

  FUNCTION resolve_publisher (p_name IN publishers.name%TYPE)
    RETURN publishers.id%TYPE IS
    v_id publishers.id%TYPE;
  BEGIN
    SELECT id INTO v_id FROM publishers WHERE name = p_name;
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      INSERT INTO publishers (name) VALUES (p_name) RETURNING id INTO v_id;
      RETURN v_id;
  END resolve_publisher;

  FUNCTION resolve_author (p_name IN authors.name%TYPE)
    RETURN authors.id%TYPE IS
    v_id authors.id%TYPE;
  BEGIN
    SELECT id INTO v_id FROM authors WHERE name = p_name;
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      INSERT INTO authors (name) VALUES (p_name) RETURNING id INTO v_id;
      RETURN v_id;
  END resolve_author;

  FUNCTION fn_to_xml (p_raw IN CLOB) RETURN CLOB IS
    v_xml CLOB;
  BEGIN
    IF p_raw IS NULL OR DBMS_LOB.getlength(p_raw) = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_empty_input, 'Raw payload is empty.');
    END IF;

    SELECT XMLELEMENT("books",
             XMLAGG(
               XMLELEMENT("book",
                 XMLELEMENT("title", title),
                 XMLELEMENT("author", author),
                 XMLELEMENT("publisher", publisher)
               ) ORDER BY rn
             )
           ).getClobVal()
      INTO v_xml
      FROM (
        SELECT rn,
               TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 1)) AS title,
               TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 2)) AS author,
               TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 3)) AS publisher
          FROM (
            SELECT TRIM(REGEXP_SUBSTR(p_raw, '[^~]+', 1, LEVEL)) AS rec,
                   LEVEL AS rn
              FROM dual
           CONNECT BY REGEXP_SUBSTR(p_raw, '[^~]+', 1, LEVEL) IS NOT NULL
          )
      );

    RETURN v_xml;
  END fn_to_xml;

  FUNCTION fn_to_json (p_raw IN CLOB) RETURN CLOB IS
    v_json CLOB;
  BEGIN
    IF p_raw IS NULL OR DBMS_LOB.getlength(p_raw) = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_empty_input, 'Raw payload is empty.');
    END IF;

    SELECT JSON_ARRAYAGG(
             JSON_OBJECT(
               'title'     VALUE title,
               'author'    VALUE author,
               'publisher' VALUE publisher
             ) ORDER BY rn RETURNING CLOB
           )
      INTO v_json
      FROM (
        SELECT rn,
               TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 1)) AS title,
               TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 2)) AS author,
               TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 3)) AS publisher
          FROM (
            SELECT TRIM(REGEXP_SUBSTR(p_raw, '[^~]+', 1, LEVEL)) AS rec,
                   LEVEL AS rn
              FROM dual
           CONNECT BY REGEXP_SUBSTR(p_raw, '[^~]+', 1, LEVEL) IS NOT NULL
          )
      );

    RETURN v_json;
  END fn_to_json;

  PROCEDURE prc_import_books (
    p_xml      IN  CLOB,
    p_json     IN  CLOB,
    p_inserted OUT NUMBER,
    p_message  OUT VARCHAR2
  ) IS
    v_count        PLS_INTEGER := 0;
    v_xml_cnt      PLS_INTEGER := 0;
    v_json_cnt     PLS_INTEGER := 0;
    v_author_id    authors.id%TYPE;
    v_publisher_id publishers.id%TYPE;
  BEGIN
    p_inserted := 0;

    IF p_xml IS NULL OR p_json IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_empty_input,
        'Both XML and JSON inputs are required.');
    END IF;

    SELECT COUNT(*) INTO v_xml_cnt
      FROM XMLTABLE('/books/book' PASSING XMLTYPE(p_xml)
             COLUMNS title VARCHAR2(300) PATH 'title');

    SELECT COUNT(*) INTO v_json_cnt
      FROM JSON_TABLE(p_json, '$[*]'
             COLUMNS (title VARCHAR2(300) PATH '$.title'));

    IF v_xml_cnt <> v_json_cnt THEN
      RAISE_APPLICATION_ERROR(c_err_mismatch,
        'XML and JSON record counts differ (' || v_xml_cnt ||
        ' vs ' || v_json_cnt || '); batch rejected.');
    END IF;

    FOR rec IN (
      SELECT x.title, x.author, x.publisher
        FROM XMLTABLE('/books/book' PASSING XMLTYPE(p_xml)
               COLUMNS title     VARCHAR2(300) PATH 'title',
                       author    VARCHAR2(200) PATH 'author',
                       publisher VARCHAR2(200) PATH 'publisher') x
    ) LOOP
      IF rec.title IS NULL OR rec.author IS NULL OR rec.publisher IS NULL THEN
        RAISE_APPLICATION_ERROR(c_err_bad_format,
          'Malformed record #' || (v_count + 1) || ': a required field is missing.');
      END IF;

      v_publisher_id := resolve_publisher(rec.publisher);
      v_author_id    := resolve_author(rec.author);

      INSERT INTO books (title, author_id, publisher_id)
      VALUES (rec.title, v_author_id, v_publisher_id);

      v_count := v_count + 1;
    END LOOP;

    COMMIT;

    p_inserted := v_count;
    p_message  := 'Import successful: ' || v_count ||
                  ' book(s) persisted from XML+JSON payloads.';

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE BETWEEN -20999 AND -20000 THEN
        RAISE;
      ELSE
        RAISE_APPLICATION_ERROR(c_err_unexpected,
          'Unexpected import failure: ' || SQLERRM);
      END IF;
  END prc_import_books;

  PROCEDURE prc_fetch_books (p_result OUT SYS_REFCURSOR) IS
    CURSOR c_books IS
      SELECT b.id AS book_id,
             b.title,
             a.name AS author_name,
             p.name AS publisher_name
        FROM books b
        JOIN authors    a ON a.id = b.author_id
        JOIN publishers p ON p.id = b.publisher_id
       ORDER BY b.title;

    v_row  c_books%ROWTYPE;
    v_data book_detail_tab := book_detail_tab();
  BEGIN
    OPEN c_books;
    LOOP
      FETCH c_books INTO v_row;
      EXIT WHEN c_books%NOTFOUND;
      v_data.EXTEND;
      v_data(v_data.LAST) := book_detail_obj(
        v_row.book_id, v_row.title, v_row.author_name, v_row.publisher_name
      );
    END LOOP;
    CLOSE c_books;

    OPEN p_result FOR SELECT * FROM TABLE(v_data);
  END prc_fetch_books;

END book_operations;
