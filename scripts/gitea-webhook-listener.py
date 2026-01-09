#!/usr/bin/env python3
"""
Gitea Webhook Listener for Real-Time Change Notifications

Receives push webhooks from Gitea and displays commit information in the terminal.
Used by devenv to show real-time deployment activity.

Usage:
    python3 gitea-webhook-listener.py

Environment Variables:
    GITEA_WEBHOOK_PORT  - Port to listen on (default: 9999)
    GITEA_WEBHOOK_SECRET - Shared secret for signature verification (optional)
"""

import json
import os
import sys
import hmac
import hashlib
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

# Configuration
PORT = int(os.environ.get('GITEA_WEBHOOK_PORT', 9999))
SECRET = os.environ.get('GITEA_WEBHOOK_SECRET', '')

# ANSI Colors
RESET = '\033[0m'
BOLD = '\033[1m'
DIM = '\033[2m'
GREEN = '\033[0;32m'
BLUE = '\033[0;34m'
YELLOW = '\033[1;33m'
CYAN = '\033[0;36m'
MAGENTA = '\033[0;35m'


def log_timestamp():
    """Return formatted timestamp."""
    return datetime.now().strftime('%H:%M:%S')


def extract_app_name(repo_name):
    """Extract app name from idpbuilder repo name.

    Example: giteaAdmin/idpbuilder-thinkpad-backstage -> backstage
    """
    parts = repo_name.split('/')[-1]  # Get repo name without owner
    if parts.startswith('idpbuilder-'):
        # Remove idpbuilder- prefix and cluster name
        # idpbuilder-thinkpad-backstage -> backstage
        segments = parts.split('-')
        if len(segments) >= 3:
            return '-'.join(segments[2:])  # Join remaining parts (handles multi-word app names)
    return parts


def verify_signature(payload, signature):
    """Verify Gitea webhook signature if secret is configured."""
    if not SECRET:
        return True

    if not signature:
        return False

    expected = 'sha256=' + hmac.new(
        SECRET.encode('utf-8'),
        payload,
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(expected, signature)


class WebhookHandler(BaseHTTPRequestHandler):
    """HTTP request handler for Gitea webhooks."""

    def log_message(self, format, *args):
        """Suppress default HTTP logging."""
        pass

    def do_POST(self):
        """Handle POST requests (webhook payloads)."""
        try:
            # Read payload
            content_length = int(self.headers.get('Content-Length', 0))
            payload = self.rfile.read(content_length)

            # Verify signature if configured
            signature = self.headers.get('X-Gitea-Signature', '')
            if not verify_signature(payload, signature):
                print(f"{YELLOW}[{log_timestamp()}]{RESET} {DIM}Rejected: Invalid signature{RESET}")
                self.send_response(401)
                self.end_headers()
                return

            # Parse JSON
            data = json.loads(payload.decode('utf-8'))

            # Get event type
            event_type = self.headers.get('X-Gitea-Event', 'unknown')

            if event_type == 'push':
                self.handle_push_event(data)
            else:
                print(f"{DIM}[{log_timestamp()}] Ignored event: {event_type}{RESET}")

            # Send success response
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')

        except json.JSONDecodeError as e:
            print(f"{YELLOW}[{log_timestamp()}]{RESET} JSON parse error: {e}")
            self.send_response(400)
            self.end_headers()
        except Exception as e:
            print(f"{YELLOW}[{log_timestamp()}]{RESET} Error: {e}")
            self.send_response(500)
            self.end_headers()

    def do_GET(self):
        """Handle GET requests (health check)."""
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'Gitea Webhook Listener OK')

    def handle_push_event(self, data):
        """Handle push event and display commit information."""
        repo = data.get('repository', {})
        repo_name = repo.get('full_name', 'unknown')
        app_name = extract_app_name(repo_name)

        commits = data.get('commits', [])
        ref = data.get('ref', '').replace('refs/heads/', '')
        pusher = data.get('pusher', {}).get('username', 'unknown')

        if not commits:
            # Handle force push or other scenarios without commits
            print(f"\n{CYAN}[{log_timestamp()}]{RESET} {GREEN}{BOLD}{app_name}{RESET} {DIM}({ref}){RESET}")
            print(f"  {DIM}Push by {pusher} (no commits){RESET}")
            return

        # Display header
        print(f"\n{CYAN}[{log_timestamp()}]{RESET} {GREEN}{BOLD}{app_name}{RESET} {DIM}({ref}){RESET}")

        # Display each commit
        for commit in commits:
            sha = commit.get('id', '')[:7]
            message = commit.get('message', '').split('\n')[0]  # First line only
            author = commit.get('author', {}).get('name', 'unknown')

            # Truncate message if too long
            if len(message) > 60:
                message = message[:57] + '...'

            print(f"  {YELLOW}{sha}{RESET} {message}")

            # Show files changed (if available)
            added = commit.get('added', [])
            modified = commit.get('modified', [])
            removed = commit.get('removed', [])

            if added or modified or removed:
                changes = []
                if added:
                    changes.append(f"+{len(added)}")
                if modified:
                    changes.append(f"~{len(modified)}")
                if removed:
                    changes.append(f"-{len(removed)}")
                print(f"  {DIM}by {author} ({', '.join(changes)} files){RESET}")
            else:
                print(f"  {DIM}by {author}{RESET}")

        # Flush output immediately
        sys.stdout.flush()


class ReuseAddrHTTPServer(HTTPServer):
    """HTTPServer with SO_REUSEADDR to allow quick restarts."""
    allow_reuse_address = True


def main():
    """Start the webhook listener server."""
    print(f"{GREEN}{BOLD}Gitea Webhook Listener{RESET}")
    print(f"{DIM}Listening on port {PORT}...{RESET}")
    if SECRET:
        print(f"{DIM}Signature verification: enabled{RESET}")
    else:
        print(f"{DIM}Signature verification: disabled{RESET}")
    print()
    print(f"{DIM}Waiting for push events...{RESET}")
    print()

    server = ReuseAddrHTTPServer(('0.0.0.0', PORT), WebhookHandler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print(f"\n{DIM}Shutting down...{RESET}")
        server.shutdown()


if __name__ == '__main__':
    main()
