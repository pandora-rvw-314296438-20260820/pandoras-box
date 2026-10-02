# Edge boot artifact (B1)

`chat-slim.b64.txt` is gzip+base64 of an ESM-safe slim `pandora-intelligence-chat` bundle
(no CJS default imports). Used by the production edge loader while the full multi-file
deploy payload exceeds MCP argument size limits.

Do not import from app code. Safe to delete once an embedded deploy lands.
