CREATE OR REPLACE FUNCTION "%{table}_update" ()
  RETURNS TRIGGER
AS $$
DECLARE
  rec "%{table}";
  new_id INT4;
  now timestamp;
  whodunnit int;

BEGIN
  IF OLD.obsoleted_dt <> 'infinity' THEN
     RAISE EXCEPTION 'can not modify old row version';
  END IF;

  -- If obsoleted_dt is being set, assume that the row is being
  -- obsoleted.  We return the OLD row so that other field updates are
  -- ignored.  This is used by DELETE.
  IF NEW.obsoleted_dt <> 'infinity' THEN
     OLD.o_user_id = NEW.o_user_id;
     OLD.obsoleted_dt = NEW.obsoleted_dt;
     return OLD;
  END IF;

  -- copy old version of the row into rec
  SELECT INTO rec * FROM "%{table}" WHERE "id" = NEW.id;

  -- new_id is a new primary key that we'll use for the obsoleted row.
  SELECT nextval('"%{table}_id_seq"') INTO new_id;

  -- not sure if PGSQL will return the same value for now() in the
  -- same transaction.  So, use the same variable to be sure.
  now = 'now()';

  rec.id = new_id;
  rec.group_id = NEW.id;
  rec.o_user_id = NEW.user_id;

  -- FIXME: The following IF/ELSE handles cases where created_dt is
  -- sent in on update. This is only useful for debugging.  Consider
  -- removing the surronding IF (and ELSE part) for production
  -- version.
  IF NEW.created_dt = OLD.created_dt THEN
    -- Set the modified row's created_dt.  The obsoleted_dt field was
    -- already infinity, so we don't need to set it.
    NEW.created_dt = now;
    rec.obsoleted_dt = now;
  ELSE
    IF NEW.created_dt <= OLD.created_dt THEN
      RAISE EXCEPTION 'new created_dt must be greater than old';
    END IF;

    rec.obsoleted_dt = NEW.created_dt;
  END IF;

  -- insert rec, note that the insert trigger will get called.  The
  -- obsoleted_dt is set so INSERT should not do anything with this row.
  INSERT INTO "%{table}" VALUES (rec.*);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS %{table}_update ON %{table};
CREATE TRIGGER "%{table}_update" BEFORE UPDATE ON "%{table}" FOR EACH ROW
EXECUTE PROCEDURE "%{table}_update"();
