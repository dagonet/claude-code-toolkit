# /api-design - Review and Design API Contracts

Review or design REST API contracts following best practices.

## Arguments

- `$ARGUMENTS` - "review" for existing API, or feature name for new design

## Workflow (Review Mode)

1. **Find API controllers**
   - Call `map_dotnet_structure(root)`
   - Search for files in Controllers/ or Endpoints/
   - Read controller files

2. **Analyze endpoints**
   For each endpoint, check:
   - HTTP method appropriateness (GET/POST/PUT/PATCH/DELETE)
   - Route naming (plural nouns, no verbs)
   - Status codes returned
   - Request/Response models
   - Validation attributes

3. **Check REST conventions**
   ```
   ## API Review

   ### Endpoint: GET /api/users/{id}
   ✅ Correct HTTP method for retrieval
   ✅ Proper route naming
   ⚠️ Missing [ProducesResponseType] for 404

   ### Endpoint: POST /api/users/create
   ❌ Route should be POST /api/users (no verb)
   ⚠️ Missing request validation
   ```

4. **Review DTOs**
   - Separate input/output models
   - No domain entities exposed
   - Proper nullability annotations
   - Validation attributes present

5. **Check security**
   - Authentication attributes
   - Authorization policies
   - Input sanitization
   - Rate limiting

6. **Generate recommendations**

## Workflow (Design Mode)

1. **Gather requirements**
   - Parse `$ARGUMENTS` for feature name
   - ASK for:
     - Resources involved
     - Operations needed (CRUD, custom)
     - Authentication requirements

2. **Design resource model**
   ```
   ## Resource: Order

   ### Endpoints
   | Method | Route | Description |
   |--------|-------|-------------|
   | GET | /api/orders | List orders |
   | GET | /api/orders/{id} | Get order by ID |
   | POST | /api/orders | Create order |
   | PUT | /api/orders/{id} | Update order |
   | DELETE | /api/orders/{id} | Delete order |
   | POST | /api/orders/{id}/submit | Submit order |
   ```

3. **Design request/response models**
   ```csharp
   // Request
   public sealed class CreateOrderRequest
   {
       [Required]
       public string CustomerId { get; init; }

       [Required]
       [MinLength(1)]
       public List<OrderItemRequest> Items { get; init; }
   }

   // Response
   public sealed class OrderResponse
   {
       public Guid Id { get; init; }
       public string Status { get; init; }
       public decimal Total { get; init; }
       public DateTime CreatedAt { get; init; }
   }
   ```

4. **Define status codes**
   ```
   | Endpoint | Success | Errors |
   |----------|---------|--------|
   | GET /orders | 200 OK | 401, 403 |
   | GET /orders/{id} | 200 OK | 401, 403, 404 |
   | POST /orders | 201 Created | 400, 401, 403, 422 |
   | DELETE /orders/{id} | 204 No Content | 401, 403, 404 |
   ```

5. **Generate controller skeleton**

## REST Best Practices Checklist

### Naming
- [ ] Use plural nouns for collections (`/users`, not `/user`)
- [ ] Use lowercase with hyphens (`/order-items`)
- [ ] No verbs in URLs (use HTTP methods instead)
- [ ] Nest sub-resources (`/orders/{id}/items`)

### HTTP Methods
- [ ] GET - Read (idempotent, no body)
- [ ] POST - Create (not idempotent)
- [ ] PUT - Full update (idempotent)
- [ ] PATCH - Partial update
- [ ] DELETE - Remove (idempotent)

### Status Codes
- [ ] 200 OK - Success with body
- [ ] 201 Created - Resource created (include Location header)
- [ ] 204 No Content - Success without body
- [ ] 400 Bad Request - Malformed request
- [ ] 401 Unauthorized - Not authenticated
- [ ] 403 Forbidden - Not authorized
- [ ] 404 Not Found - Resource doesn't exist
- [ ] 422 Unprocessable Entity - Validation failed

### Documentation
- [ ] OpenAPI/Swagger annotations
- [ ] XML documentation comments
- [ ] Example requests/responses

## Rules

- MUST follow REST conventions
- MUST NOT expose domain entities directly
- MUST include proper validation
- MUST document all status codes
- MUST consider versioning strategy
