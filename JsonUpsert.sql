/* Importing JSON collections of documents into SQL Server is fairly easy if there is an underlying table schema
 to them. If the documents have  different schemas then you have little chance. Fortunately, this is rare
 Let's start this gently, putting simple collections into strings which we will insert into a table. 
 We'll use the example of sheep-counting words, collected from many different parts of Great Britain and 
 Brittany. The simple aim is to put them into a table */


IF Object_Id('SheepCountingWords','U') IS NOT NULL DROP TABLE SheepCountingWords
CREATE TABLE SheepCountingWords
  (
  Number INT NOT NULL,
  Word NVARCHAR(40) NOT NULL,
  Region NVARCHAR(40) NOT NULL,
  CONSTRAINT NumberRegionKey PRIMARY KEY  (Number,Region)
  );
GO

/* the quickest way to insert JSON into a table will always be the straight insert, 
even after an existence check. It is a good  practice to make the process idempotent 
by only inserting the records that don't already exist. I'll use the MERGE just to keep 
things simple, though the left outer join with a null check is faster. The MERGE is
far more convenient because it will accept a table-source such as a result from the
OpenJSON function */

IF EXISTS (SELECT * FROM tempdb.sys.objects WHERE name LIKE '#MergeJSONwithCountingTable%') DROP procedure #MergeJSONwithCountingTable
GO
CREATE PROCEDURE #MergeJSONwithCountingTable @json NVARCHAR(MAX),
  @source NVARCHAR(MAX)
/**
Summary: >
  This inserts, or updates, into a table (dbo.SheepCountingWords) a JSON string consisting 
  of sheep-counting words for  numbers between one and twenty used traditionally by sheep
  farmers in Gt Britain and Brittany. it allows records to be inserted or updated in any
  order or quantity.
  
Author: PhilFactor
Date: 20/04/2018
Database: CountingSheep
Examples:
   - EXECUTE #MergeJSONwithCountingTable @json=@OneToTen, @Source='Lincolnshire'
   - EXECUTE #MergeJSONwithCountingTable @Source='Lincolnshire', @json='[{
     "number": 11, "word": "Yan-a-dik"}, {"number": 12, "word": "Tan-a-dik"}]'
Returns: >
  nothing
**/
AS
MERGE dbo.SheepCountingWords AS target
USING
  (
  SELECT DISTINCT Number, Word, @source --duplicates cause 
    FROM --                         unique constraint violations
    OpenJson(@json)
    WITH (Number INT '$.number', Word VARCHAR(20) '$.word')
  ) AS source (Number, Word, Region)
ON target.Number = source.Number AND target.Region = source.Region
WHEN MATCHED AND (source.Word <> target.Word) THEN
  UPDATE SET target.Word = source.Word
WHEN NOT MATCHED THEN 
  INSERT (Number, Word, Region)
    VALUES
      (source.Number, source.Word, source.Region);
GO
/* now we try it out. Let's assemble a couple of simple json strings
from a table-source.*/

DECLARE @oneToTen NVARCHAR(MAX) =
	(
	SELECT LincolnshireCounting.number, LincolnshireCounting.word
	FROM
		(
		VALUES (1, 'Yan'), (2, 'Tan'), (3, 'Tethera'), (4, 'Pethera'),
		(5, 'Pimp'), (6, 'Sethera'), (7, 'Lethera'), (8, 'Hovera'),
		(9, 'Covera'), (10, 'Dik')
		) AS LincolnshireCounting (number, word)
	FOR JSON AUTO
	)

DECLARE @ElevenToTwenty NVARCHAR(MAX) =
    (
    SELECT LincolnshireCounting.number, LincolnshireCounting.word
    FROM
		(
		VALUES (11, 'Yan-a-dik'), (12, 'Tan-a-dik'), (13, 'Tethera-dik'),
		(14, 'Pethera-dik'), (15, 'Bumfit'), (16, 'Yan-a-bumtit'),
		(17, 'Tan-a-bumfit'), (18, 'Tethera-bumfit'),
		(19, 'Pethera-bumfit'), (20, 'Figgot')
		) AS LincolnshireCounting (number, word)
    FOR JSON AUTO
    )

/*this second query gives (formatted)...
[{
  "number": 11,  "word": "Yan-a-dik"
}, {
  "number": 12,  "word": "Tan-a-dik"
}, {
  "number": 13,  "word": "Tethera-dik"
}, {
  "number": 14,  "word": "Pethera-dik"
}, {
  "number": 15,  "word": "Bumfit"
}, {
  "number": 16,  "word": "Yan-a-bumtit"
}, {
  "number": 17,  "word": "Tan-a-bumfit"
}, {
  "number": 18,  "word": "Tethera-bumfit"
}, {
  "number": 19,  "word": "Pethera-bumfit"
}, {
  "number": 20,  "word": "Figgot"
}] 

which is easy to convert to a table source */


SELECT  Number, Word
    FROM
    OpenJson('[{
  "number": 11,  "word": "Yan-a-dik"
}, {
  "number": 12,  "word": "Tan-a-dik"
}, {
  "number": 13,  "word": "Tethera-dik"
}, {
  "number": 14,  "word": "Pethera-dik"
}, {
  "number": 15,  "word": "Bumfit"
}, {
  "number": 16,  "word": "Yan-a-bumtit"
}, {
  "number": 17,  "word": "Tan-a-bumfit"
}, {
  "number": 18,  "word": "Tethera-bumfit"
}, {
  "number": 19,  "word": "Pethera-bumfit"
}, {
  "number": 20,  "word": "Figgot"
}] '
)WITH (Number INT '$.number', Word VARCHAR(20) '$.word')

--Now we can EXECUTE the procedure to store them in the table
 
EXECUTE #MergeJSONwithCountingTable @json=@ElevenToTwenty, @Source='Lincolnshire'
EXECUTE #MergeJSONwithCountingTable @json=@OneToTen, @Source='Lincolnshire'
--and make sure that we are protected against duplicate inserts
EXECUTE #MergeJSONwithCountingTable @Source='Lincolnshire', @json='[{
  "number": 11, "word": "Yan-a-dik"}, {"number": 12, "word": "Tan-a-dik"}]'

SELECT * FROM SheepCountingWords
/*What if you want to import the sheep-counting words from several regions? This is 
OK for a collection that models a single table. However, real like isn't like that. 
Not even Sheep-Counting Words are like that. A little internalised 
Chris Date will be whispering in your ear that there are two relations here, a 
region and the name for a number. 
Your Javascipt will more likely be this (just reducing it to two numbers rather
than the twenty)

[{
   "region": "Wilts",
   "sequence": [{
      "number": 1,
      "word": "Ain"
   }, {
      "number": 2,
      "word": "Tain"
   }]
}, {
   "region": "Scots",
   "sequence": [{
      "number": 1,
      "word": "Yan"
   }, {
      "number": 2,
      "word": "Tyan"
   }]
}]
*/

SELECT DISTINCT Number, Word, Region
  FROM OpenJson(
'[{"region":"Wilts","sequence":[{"number":1,"word":"Ain"},{"number":2,"word":"Tain"}]},
{"region":"Scots","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tyan"}]}]')
WITH (Region NVARCHAR(30) N'$.region', sequence NVARCHAR(MAX) N'$.sequence' AS JSON)
    OUTER APPLY
  OpenJson(sequence) --to get the number and word within each array element 
  WITH (Number INT N'$.number', Word NVARCHAR(30) N'$.word')


IF EXISTS
  (
  SELECT *
    FROM tempdb.sys.objects
    WHERE objects.name LIKE '#MergeJSONWithEmbeddedArraywithCountingTable%'
  )
  DROP PROCEDURE #MergeJSONWithEmbeddedArraywithCountingTable;
GO
CREATE PROCEDURE #MergeJSONWithEmbeddedArraywithCountingTable @json NVARCHAR(MAX)
/**
Summary: >
  This inserts, or updates, into a table (dbo.SheepCountingWords) a JSON string consisting 
  of sheep-counting words for  numbers between one and twenty used traditionally by sheep
  farmers in Gt Britain and Brittany. it allows records to be inserted or updated in any
  order or quantity.
  
Author: PhilFactor
Date: 20/04/2018
Database: CountingSheep
Examples:
   - EXECUTE #MergeJSONWithEmbeddedArraywithCountingTable @json=@OneToTen, @Source='Lincolnshire'
   - EXECUTE #MergeJSONWithEmbeddedArraywithCountingTable @json='
     [{"region":"Wilts","sequence":[{"number":1,"word":"Ain"},{"number":2,"word":"Tain"}]},
     {"region":"Scots","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tyan"}]}]'
Returns: >
  nothing
**/
AS
MERGE dbo.SheepCountingWords AS target
USING
  (
  SELECT DISTINCT Number, Word, Region
  FROM OpenJson(@json) 
  WITH (Region NVARCHAR(30) N'$.region', sequence NVARCHAR(MAX) N'$.sequence' AS JSON)
    OUTER APPLY
  OpenJson(sequence)
  WITH (Number INT N'$.number', Word NVARCHAR(30) N'$.word')
  ) AS source (Number, Word, Region)
ON target.Number = source.Number AND target.Region = source.Region
WHEN MATCHED AND (source.Word <> target.Word) THEN
  UPDATE SET target.Word = source.Word
WHEN NOT MATCHED THEN INSERT (Number, Word, Region)
                      VALUES
                        (source.Number, source.Word, source.Region);
GO


/* and we can try it out easily */

EXECUTE #MergeJSONWithEmbeddedArraywithCountingTable '[{
   "region": "Wilts",
   "sequence": [{
      "number": 1,
      "word": "Ain"
   }, {
      "number": 2,
      "word": "Tain"
   }]
}, {
   "region": "Scots",
   "sequence": [{
      "number": 1,
      "word": "Yan"
   }, {
      "number": 2,
      "word": "Tyan"
   }]
}]'

DECLARE @json NVARCHAR(MAX)='[
   {
   "region": "Wilts",
   "sequence": [{
      "number": 1,
      "word": "Ain"
   }, {
      "number": 2,
      "word": "Tain"
   }]
},{
   "region": "Wilts",
   "sequence": [{
      "number": 1,
      "word": "Ain"
   }, {
      "number": 2,
      "word": "Tain"
   }]
}, {
   "region": "Scots",
   "sequence": [{
      "number": 1,
      "word": "Yan"
   }, {
      "number": 2,
      "word": "Tyan"
   }]
}]'
EXECUTE #MergeJSONWithEmbeddedArraywithCountingTable @json
go
/* so lets try a larger JSON collection */

DELETE FROM dbo.SheepCountingWords
DECLARE @AllRegions NVARCHAR(MAX) =
  '[{"region":"Wilts","sequence":[{"number":1,"word":"Ain"},{"number":2,"word":"Tain"},{"number":3,"word":"Tethera"},{"number":4,"word":"Methera"},{"number":5,"word":"Mimp"},{"number":6,"word":"Ayta"},{"number":7,"word":"Slayta"},{"number":8,"word":"Laura"},{"number":9,"word":"Dora"},{"number":10,"word":"Dik"},{"number":11,"word":"Ain-a-dik"},{"number":12,"word":"Tain-a-dik"},{"number":13,"word":"Tethera-a-dik"},{"number":14,"word":"Methera-a-dik"},{"number":15,"word":"Mit"},{"number":16,"word":"Ain-a-mit"},{"number":17,"word":"Tain-a-mit"},{"number":18,"word":"Tethera-mit"},{"number":19,"word":"Gethera-mit"},{"number":20,"word":"Ghet"}]},{"region":"Scots","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tyan"},{"number":3,"word":"Tethera"},{"number":4,"word":"Methera"},{"number":5,"word":"Pimp"},{"number":6,"word":"Sethera"},{"number":7,"word":"Lethera"},{"number":8,"word":"Hovera"},{"number":9,"word":"Dovera"},{"number":10,"word":"Dik"},{"number":11,"word":"Yanadik"},{"number":12,"word":"Tyanadik"},{"number":13,"word":"Tetheradik"},{"number":14,"word":"Metheradik"},{"number":15,"word":"Bumfitt"},{"number":16,"word":"Yanabumfit"},{"number":17,"word":"Tyanabumfitt"},{"number":18,"word":"Tetherabumfitt"},{"number":19,"word":"Metherabumfitt"},{"number":20,"word":"Giggot"}]},{"region":"Welsh","sequence":[{"number":1,"word":"Un"},{"number":2,"word":"Dau"},{"number":3,"word":"Tri"},{"number":4,"word":"Pedwar"},{"number":5,"word":"Pump"},{"number":6,"word":"Chwech"},{"number":7,"word":"Saith"},{"number":8,"word":"Wyth"},{"number":9,"word":"Naw"},{"number":10,"word":"Deg"},{"number":11,"word":"Un ar ddeg"},{"number":12,"word":"Deuddeg"},{"number":13,"word":"Tri ar ddeg"},{"number":14,"word":"Pedwar ar ddeg"},{"number":15,"word":"Pymtheg"},{"number":16,"word":"Un ar bymtheg"},{"number":17,"word":"Dau ar bymtheg"},{"number":18,"word":"Deunaw"},{"number":19,"word":"Pedwar ar bymtheg"},{"number":20,"word":"Ugain"}]},{"region":"Bowland","sequence":[{"number":1,"word":"Yain"},{"number":2,"word":"Tain"},{"number":3,"word":"Eddera"},{"number":4,"word":"Peddera"},{"number":5,"word":"Pit"},{"number":6,"word":"Tayter"},{"number":7,"word":"Layter"},{"number":8,"word":"Overa"},{"number":9,"word":"Covera"},{"number":10,"word":"Dix"},{"number":11,"word":"Yain-a-dix"},{"number":12,"word":"Tain-a-dix"},{"number":13,"word":"Eddera-a-dix"},{"number":14,"word":"Peddera-a-dix"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yain-a-bumfit"},{"number":17,"word":"Tain-a-bumfit"},{"number":18,"word":"Eddera-bumfit"},{"number":19,"word":"Peddera-a-bumfit"},{"number":20,"word":"Jiggit"}]},{"region":"Rathmell","sequence":[{"number":1,"word":"Aen"},{"number":2,"word":"Taen"},{"number":3,"word":"Tethera"},{"number":4,"word":"Fethera"},{"number":5,"word":"Phubs"},{"number":6,"word":"Aayther"},{"number":7,"word":"Layather"},{"number":8,"word":"Quoather"},{"number":9,"word":"Quaather"},{"number":10,"word":"Dugs"},{"number":11,"word":"Aena dugs"},{"number":12,"word":"Taena dugs"},{"number":13,"word":"Tethera dugs"},{"number":14,"word":"Fethera dugs"},{"number":15,"word":"Buon"},{"number":16,"word":"Aena buon"},{"number":17,"word":"Taena buon"},{"number":18,"word":"Tethera buon"},{"number":19,"word":"Fethera buon"},{"number":20,"word":"Gun a gun"}]},{"region":"Nidderdale","sequence":[{"number":1,"word":"Yain"},{"number":2,"word":"Tain"},{"number":3,"word":"Eddero"},{"number":4,"word":"Peddero"},{"number":5,"word":"Pitts"},{"number":6,"word":"Tayter"},{"number":7,"word":"Layter"},{"number":8,"word":"Overo"},{"number":9,"word":"Covero"},{"number":10,"word":"Dix"},{"number":11,"word":"Yaindix"},{"number":12,"word":"Taindix"},{"number":13,"word":"Edderodix"},{"number":14,"word":"Pedderodix"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yain-o-Bumfit"},{"number":17,"word":"Tain-o-Bumfit"},{"number":18,"word":"Eddero-Bumfit"},{"number":19,"word":"Peddero-Bumfit"},{"number":20,"word":"Jiggit"}]},{"region":"Swaledale","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tan"},{"number":3,"word":"Tether"},{"number":4,"word":"Mether"},{"number":5,"word":"Pip"},{"number":6,"word":"Azer"},{"number":7,"word":"Sezar"},{"number":8,"word":"Akker"},{"number":9,"word":"Conter"},{"number":10,"word":"Dick"},{"number":11,"word":"Yanadick"},{"number":12,"word":"Tanadick"},{"number":13,"word":"Tetheradick"},{"number":14,"word":"Metheradick"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yanabum"},{"number":17,"word":"Tanabum"},{"number":18,"word":"Tetherabum"},{"number":19,"word":"Metherabum"},{"number":20,"word":"Jigget"}]},{"region":"Teesdale","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tean"},{"number":3,"word":"Tether"},{"number":4,"word":"Mether"},{"number":5,"word":"Pip"},{"number":6,"word":"Lezar"},{"number":7,"word":"Azar"},{"number":8,"word":"Catrah"},{"number":9,"word":"Borna"},{"number":10,"word":"Dick"},{"number":11,"word":"Yan-a-dick"},{"number":12,"word":"Tean-a-dick"},{"number":13,"word":"Tether-dick"},{"number":14,"word":"Mether-dick"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yan-a-bum"},{"number":17,"word":"Tean-a-bum"},{"number":18,"word":"Tethera-bum"},{"number":19,"word":"Methera-bum"},{"number":20,"word":"Jiggit"}]},{"region":"Derbyshire","sequence":[{"number":1,"word":"Yain"},{"number":2,"word":"Tain"},{"number":3,"word":"Eddero"},{"number":4,"word":"Pederro"},{"number":5,"word":"Pitts"},{"number":6,"word":"Tayter"},{"number":7,"word":"Later"},{"number":8,"word":"Overro"},{"number":9,"word":"Coverro"},{"number":10,"word":"Dix"},{"number":11,"word":"Yain-dix"},{"number":12,"word":"Tain-dix"},{"number":13,"word":"Eddero-dix"},{"number":14,"word":"Peddero-dix"},{"number":15,"word":"Bumfitt"},{"number":16,"word":"Yain-o-bumfitt"},{"number":17,"word":"Tain-o-bumfitt"},{"number":18,"word":"Eddero-o-bumfitt"},{"number":19,"word":"Peddero-o-bumfitt"},{"number":20,"word":"Jiggit"}]},{"region":"Weardale","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Teyan"},{"number":3,"word":"Tethera"},{"number":4,"word":"Methera"},{"number":5,"word":"Tic"},{"number":6,"word":"Yan-a-tic"},{"number":7,"word":"Teyan-a-tic"},{"number":8,"word":"Tethera-tic"},{"number":9,"word":"Methera-tic"},{"number":10,"word":"Bub"},{"number":11,"word":"Yan-a-bub"},{"number":12,"word":"Teyan-a-bub"},{"number":13,"word":"Tethera-bub"},{"number":14,"word":"Methera-bub"},{"number":15,"word":"Tic-a-bub"},{"number":16,"word":"Yan-tic-a-bub"},{"number":17,"word":"Teyan-tic-a-bub"},{"number":18,"word":"Tethea-tic-a-bub"},{"number":19,"word":"Methera-tic-a-bub"},{"number":20,"word":"Gigget"}]},{"region":"Tong","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tan"},{"number":3,"word":"Tether"},{"number":4,"word":"Mether"},{"number":5,"word":"Pick"},{"number":6,"word":"Sesan"},{"number":7,"word":"Asel"},{"number":8,"word":"Catel"},{"number":9,"word":"Oiner"},{"number":10,"word":"Dick"},{"number":11,"word":"Yanadick"},{"number":12,"word":"Tanadick"},{"number":13,"word":"Tetheradick"},{"number":14,"word":"Metheradick"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yanabum"},{"number":17,"word":"Tanabum"},{"number":18,"word":"Tetherabum"},{"number":19,"word":"Metherabum"},{"number":20,"word":"Jigget"}]},{"region":"Kirkby Lonsdale","sequence":[{"number":1,"word":"Yaan"},{"number":2,"word":"Tyaan"},{"number":3,"word":"Taed''ere"},{"number":4,"word":"Mead''ere"},{"number":5,"word":"Mimp"},{"number":6,"word":"Haites"},{"number":7,"word":"Saites"},{"number":8,"word":"Haoves"},{"number":9,"word":"Daoves"},{"number":10,"word":"Dik"},{"number":11,"word":"Yaan''edik"},{"number":12,"word":"Tyaan''edik"},{"number":13,"word":"Tead''eredik"},{"number":14,"word":"Mead''eredik"},{"number":15,"word":"Boon, buom, buum"},{"number":16,"word":"Yaan''eboon"},{"number":17,"word":"Tyaan''eboon"},{"number":18,"word":"Tead''ereboon"},{"number":19,"word":"Mead''ereboon"},{"number":20,"word":"Buom''fit, buum''fit"}]},{"region":"Wensleydale","sequence":[{"number":1,"word":"Yain"},{"number":2,"word":"Tain"},{"number":3,"word":"Eddero"},{"number":4,"word":"Peddero"},{"number":5,"word":"Pitts"},{"number":6,"word":"Tayter"},{"number":7,"word":"Later"},{"number":8,"word":"Overro"},{"number":9,"word":"Coverro"},{"number":10,"word":"Disc"},{"number":11,"word":"Yain disc"},{"number":12,"word":"Tain disc"},{"number":13,"word":"Ederro disc"},{"number":14,"word":"Peddero disc"},{"number":15,"word":"Bumfitt"},{"number":16,"word":"Bumfitt yain"},{"number":17,"word":"Bumfitt tain"},{"number":18,"word":"Bumfitt ederro"},{"number":19,"word":"Bumfitt peddero"},{"number":20,"word":"Jiggit"}]},{"region":"Derbyshire Dales","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tan"},{"number":3,"word":"Tethera"},{"number":4,"word":"Methera"},{"number":5,"word":"Pip"},{"number":6,"word":"Sethera"},{"number":7,"word":"Lethera"},{"number":8,"word":"Hovera"},{"number":9,"word":"Dovera"},{"number":10,"word":"Dick"},{"number":11,"word":""},{"number":12,"word":""},{"number":13,"word":""},{"number":14,"word":""},{"number":15,"word":""},{"number":16,"word":""},{"number":17,"word":""},{"number":18,"word":""},{"number":19,"word":""},{"number":20,"word":""}]},{"region":"Lincolnshire","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tan"},{"number":3,"word":"Tethera"},{"number":4,"word":"Pethera"},{"number":5,"word":"Pimp"},{"number":6,"word":"Sethera"},{"number":7,"word":"Lethera"},{"number":8,"word":"Hovera"},{"number":9,"word":"Covera"},{"number":10,"word":"Dik"},{"number":11,"word":"Yan-a-dik"},{"number":12,"word":"Tan-a-dik"},{"number":13,"word":"Tethera-dik"},{"number":14,"word":"Pethera-dik"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yan-a-bumfit"},{"number":17,"word":"Tan-a-bumfit"},{"number":18,"word":"Tethera-bumfit"},{"number":19,"word":"Pethera-bumfit"},{"number":20,"word":"Figgot"}]},{"region":"Southwest England ","sequence":[{"number":1,"word":"Yahn"},{"number":2,"word":"Tayn"},{"number":3,"word":"Tether"},{"number":4,"word":"Mether"},{"number":5,"word":"Mumph"},{"number":6,"word":"Hither"},{"number":7,"word":"Lither"},{"number":8,"word":"Auver"},{"number":9,"word":"Dauver"},{"number":10,"word":"Dic"},{"number":11,"word":"Yahndic"},{"number":12,"word":"Tayndic"},{"number":13,"word":"Tetherdic"},{"number":14,"word":"Metherdic"},{"number":15,"word":"Mumphit"},{"number":16,"word":"Yahna Mumphit"},{"number":17,"word":"Tayna Mumphit"},{"number":18,"word":"Tethera Mumphit"},{"number":19,"word":"Methera Mumphit"},{"number":20,"word":"Jigif"}]},{"region":"West Country Dorset","sequence":[{"number":1,"word":"Hant"},{"number":2,"word":"Tant"},{"number":3,"word":"Tothery"},{"number":4,"word":"Forthery"},{"number":5,"word":"Fant"},{"number":6,"word":"Sahny"},{"number":7,"word":"Dahny"},{"number":8,"word":"Downy"},{"number":9,"word":"Dominy"},{"number":10,"word":"Dik"},{"number":11,"word":"Haindik"},{"number":12,"word":"Taindik"},{"number":13,"word":"Totherydik"},{"number":14,"word":"Fotherydik"},{"number":15,"word":"Jiggen"},{"number":16,"word":"Hain Jiggen"},{"number":17,"word":"Tain Jiggen"},{"number":18,"word":"Tother Jiggen"},{"number":19,"word":"Fother Jiggen"},{"number":20,"word":"Full Score"}]},{"region":"Coniston","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Taen"},{"number":3,"word":"Tedderte"},{"number":4,"word":"Medderte"},{"number":5,"word":"Pimp"},{"number":6,"word":"Haata"},{"number":7,"word":"Slaata"},{"number":8,"word":"Lowra"},{"number":9,"word":"Dowra"},{"number":10,"word":"Dick"},{"number":11,"word":"Yan-a-Dick"},{"number":12,"word":"Taen-a-Dick"},{"number":13,"word":"Tedder-a-Dick"},{"number":14,"word":"Medder-a-Dick"},{"number":15,"word":"Mimph"},{"number":16,"word":"Yan-a-Mimph"},{"number":17,"word":"Taen-a-Mimph"},{"number":18,"word":"Tedder-a-Mimph"},{"number":19,"word":"Medder-a-Mimph"},{"number":20,"word":"Gigget"}]},{"region":"Borrowdale","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tyan"},{"number":3,"word":"Tethera"},{"number":4,"word":"Methera"},{"number":5,"word":"Pimp"},{"number":6,"word":"Sethera"},{"number":7,"word":"Lethera"},{"number":8,"word":"Hovera"},{"number":9,"word":"Dovera"},{"number":10,"word":"Dick"},{"number":11,"word":"Yan-a-Dick"},{"number":12,"word":"Tyan-a-Dick"},{"number":13,"word":"Tethera-Dick"},{"number":14,"word":"Methera-Dick"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yan-a-bumfit"},{"number":17,"word":"Tyan-a-bumfit"},{"number":18,"word":"Tethera Bumfit"},{"number":19,"word":"Methera Bumfit"},{"number":20,"word":"Giggot"}]},{"region":"Eskdale","sequence":[{"number":1,"word":"Yaena"},{"number":2,"word":"Taena"},{"number":3,"word":"Teddera"},{"number":4,"word":"Meddera"},{"number":5,"word":"Pimp"},{"number":6,"word":"Seckera"},{"number":7,"word":"Leckera"},{"number":8,"word":"Hofa"},{"number":9,"word":"Lofa"},{"number":10,"word":"Dec"},{"number":11,"word":""},{"number":12,"word":""},{"number":13,"word":""},{"number":14,"word":""},{"number":15,"word":""},{"number":16,"word":""},{"number":17,"word":""},{"number":18,"word":""},{"number":19,"word":""},{"number":20,"word":""}]},{"region":"Westmorland","sequence":[{"number":1,"word":"Yan"},{"number":2,"word":"Tahn"},{"number":3,"word":"Teddera"},{"number":4,"word":"Meddera"},{"number":5,"word":"Pimp"},{"number":6,"word":"Settera"},{"number":7,"word":"Lettera"},{"number":8,"word":"Hovera"},{"number":9,"word":"Dovera"},{"number":10,"word":"Dick"},{"number":11,"word":"Yan Dick"},{"number":12,"word":"Tahn Dick"},{"number":13,"word":"Teddera Dick"},{"number":14,"word":"Meddera Dick"},{"number":15,"word":"Bumfit"},{"number":16,"word":"Yan-a-Bumfit"},{"number":17,"word":"Tahn-a Bumfit"},{"number":18,"word":"Teddera-Bumfit"},{"number":19,"word":"Meddera-Bumfit"},{"number":20,"word":"Jiggot"}]},{"region":"Lakes","sequence":[{"number":1,"word":"Auna"},{"number":2,"word":"Peina"},{"number":3,"word":"Para"},{"number":4,"word":"Peddera"},{"number":5,"word":"Pimp"},{"number":6,"word":"Ithy"},{"number":7,"word":"Mithy"},{"number":8,"word":"Owera"},{"number":9,"word":"Lowera"},{"number":10,"word":"Dig"},{"number":11,"word":"Ain-a-dig"},{"number":12,"word":"Pein-a-dig"},{"number":13,"word":"Para-a-dig"},{"number":14,"word":"Peddaer-a-dig"},{"number":15,"word":"Bunfit"},{"number":16,"word":"Aina-a-bumfit"},{"number":17,"word":"Pein-a-bumfit"},{"number":18,"word":"Par-a-bunfit"},{"number":19,"word":"Pedder-a-bumfit"},{"number":20,"word":"Giggy"}]},{"region":"Dales","sequence":[{"number":1,"word":"Yain"},{"number":2,"word":"Tain"},{"number":3,"word":"Edderoa"},{"number":4,"word":"Peddero"},{"number":5,"word":"Pitts"},{"number":6,"word":"Tayter"},{"number":7,"word":"Leter"},{"number":8,"word":"Overro"},{"number":9,"word":"Coverro"},{"number":10,"word":"Dix"},{"number":11,"word":"Yain-dix"},{"number":12,"word":"Tain-dix"},{"number":13,"word":"Eddero-dix"},{"number":14,"word":"Pedderp-dix"},{"number":15,"word":"Bumfitt"},{"number":16,"word":"Yain-o-bumfitt"},{"number":17,"word":"Tain-o-bumfitt"},{"number":18,"word":"Eddero-bumfitt"},{"number":19,"word":"Peddero-bumfitt"},{"number":20,"word":"Jiggit"}]},{"region":"Ancient British","sequence":[{"number":1,"word":"oinos"},{"number":2,"word":"dewou"},{"number":3,"word":"trīs "},{"number":4,"word":"petwār"},{"number":5,"word":"pimpe"},{"number":6,"word":"swexs"},{"number":7,"word":"sextam"},{"number":8,"word":"oxtū"},{"number":9,"word":"nawam"},{"number":10,"word":"dekam"},{"number":11,"word":"oindekam"},{"number":12,"word":"deudekam"},{"number":13,"word":"trīdekam"},{"number":14,"word":"petwārdekam"},{"number":15,"word":"penpedekam"},{"number":16,"word":"swedekam"},{"number":17,"word":"sextandekam"},{"number":18,"word":"oxtūdekam"},{"number":19,"word":"nawandekam"},{"number":20,"word":"ukintī"}]},{"region":"Old Welsh","sequence":[{"number":1,"word":"un"},{"number":2,"word":"dou"},{"number":3,"word":"tri"},{"number":4,"word":"petuar"},{"number":5,"word":"pimp"},{"number":6,"word":"chwech"},{"number":7,"word":"seith"},{"number":8,"word":"wyth"},{"number":9,"word":"nau"},{"number":10,"word":"dec"},{"number":11,"word":""},{"number":12,"word":""},{"number":13,"word":""},{"number":14,"word":""},{"number":15,"word":""},{"number":16,"word":""},{"number":17,"word":""},{"number":18,"word":""},{"number":19,"word":""},{"number":20,"word":""}]},{"region":"Cornish (Kemmyn)","sequence":[{"number":1,"word":"unn"},{"number":2,"word":"dew, diw"},{"number":3,"word":"tri, teyr"},{"number":4,"word":"peswar"},{"number":5,"word":"pymp"},{"number":6,"word":"hwegh"},{"number":7,"word":"seyth"},{"number":8,"word":"eth"},{"number":9,"word":"naw"},{"number":10,"word":"deg"},{"number":11,"word":"unnek"},{"number":12,"word":"dewdhek"},{"number":13,"word":"trydhek"},{"number":14,"word":"peswardhek"},{"number":15,"word":"pymthek"},{"number":16,"word":"hwetek"},{"number":17,"word":"seytek"},{"number":18,"word":"etek"},{"number":19,"word":"nownsek"},{"number":20,"word":"ugens"}]},{"region":"Breton","sequence":[{"number":1,"word":"unan"},{"number":2,"word":"daou, div"},{"number":3,"word":"tri, teir"},{"number":4,"word":"pevar, peder"},{"number":5,"word":"pemp"},{"number":6,"word":"c''hwec''h"},{"number":7,"word":"seizh"},{"number":8,"word":"eizh"},{"number":9,"word":"nav"},{"number":10,"word":"dek"},{"number":11,"word":"unnek"},{"number":12,"word":"daouzek"},{"number":13,"word":"trizek"},{"number":14,"word":"pevarzek"},{"number":15,"word":"pemzek"},{"number":16,"word":"c''hwezek"},{"number":17,"word":"seitek"},{"number":18,"word":"triwec''h"},{"number":19,"word":"naontek"},{"number":20,"word":"ugent"}]}]
'
EXECUTE #MergeJSONWithEmbeddedArraywithCountingTable @AllRegions

 

DELETE FROM sheepcountingwords
DECLARE @JSON nvarchar(max)
SELECT @json = BulkColumn
 FROM OPENROWSET (BULK 'D:\raw data\YanTanTethera.json', SINGLE_BLOB) as j
 --must be UTF-16 Little Endian

 EXECUTE #MergeJSONWithEmbeddedArraywithCountingTable @JSON

/* and now do a pivot rotation */

SELECT SheepCountingWords.Number,
  Max(CASE WHEN SheepCountingWords.Region = 'Ancient British' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Ancient British],
  Max(CASE WHEN SheepCountingWords.Region = 'Borrowdale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Borrowdale,
  Max(CASE WHEN SheepCountingWords.Region = 'Bowland' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Bowland,
  Max(CASE WHEN SheepCountingWords.Region = 'Breton' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Breton,
  Max(CASE WHEN SheepCountingWords.Region = 'Coniston' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Coniston,
  Max(CASE WHEN SheepCountingWords.Region = 'Cornish (Kemmyn)' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Cornish (Kemmyn)],
  Max(CASE WHEN SheepCountingWords.Region = 'Craven and N.W. Moorlands' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Craven and N.W. Moorlands],
  Max(CASE WHEN SheepCountingWords.Region = 'Dales' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Dales,
  Max(CASE WHEN SheepCountingWords.Region = 'Derbyshire' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Derbyshire,
  Max(CASE WHEN SheepCountingWords.Region = 'Derbyshire Dales' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Derbyshire Dales],
  Max(CASE WHEN SheepCountingWords.Region = 'Eskdale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Eskdale,
  Max(CASE WHEN SheepCountingWords.Region = 'Gaelic' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Gaelic,
  Max(CASE WHEN SheepCountingWords.Region = 'Kirkby Lonsdale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Kirkby Lonsdale],
  Max(CASE WHEN SheepCountingWords.Region = 'Lakes' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Lakes,
  Max(CASE WHEN SheepCountingWords.Region = 'Lincolnshire' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Lincolnshire,
  Max(CASE WHEN SheepCountingWords.Region = 'Middleton - in- Teesdale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Middleton - in- Teesdale],
  Max(CASE WHEN SheepCountingWords.Region = 'Modern Irish' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Modern Irish],
  Max(CASE WHEN SheepCountingWords.Region = 'Nidderdale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Nidderdale,
  Max(CASE WHEN SheepCountingWords.Region = 'North Riding' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [North Riding],
  Max(CASE WHEN SheepCountingWords.Region = 'Old Welsh' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Old Welsh],
  Max(CASE WHEN SheepCountingWords.Region = 'Rathmell' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Rathmell,
  Max(CASE WHEN SheepCountingWords.Region = 'Scots' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Scots,
  Max(CASE WHEN SheepCountingWords.Region = 'Southwest England ' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Southwest England ],
  Max(CASE WHEN SheepCountingWords.Region = 'Swaledale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Swaledale,
  Max(CASE WHEN SheepCountingWords.Region = 'Teesdale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Teesdale,
  Max(CASE WHEN SheepCountingWords.Region = 'Tong' THEN 
             SheepCountingWords.Word ELSE '' END
     ) AS Tong,
  Max(CASE WHEN SheepCountingWords.Region = 'Weardale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Weardale,
  Max(CASE WHEN SheepCountingWords.Region = 'Welsh (feminine)' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Welsh (feminine)],
  Max(CASE WHEN SheepCountingWords.Region = 'Welsh (masculine)' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [Welsh (masculine)],
  Max(CASE WHEN SheepCountingWords.Region = 'Wensleydale' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Wensleydale,
  Max(CASE WHEN SheepCountingWords.Region = 'West Country Dorset' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS [West Country Dorset],
  Max(CASE WHEN SheepCountingWords.Region = 'Westmorland' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Westmorland,
  Max(CASE WHEN SheepCountingWords.Region = 'Wilts' THEN
             SheepCountingWords.Word ELSE '' END
     ) AS Wilts
  FROM SheepCountingWords
  GROUP BY SheepCountingWords.Number
  ORDER BY SheepCountingWords.Number

