---
paths:
  - "**/*.xaml"
  - "**/*.xaml.cs"
---

# XAML / MAUI UI Conventions

- When adding UI behaviors (e.g., CommunityToolkit.Maui), verify the required NuGet package and namespace imports are in place
- When modifying XAML, verify ContentPage namespace declarations include all referenced assemblies
- For UI changes, publish the MAUI app and run smoke tests before claiming complete
