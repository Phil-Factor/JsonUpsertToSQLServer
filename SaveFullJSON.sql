DECLARE @CJSON nvarchar(max)
SELECT @Cjson = BulkColumn
 FROM OPENROWSET (BULK 'D:\raw data\customersUTF16.json', SINGLE_BLOB) as j
--text encoding must be littlendian UTF16
/*
We start by creating a table at the document level, with the main arrays within each document 
represented by columns. This means that this initial slicing of the JSON collection needs
be done only once. In our case, there are
  the details of the Name,
  Addresses, 
  Credit Cards, 
  Email Addresses, 
  Notes, 
  Phone numbers
In some cases, there are sub-arrays. The phone numbers, for example, have an array of dates.
We fill this table via a call to openJSON.
By doing this, we have the main details of each customer available to us when slicing up
embedded arrays

The batch is designed so it can be rerun, and should be idempotent. 
*/

IF Object_Id('dbo.JSONDocuments','U') IS NOT NULL DROP TABLE dbo.JSONDocuments
CREATE TABLE dbo.JSONDocuments
  (
  Document_id INT NOT NULL,
      [Full_Name] NVARCHAR(30) NOT NULL,
 	  Name NVARCHAR(MAX) NOT NULL,--holds a JSON object
	  Addresses NVARCHAR(MAX) NULL,--holds an array of JSON objects
	  Cards NVARCHAR(MAX) NULL,--holds an array of JSON objects
	  EmailAddresses NVARCHAR(MAX) NULL,--holds an array of JSON objects
	  Notes NVARCHAR(MAX) NULL,--holds an array of JSON objects
	  Phones NVARCHAR(MAX) NULL,--holds an array of JSON objects
	  CONSTRAINT JSONDocumentsPk PRIMARY KEY (Document_id)
  ) ON [PRIMARY];

/* Now we fill this table with a row for each document, each representing the entire date for a
customer. Each item of root data, such as the id and the customer's full name, is held  
as a column. All other columns hold JSON.*/
INSERT INTO dbo.JSONDocuments ( Document_id,Full_name,[Name],Addresses, Cards, EmailAddresses, Notes, Phones)
 SELECT [key] AS Document_id,Full_name,[Name],Addresses, Cards, EmailAddresses, Notes, Phones 
  FROM OpenJson(@CJSON) AS EachDocument
      CROSS APPLY OpenJson(EachDocument.Value) 
	  WITH (
	      [Full_Name] NVARCHAR(30) N'$."Full Name"', 
		  Name NVARCHAR(MAX) N'$.Name' AS JSON,
		  Addresses NVARCHAR(MAX) N'$.Addresses' AS JSON,
		  Cards NVARCHAR(MAX) N'$.Cards' AS JSON,
		  EmailAddresses NVARCHAR(MAX) N'$.EmailAddresses' AS JSON,
		  Notes NVARCHAR(MAX) N'$.Notes' AS JSON,
		  Phones NVARCHAR(MAX) N'$.Phones' AS JSON)

/*first we need to create an entry in the person table if it doesn't already
exist as that has the person_id.
*/
SET IDENTITY_INSERT [Customer].[Person] On
MERGE [Customer].[Person] AS target
USING
  (--get the required data for the person table and merge it with what is there
  SELECT JSONDocuments.Document_id, Title, FirstName, 
       MiddleName, LastName, Suffix
    FROM dbo.JSONDocuments
      CROSS APPLY
    OpenJson(JSONDocuments.Name)
    WITH
      (
      Title NVARCHAR(8) N'$.Title', FirstName VARCHAR(40) N'$."First Name"',
      MiddleName VARCHAR(40) N'$."Middle Name"',
      LastName VARCHAR(40) N'$."Last Name"', Suffix VARCHAR(10) N'$.Suffix'
      )
  ) AS source (person_id, Title, FirstName, MiddleName, LastName, Suffix)
ON target.person_id = source.person_id 
WHEN NOT MATCHED THEN 
  INSERT (person_id, Title, FirstName, MiddleName, LastName, Suffix)
    VALUES
      (source.person_id, source.Title, source.FirstName, 
	  source.MiddleName, source.LastName, source.Suffix);
SET IDENTITY_INSERT [Customer].[Person] Off

/* Now we do the notes. This has the complication because there is a many to many
relationship with the notes and the people, because the same standard notes can be 
associated with many customers such an overdue invoice payment etc. */
DECLARE @Note TABLE (document_id INT NOT NULL, Text NVARCHAR(MAX) NOT NULL, Date DATETIME)
INSERT INTO @Note (document_id, Text, Date)
  SELECT JSONDocuments.Document_id, Text, Date
    FROM dbo.JSONDocuments
      CROSS APPLY OpenJson(JSONDocuments.Notes) AS TheNotes
      CROSS APPLY
    OpenJson(TheNotes.Value)
    WITH (Text NVARCHAR(MAX) N'$.Text', Date DATETIME N'$.Date')
	WHERE Text IS NOT null
--if the notes are new then insert them
INSERT INTO Customer.Note (Note)
  SELECT DISTINCT newnotes.Text
    FROM @Note AS newnotes
      LEFT OUTER JOIN Customer.Note
        ON note.notestart = Left(newnotes.Text,850)--just compare the first 850 chars
    WHERE note.note IS NULL 
/* now fill in the many-to-many table relating notes to people, making sure that you
--do not duplicate anything*/
INSERT INTO Customer.NotePerson (Person_id, Note_id)
  SELECT newnotes.document_id, note.note_id
    FROM @Note AS newnotes
      INNER JOIN Customer.Note
        ON note.note = newnotes.Text
	  LEFT OUTER JOIN Customer.NotePerson
	    ON NotePerson.Person_id=newnotes.document_id
		AND NotePerson.note_id=note.note_id
		WHERE NotePerson.note_id IS null

/* addresses are complicated because they involve three tables. There is the
address, which is the physical place, the abode, which records when and why the 
person was associated with the place, and a third table which constrains
the type of abode.

We create a table variable to support the various queries without any extra
shredding */
DECLARE @addresses TABLE
  (
  person_id INT NOT null,
  Type NVARCHAR(40) NOT null,
  Full_Address NVARCHAR(200)NOT null,
  County NVARCHAR(30) NOT null,
  Start_Date DATETIME NOT null,
  End_Date DATETIME null
  );
--stock the table variable with the adderess information
INSERT INTO @Addresses(person_id, Type,Full_Address, County, [Start_Date], End_Date)
SELECT Document_id, Address.Type,Address.Full_Address, Address.County, 
         WhenLivedIn.[Start_date],WhenLivedIn.End_date
    FROM dbo.JSONDocuments
      CROSS APPLY
    OpenJson(JSONDocuments.Addresses) AllAddresses
	  CROSS APPLY 
	   OpenJson(AllAddresses.value)
    WITH
      (
      Type NVARCHAR(8) N'$.type', Full_Address NVARCHAR(200) N'$."Full Address"',
      County VARCHAR(40) N'$.County',Dates NVARCHAR(MAX) AS json
      ) Address
    CROSS APPLY
	OpenJson(Address.Dates) WITH
      (
      Start_date datetime N'$."Moved In"',End_date datetime N'$."Moved Out"'
      )WhenLivedIn

--first make sure that the types of address exists and add if necessary
INSERT INTO Customer.Addresstype (TypeOfAddress)
  SELECT DISTINCT NewAddresses.Type
    FROM @addresses AS NewAddresses
      LEFT OUTER JOIN Customer.Addresstype
        ON NewAddresses.Type = Addresstype.TypeOfAddress
    WHERE Addresstype.TypeOfAddress IS NULL;

--Fill the Address table with addresses ensuring uniqueness 
INSERT INTO Customer.Address (Full_Address, County)
SELECT DISTINCT NewAddresses.Full_Address, NewAddresses.County
  FROM @addresses AS NewAddresses
    LEFT OUTER JOIN Customer.Address AS currentAddresses
      ON NewAddresses.Full_Address = currentAddresses.Full_Address
  WHERE currentAddresses.Full_Address IS NULL;

--and now the many-to-many Abode table
INSERT INTO Customer.Abode (Person_id, Address_ID, TypeOfAddress, Start_date,
End_date)
  SELECT newAddresses.person_id, address.Address_ID, newAddresses.Type,
    newAddresses.Start_Date, newAddresses.End_Date
    FROM @addresses AS newAddresses
      INNER JOIN customer.address
        ON newAddresses.Full_Address = address.Full_Address
      LEFT OUTER JOIN Customer.Abode
        ON Abode.person_id = newAddresses.person_id
       AND Abode.Address_ID = address.Address_ID
    WHERE Abode.person_id IS NULL;
/*
credit cards are much easier since they are a simple sub-array.
*/
INSERT INTO customer.CreditCard (Person_id, CardNumber, ValidFrom, ValidTo, CVC)
  SELECT JSONDocuments.Document_id AS Person_id, new.CardNumber, new.ValidFrom,
    new.ValidTo, new.CVC
    FROM dbo.JSONDocuments
      CROSS APPLY OpenJson(JSONDocuments.Cards) AS TheCards
      CROSS APPLY
    OpenJson(TheCards.Value)
    WITH
      (
      CardNumber VARCHAR(20), ValidFrom DATE N'$.ValidFrom',
      ValidTo DATE N'$.ValidTo', CVC CHAR(3)
      ) AS new
      LEFT OUTER JOIN customer.CreditCard
        ON JSONDocuments.Document_id = CreditCard.Person_id
       AND new.CardNumber = CreditCard.CardNumber
    WHERE CreditCard.CardNumber IS NULL;

--Email Addresses are also simple 
INSERT INTO Customer.EmailAddress (Person_id, EmailAddress, StartDate, EndDate)
  SELECT JSONDocuments.Document_id AS Person_id, new.EmailAddress,
    new.StartDate, new.EndDate
    FROM dbo.JSONDocuments
      CROSS APPLY OpenJson(JSONDocuments.EmailAddresses) AS TheEmailAddresses
      CROSS APPLY
    OpenJson(TheEmailAddresses.Value)
    WITH
      (
      EmailAddress NVARCHAR(40) N'$.EmailAddress',
      StartDate DATE N'$.StartDate', EndDate DATE N'$.EndDate'
      ) AS new
      LEFT OUTER JOIN Customer.EmailAddress AS email
        ON JSONDocuments.Document_id = email.Person_id
       AND new.EmailAddress = email.EmailAddress
    WHERE email.EmailAddress IS NULL;

/*now we add these customers phones. The various dates for the start and end
of the use of the phone number are held in a subarray within the individual
card objects*/
DECLARE @phones TABLE
  (
  Person_id INT,
  TypeOfPhone NVARCHAR(40),
  DiallingNumber VARCHAR(20),
  Start_Date DATE,
  End_Date DATE
  );
INSERT INTO @phones (Person_id, TypeOfPhone, DiallingNumber, Start_Date,
End_Date)
  SELECT JSONDocuments.Document_id, EachPhone.TypeOfPhone,
    EachPhone.DiallingNumber, [From], [To]
    FROM dbo.JSONDocuments
      CROSS APPLY OpenJson(JSONDocuments.Phones) AS ThePhones
      CROSS APPLY
    OpenJson(ThePhones.Value)
    WITH
      (
      TypeOfPhone NVARCHAR(40), DiallingNumber VARCHAR(20), Dates NVARCHAR(MAX) AS JSON
      ) AS EachPhone
      CROSS APPLY
    OpenJson(EachPhone.Dates)
    WITH ([From] DATE, [To] DATE);

--insert any new phone types
INSERT INTO Customer.PhoneType (TypeOfPhone)
  SELECT DISTINCT new.TypeOfPhone
    FROM @phones AS new
      LEFT OUTER JOIN Customer.PhoneType
        ON PhoneType.TypeOfPhone = new.TypeOfPhone
    WHERE PhoneType.TypeOfPhone IS NULL AND new.TypeOfPhone IS NOT null;

--insert all new phones 
INSERT INTO Customer.Phone (Person_id, TypeOfPhone, DiallingNumber, Start_date,
End_date)
  SELECT new.Person_id, new.TypeOfPhone, new.DiallingNumber, new.Start_Date,
    new.End_Date
    FROM @phones AS new
      LEFT OUTER JOIN Customer.Phone
        ON Phone.DiallingNumber = new.DiallingNumber
       AND Phone.Person_id = new.Person_id
    WHERE Phone.Person_id IS NULL AND new.TypeOfPhone IS NOT null;	 

