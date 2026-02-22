# /add-tests - Generate Unit Tests

Generate unit tests for existing code with proper coverage.

## Arguments

- `$ARGUMENTS` - Path to file/class to test, or feature area

## Workflow

1. **Locate target code**
   - If path provided in `$ARGUMENTS`, read that file
   - Otherwise, call `map_dotnet_structure(root)` to find source files
   - ASK user which class/method to test if unclear

2. **Analyze the code**
   - Read the target file(s)
   - Identify:
     - Public methods to test
     - Dependencies to mock
     - Edge cases and boundary conditions
     - Exception scenarios

3. **Find existing test patterns**
   - Call `map_dotnet_structure(root)` to find test projects
   - Read existing tests to understand:
     - Test framework (xUnit, NUnit, MSTest)
     - Mocking library (Moq, NSubstitute, FakeItEasy)
     - Naming conventions (e.g., `MethodName_Scenario_ExpectedResult`)
     - Arrange-Act-Assert patterns used

4. **Plan test cases**
   ```
   ## Tests for [ClassName]

   ### [MethodName]
   - [ ] Should_ReturnSuccess_WhenValidInput
   - [ ] Should_ThrowException_WhenNullArgument
   - [ ] Should_ReturnEmpty_WhenNoDataFound
   ```

5. **Get approval**
   - Present test plan to user
   - ASK for confirmation before creating

6. **Generate test file**
   - Create test class following existing patterns
   - Include:
     - Constructor with mock setup
     - One test method per scenario
     - Clear Arrange/Act/Assert sections
     - Descriptive test names

7. **Verify tests compile**
   - Call `build_and_extract_errors` for the test project
   - Fix any compilation errors

8. **Run tests**
   - Call `run_tests_summary` to verify tests pass
   - Report results

## Test Template

```csharp
public class [ClassName]Tests
{
    private readonly Mock<IDependency> _mockDependency;
    private readonly [ClassName] _sut;

    public [ClassName]Tests()
    {
        _mockDependency = new Mock<IDependency>();
        _sut = new [ClassName](_mockDependency.Object);
    }

    [Fact]
    public void MethodName_Scenario_ExpectedResult()
    {
        // Arrange

        // Act

        // Assert
    }
}
```

## Rules

- MUST follow existing test patterns and conventions
- MUST use the same test framework as existing tests
- MUST mock external dependencies
- MUST NOT modify production code (only create tests)
- Test names MUST be descriptive and follow conventions
