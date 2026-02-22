# /godot-run - Run Godot Project

Run a Godot project and capture debug output using MCP Godot tools.

## Arguments

- `$ARGUMENTS` - Path to Godot project directory (optional)

## Workflow

1. **Locate project**
   - If path provided in `$ARGUMENTS`, use it
   - Otherwise, call `list_projects(directory, recursive=true)` to find projects
   - If multiple projects found, ASK user which one

2. **Get project info**
   - Call `get_project_info(projectPath)`
   - Confirm project name and main scene

3. **Run project**
   - Call `run_project(projectPath)`
   - Wait briefly for startup

4. **Monitor output**
   - Call `get_debug_output()` repeatedly to capture logs
   - Look for errors, warnings, or expected output
   - Continue until user signals stop or error occurs

5. **Stop project**
   - Call `stop_project()` when done
   - ALWAYS stop the project, even if errors occurred

6. **Report results**
   - Summarize what was observed
   - Highlight any errors or warnings
   - Note any expected behavior that was confirmed

## Rules

- MUST use MCP Godot tools, NOT direct `godot.exe` calls
- MUST ALWAYS call `stop_project()` when finished
- MUST use absolute Windows paths in tool arguments
- If Godot is not found, inform user to set `GODOT_PATH`
