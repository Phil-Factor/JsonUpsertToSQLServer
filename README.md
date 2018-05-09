# Importing JSON Collections into SQL Server.

This is a repository to go with a Simple-talk article that is yet to be published. 

It demonstrates how to import a JSON file into SQL Server and accomodate it in a staging table, before assimilating the data by stocking a set of relational tables. 

JSON support in SQL Server has been the result of a long wait, but now that we have it, it opens up several possibilities.

No SQL Server Developer or admin needs to rule out using JSON for ETL (Extract, Transform, Load) processes to pass data between JSON-based document databases and SQL Server. The features that SQL Server has are sufficient, and far easier to use than the SQL Server XML support. 
A typical SQL Server database is far more complex than the simple example used in this article, but it is certainly not an outrageous idea that a database could have its essential static data drawn from JSON documents: These are more versatile than VALUE statements and more efficient than individual INSERT statements.

I’m inclined to smile on the idea of transferring data between the application and database as JSON. It is usually easier for front-end application programmers, and we Database folks can, at last, do all the checks and transformations to accommodate data within the arcane relational world, rather than insist on the application programmer doing it. It will also decouple the application and database to the extent that the two no longer would need to shadow each other in terms of revisions.
JSON collections of documents represent an industry-standard way of transferring data. It is today’s  CSV, and it is good to know that SQL Server can support  it.

