CREATE OR REPLACE TRIGGER trg_books_audit
AFTER INSERT ON books
FOR EACH ROW
BEGIN
  INSERT INTO audit_logs (table_name, action, record_id, changed_by, changed_at)
  VALUES ('BOOKS', 'INSERT', :NEW.id, USER, SYSTIMESTAMP);
END;
