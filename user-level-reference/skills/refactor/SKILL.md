---
name: refactor
description: Identifies code quality issues and suggests refactoring. Triggers on requests to clean up, improve, or refactor code.
---

# Refactor Skill

Identify code quality issues and refactor problematic code.

## When to Use

This skill auto-activates when:
- User asks to "refactor", "clean up", or "improve" code
- User mentions "code smell", "technical debt", or "messy code"
- User asks about code quality or maintainability
- User wants to simplify or restructure existing code

## Workflow

1. **Identify scope**
   - If path provided, focus on that area
   - If "all" or empty, analyze entire solution

2. **Run quality analysis** (in parallel)
   - Call `analyze_method_complexity(root, threshold=10)`
   - Call `find_god_classes(root, method_threshold=20, field_threshold=15)`
   - Call `find_large_files(root, line_threshold=500)`
   - Call `analyze_namespace_conflicts(root)`

3. **Compile findings**
   ```
   ## Code Quality Report

   ### Critical Issues
   - [File:Line] Method complexity: X (threshold: 10)

   ### High Priority
   - [File] God class: X methods, Y fields

   ### Medium Priority
   - [File] Large file: X lines

   ### Conflicts
   - [Type] defined in multiple locations
   ```

4. **Prioritize refactoring**
   - CRITICAL: Namespace conflicts (blocks compilation)
   - HIGH: God classes (maintainability risk)
   - MEDIUM: Complex methods (bug risk)
   - LOW: Large files (readability)

5. **Propose refactoring strategy**
   For each issue, suggest specific refactoring:

   **Complex methods:**
   - Extract Method
   - Replace Conditional with Polymorphism
   - Introduce Parameter Object

   **God classes:**
   - Extract Class
   - Extract Interface
   - Move Method/Field

   **Large files:**
   - Split into partial classes
   - Extract nested classes
   - Move to separate files

6. **Get approval**
   - Present refactoring plan
   - ASK which items to address

7. **Execute refactoring**
   - Make changes incrementally
   - After each change:
     - Call `build_and_extract_errors` to verify compilation
     - Call `run_tests_summary` to verify tests pass

8. **Verify improvements**
   - Re-run quality analysis
   - Show before/after metrics

## Refactoring Patterns

### Extract Method
```csharp
// Before: Long method with multiple responsibilities
// After: Small focused methods with clear names
```

### Extract Class
```csharp
// Before: Class with 30 methods
// After: Multiple cohesive classes with single responsibility
```

### Replace Conditionals
```csharp
// Before: switch/if-else chains
// After: Strategy pattern or polymorphism
```

## Rules

- MUST run tests after each refactoring step
- MUST NOT change behavior (refactoring only)
- MUST preserve public API unless explicitly approved
- MUST follow existing code conventions
- Small, incremental changes over big-bang refactoring
