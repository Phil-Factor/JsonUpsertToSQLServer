/*
USE master;
GO

IF NOT EXISTS
  (
  SELECT databases.name FROM sys.databases WHERE databases.name LIKE 'customersAnother'
  )
  CREATE DATABASE CustomersAnother;
GO

USE CustomersAnother;
GO
*/
--only create the Customer schema if it does not exist
IF EXISTS (SELECT * FROM sys.schemas WHERE schemas.name LIKE 'Customer') SET NOEXEC ON;
GO
CREATE SCHEMA Customer;
GO

--
SET NOEXEC OFF;

--delete the table with all the foreign key references in it
IF EXISTS
  (
  SELECT *
    FROM sys.objects
    WHERE objects.object_id LIKE Object_Id('Customer.EmailAddress')
  )
  DROP TABLE Customer.EmailAddress;
GO
IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.Abode')
  )
  DROP TABLE Customer.Abode;

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.NotePerson')
  )
  DROP TABLE Customer.NotePerson;
GO

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.Phone')
  )
  DROP TABLE Customer.Phone;
GO

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.CreditCard')
  )
  DROP TABLE Customer.CreditCard;
GO

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.Person')
  )
  DROP TABLE Customer.Person;
GO



CREATE TABLE Customer.Person
  (
  person_ID INT NOT NULL IDENTITY CONSTRAINT PK_PersonID PRIMARY KEY,
  Title NVARCHAR(8) NULL,
  FirstName NVARCHAR(40) NOT NULL,
  MiddleName NVARCHAR(40) NULL,
  LastName NVARCHAR(40) NOT NULL,
  Suffix NVARCHAR(10) NULL,
  fullName AS
    (Coalesce(Title + ' ', '') + FirstName + Coalesce(' ' + MiddleName, '')
     + ' ' + LastName + Coalesce(' ' + Suffix, '')
    ),
  ModifiedDate DATETIME NOT NULL CONSTRAINT DF_ModifiedDate DEFAULT GetDate()
  );

CREATE NONCLUSTERED INDEX SearchByPersonLastname
ON Customer.Person (LastName ASC, FirstName ASC)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF,
     DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON,
     ALLOW_PAGE_LOCKS = ON
     );
GO

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.Address')
  )
  DROP TABLE Customer.Address;
GO

CREATE TABLE Customer.Address
  (
  Address_ID INT IDENTITY PRIMARY KEY,
  AddressLine1 NVARCHAR(60) NULL,
  AddressLine2 NVARCHAR(60) NULL,
  City NVARCHAR(30)  NULL,
  County NVARCHAR(30)  NULL,
  PostCode NVARCHAR(15)  NULL,
  Full_Address NVARCHAR(200) NULL,
  ModifiedDate DATETIME NOT NULL DEFAULT GetDate(),
  CONSTRAINT Address_Not_Complete 
   CHECK ( Coalesce( AddressLine1, AddressLine2, City, PostCode, Full_address) IS NOT NULL) 
  );
GO

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.AddressType')
  )
  DROP TABLE Customer.AddressType;
GO

CREATE TABLE Customer.AddressType
  (
  TypeOfAddress NVARCHAR(40) PRIMARY KEY,
  ModifiedDate DATETIME NOT NULL DEFAULT GetDate()
  );
GO

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.Abode')
  )
  DROP TABLE Customer.Abode;
GO

CREATE TABLE Customer.Abode
  (
  Abode_ID INT IDENTITY PRIMARY KEY,
  Person_id INT FOREIGN KEY REFERENCES Customer.Person,
  Address_id INT FOREIGN KEY REFERENCES Customer.Address,
  TypeOfAddress NVARCHAR(40) FOREIGN KEY REFERENCES Customer.AddressType,
  Start_date DATETIME,
  End_date DATETIME,
  ModifiedDate DATETIME NOT NULL DEFAULT GetDate()
  );

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.PhoneType')
  )
  DROP TABLE Customer.PhoneType;
GO

CREATE TABLE Customer.PhoneType
  (
  TypeOfPhone NVARCHAR(40) PRIMARY KEY,
  ModifiedDate DATETIME NOT NULL DEFAULT GetDate()
  );

CREATE TABLE Customer.Phone
  (
  Phone_ID INT IDENTITY PRIMARY KEY,
  Person_id INT FOREIGN KEY REFERENCES Customer.Person,
  TypeOfPhone NVARCHAR(40) FOREIGN KEY REFERENCES Customer.PhoneType,
  DiallingNumber VARCHAR(20),
  Start_date DATETIME,
  End_date DATETIME,
  ModifiedDate DATETIME NOT NULL DEFAULT GetDate()
  );

IF EXISTS
  (
  SELECT * FROM sys.objects WHERE objects.object_id LIKE Object_Id('Customer.Note')
  )
  DROP TABLE Customer.Note;
GO

CREATE TABLE Customer.Note
  (
  Note_id INT IDENTITY PRIMARY KEY,
  Note NVARCHAR(4000),
  NoteStart AS Left(note,850) UNIQUE,
  InsertionDate DATETIME NOT NULL DEFAULT GetDate(),
  ModifiedDate DATETIME NOT NULL DEFAULT GetDate()
  );

CREATE TABLE Customer.NotePerson
  (
  NoteCustomer_id INT IDENTITY PRIMARY KEY,
  Person_id INT FOREIGN KEY REFERENCES Customer.Person,
  Note_id INT FOREIGN KEY REFERENCES Customer.Note,
  InsertionDate DATETIME NOT NULL DEFAULT GetDate(),
  ModifiedDate DATETIME NOT NULL DEFAULT GetDate(),
  CONSTRAINT DuplicateUK UNIQUE (Person_id, Note_id, InsertionDate)
  );

CREATE TABLE Customer.CreditCard
  (
  CreditCardID INT IDENTITY NOT NULL PRIMARY KEY,
  Person_id INT FOREIGN KEY REFERENCES Customer.Person,
  CardNumber VARCHAR(20) NOT NULL,
  ValidFrom DATE NOT NULL,
  ValidTo DATE NOT NULL,
  CVC CHAR(3) NOT NULL,
  ModifiedDate DATETIME NOT NULL DEFAULT(GetDate()),
  CONSTRAINT DuplicateCreditCardUK UNIQUE (Person_id, Cardnumber)
  );

CREATE TABLE Customer.EmailAddress
  (
  EmailID INT IDENTITY(1, 1) NOT NULL,
  Person_id INT NULL,
  EmailAddress NVARCHAR(40) NOT NULL,
  StartDate DATE NOT NULL,
  EndDate DATE NULL,
  ModifiedDate DATETIME NOT NULL
  ) ON [PRIMARY];
GO

ALTER TABLE Customer.EmailAddress ADD DEFAULT (GetDate()) FOR ModifiedDate;
GO

ALTER TABLE Customer.EmailAddress WITH CHECK
ADD FOREIGN KEY (Person_id) REFERENCES Customer.Person (person_ID);
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the surrogate key for the email address', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'EmailAddress', @level2type = N'COLUMN',
  @level2name = N'EmailID';
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the person associated with the email address',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'EmailAddress', @level2type = N'COLUMN',
  @level2name = N'Person_id';
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the email address', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'EmailAddress', @level2type = N'COLUMN',
  @level2name = N'EmailAddress';
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the time when we created the record', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'EmailAddress', @level2type = N'COLUMN',
  @level2name = N'StartDate';
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the email stopped being valid', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'EmailAddress', @level2type = N'COLUMN',
  @level2name = N'EndDate';
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the email record was last modified', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'EmailAddress', @level2type = N'COLUMN',
  @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the surrogate key for an abode', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Abode',
  @level2type = N'COLUMN', @level2name = N'Abode_ID';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the person associated with the address', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Abode',
  @level2type = N'COLUMN', @level2name = N'Person_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the address concerned', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Abode',
  @level2type = N'COLUMN', @level2name = N'Address_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the type of address', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Abode',
  @level2type = N'COLUMN', @level2name = N'TypeOfAddress';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the person started being associated with the address',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Abode', @level2type = N'COLUMN', @level2name = N'Start_date';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the address stopped being associated with the customer',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Abode', @level2type = N'COLUMN', @level2name = N'End_date';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when this record was last modified', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Abode',
  @level2type = N'COLUMN', @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Primary key for Address records.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Address',
  @level2type = N'COLUMN', @level2name = N'Address_ID';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'First street address line.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Address',
  @level2type = N'COLUMN', @level2name = N'AddressLine1';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Second street address line.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Address',
  @level2type = N'COLUMN', @level2name = N'AddressLine2';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Name of the city.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Address',
  @level2type = N'COLUMN', @level2name = N'City';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the county associated with the address', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Address',
  @level2type = N'COLUMN', @level2name = N'County';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Postal code for the street address.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Address',
  @level2type = N'COLUMN', @level2name = N'PostCode';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Date and time the record was last updated.',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Address', @level2type = N'COLUMN',
  @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Street address information for CustomersCopy, employees, and vendors.',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Address';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'a string describing a type of address', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'AddressType', @level2type = N'COLUMN',
  @level2name = N'TypeOfAddress';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'When the type of address was first defined',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'AddressType', @level2type = N'COLUMN',
  @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the surrogate key for the credit card', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'CreditCard', @level2type = N'COLUMN',
  @level2name = N'CreditCardID';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the person owning the credit card', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'CreditCard', @level2type = N'COLUMN',
  @level2name = N'Person_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the credit card number', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'CreditCard', @level2type = N'COLUMN',
  @level2name = N'CardNumber';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the date from when the card is valid', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'CreditCard', @level2type = N'COLUMN',
  @level2name = N'ValidFrom';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the date to which the card remains valid',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'CreditCard', @level2type = N'COLUMN',
  @level2name = N'ValidTo';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the number on the back of the card', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'CreditCard', @level2type = N'COLUMN', @level2name = N'CVC';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when this record was last modified', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'CreditCard', @level2type = N'COLUMN',
  @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the surrogate key for the note', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Note',
  @level2type = N'COLUMN', @level2name = N'Note_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'record of a communication from the person',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Note', @level2type = N'COLUMN', @level2name = N'Note';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the note was recorded in the database',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Note', @level2type = N'COLUMN',
  @level2name = N'InsertionDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the note was last modified', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Note',
  @level2type = N'COLUMN', @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the surrogate key for the association between customer and note',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'NotePerson', @level2type = N'COLUMN',
  @level2name = N'NoteCustomer_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the person who is associated with the note',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'NotePerson', @level2type = N'COLUMN',
  @level2name = N'Person_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the note that is associated with the customer',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'NotePerson', @level2type = N'COLUMN',
  @level2name = N'Note_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the association between customer and note was inserted',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'NotePerson', @level2type = N'COLUMN',
  @level2name = N'InsertionDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the association between customer and note note was last modified',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'NotePerson', @level2type = N'COLUMN',
  @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Primary key for Person records.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Person',
  @level2type = N'COLUMN', @level2name = N'person_ID';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'A courtesy title. For example, Mr. or Ms.',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Person', @level2type = N'COLUMN', @level2name = N'Title';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'First name of the person.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Person',
  @level2type = N'COLUMN', @level2name = N'FirstName';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Middle name or middle initial of the person.',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Person', @level2type = N'COLUMN', @level2name = N'MiddleName';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Last name of the person.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Person',
  @level2type = N'COLUMN', @level2name = N'LastName';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Surname suffix. For example, Sr. or Jr.', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Person',
  @level2type = N'COLUMN', @level2name = N'Suffix';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'Date and time the record was last updated.',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Person', @level2type = N'COLUMN',
  @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'People involved with the Widget Manufacturing Co.',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Person';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'surrogate key for the record of the phone association',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Phone', @level2type = N'COLUMN', @level2name = N'Phone_ID';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the person associated with the phone', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Phone',
  @level2type = N'COLUMN', @level2name = N'Person_id';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the type of phone, defined in a separate table',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Phone', @level2type = N'COLUMN', @level2name = N'TypeOfPhone';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'the actual number to dial', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Phone',
  @level2type = N'COLUMN', @level2name = N'DiallingNumber';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the customer started being associated with the phone',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Phone', @level2type = N'COLUMN', @level2name = N'Start_date';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'When the phone number stopped being associated with the person',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'Phone', @level2type = N'COLUMN', @level2name = N'End_date';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the phone record was last modified', @level0type = N'SCHEMA',
  @level0name = N'Customer', @level1type = N'TABLE', @level1name = N'Phone',
  @level2type = N'COLUMN', @level2name = N'ModifiedDate';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'a description of the type of phone (e.g. Mobile, work, home)',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'PhoneType', @level2type = N'COLUMN',
  @level2name = N'TypeOfPhone';
GO
EXEC sys.sp_addextendedproperty @name = N'MS_Description',
  @value = N'when the definition of the type of phone was last modified',
  @level0type = N'SCHEMA', @level0name = N'Customer', @level1type = N'TABLE',
  @level1name = N'PhoneType', @level2type = N'COLUMN',
  @level2name = N'ModifiedDate';
GO

