CREATE TABLE server (
    id       VARCHAR (50)  PRIMARY KEY
                           UNIQUE,
    ip       VARCHAR (16),
    cpu      VARCHAR (50),
    os       VARCHAR (50),
    mem      INTEGER,
    user     VARCHAR (50),
    online   BOOLEAN,
    owner    VARCHAR (50),
    position VARCHAR (50),
    purpose  VARCHAR (100),
    product  VARCHAR (50) 
);
