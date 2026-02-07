# Integration Tests

End-to-end tests that verify:

1. Server starts and serves static files
2. WebSocket connections are established
3. Creating an incident via the API stores it in SQLite
4. Events sync between multiple clients
5. Authority-based conflict resolution works over the wire

These tests require the full server binary and will be added in Phase 2.
