CREATE FUNCTION rm_modify() 
RETURNS trigger AS $$
DECLARE
BEGIN
IF OLD.label IS NULL THEN
    IF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=0,FW2=0
       WHERE fid=NEW.fid;
    ELSIF NEW.label=1 THEN
       UPDATE rm 
       SET label=NEW.label,FW1=1
       WHERE fid=NEW.fid;
    END IF;           
ELSIF OLD.label=1 THEN
    IF NEW.label=0 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=0
       WHERE fid=OLD.fid;
    ELSIF NEW.label=2 THEN
       UPDATE rm 
       SET label=NEW.label,FW2=1
       WHERE fid=OLD.fid;
    END IF;
END IF;  
RETURN NULL;
END;
$$ LANGUAGE plpgsql;