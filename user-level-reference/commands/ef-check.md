# /ef-check - Check Entity Framework Migrations

Check EF Core migration status and database synchronization.

## Arguments

- `$ARGUMENTS` - Path to project containing DbContext (optional)

## Workflow

1. **Locate project**
   - If path provided in `$ARGUMENTS`, use it
   - Otherwise, search for projects with EF Core references
   - Look for files containing "DbContext"

2. **Get DbContext info**
   - Call `ef_dbcontext_info(project_path)`
   - Confirm database provider and connection
   - Note if multiple DbContexts exist

3. **Check migration status**
   - Call `ef_migrations_status(project_path)`
   - List all migrations with applied/pending status
   - Note the last applied migration

4. **Check for pending migrations**
   - Call `ef_pending_migrations(project_path)`
   - If pending migrations exist, list them
   - Warn if database is out of sync

5. **Generate report**
   ```
   ## DbContext: [Name]
   Provider: [e.g., SqlServer, PostgreSQL]

   ## Migration Status
   Total: X | Applied: Y | Pending: Z

   ## Pending Migrations
   [List if any]

   ## Recommendations
   [Next steps]
   ```

6. **Suggest actions**
   - If pending: Suggest `dotnet ef database update`
   - If model changes detected: Suggest creating new migration
   - If conflicts: Warn about potential issues

## Rules

- MUST identify the correct startup project (may differ from DbContext project)
- If multiple DbContexts, check each one
- Don't auto-apply migrations - just report status
- Warn if database appears to be production
