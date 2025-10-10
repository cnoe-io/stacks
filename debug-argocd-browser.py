#!/usr/bin/env python3
"""
Playwright Browser Debugging for ArgoCD UI
Tests both local and Codespaces URLs
"""
import os
import sys
import time
from playwright.sync_api import sync_playwright

def debug_argocd_ui():
    """Debug ArgoCD UI access using Playwright"""
    
    # Get URLs
    codespace_name = os.environ.get('CODESPACE_NAME', '')
    github_domain = os.environ.get('GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN', '')
    
    local_url = "https://localhost:8080"
    codespace_url = f"https://{codespace_name}-8080.{github_domain}" if codespace_name else None
    
    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║  Playwright Browser Debugging - ArgoCD UI                    ║")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print()
    
    with sync_playwright() as p:
        # Launch browser with debugging enabled
        print("🚀 Launching Chromium browser...")
        browser = p.chromium.launch(
            headless=True,
            args=['--ignore-certificate-errors', '--disable-web-security']
        )
        
        context = browser.new_context(
            ignore_https_errors=True,
            viewport={'width': 1920, 'height': 1080}
        )
        
        # Enable console logging
        page = context.new_page()
        
        console_messages = []
        errors = []
        
        def handle_console(msg):
            console_messages.append(f"[{msg.type}] {msg.text}")
        
        def handle_page_error(error):
            errors.append(str(error))
        
        page.on("console", handle_console)
        page.on("pageerror", handle_page_error)
        
        # Test 1: Local URL
        print("\n" + "="*65)
        print("TEST 1: Local ArgoCD (https://localhost:8080)")
        print("="*65)
        
        try:
            print(f"⏳ Navigating to {local_url}...")
            response = page.goto(local_url, timeout=15000, wait_until="networkidle")
            
            print(f"   Status: {response.status}")
            print(f"   URL: {page.url}")
            print(f"   Title: {page.title()}")
            
            # Wait a bit for any JavaScript to execute
            time.sleep(2)
            
            # Check page content
            html_content = page.content()
            
            # Analyze the page
            if "Argo CD" in html_content or "argocd" in html_content.lower():
                print("   ✅ ArgoCD UI content detected")
                
                # Check for specific ArgoCD elements
                if page.locator("text=Argo CD").count() > 0:
                    print("   ✅ 'Argo CD' text found on page")
                
                if page.locator("input[name='username']").count() > 0:
                    print("   ✅ Login form detected")
                elif page.locator("#app").count() > 0:
                    print("   ✅ ArgoCD app container found")
                
            else:
                print("   ❌ ArgoCD content not found")
                print(f"   First 500 chars of HTML: {html_content[:500]}")
            
            # Check console messages
            if console_messages:
                print(f"\n   📋 Console Messages ({len(console_messages)}):")
                for msg in console_messages[:10]:  # Show first 10
                    print(f"      {msg}")
            
            # Check errors
            if errors:
                print(f"\n   ❌ JavaScript Errors ({len(errors)}):")
                for error in errors[:5]:  # Show first 5
                    print(f"      {error}")
            
            # Take screenshot
            screenshot_path = "/workspaces/stacks/argocd-local-screenshot.png"
            page.screenshot(path=screenshot_path)
            print(f"\n   📸 Screenshot saved: {screenshot_path}")
            
        except Exception as e:
            print(f"   ❌ Error accessing local URL: {e}")
        
        # Test 2: Codespaces URL
        if codespace_url:
            print("\n" + "="*65)
            print(f"TEST 2: Codespaces URL")
            print("="*65)
            print(f"URL: {codespace_url}")
            
            # Clear previous messages
            console_messages.clear()
            errors.clear()
            
            try:
                print(f"⏳ Navigating to {codespace_url}...")
                response = page.goto(codespace_url, timeout=30000, wait_until="networkidle")
                
                print(f"   Status: {response.status}")
                print(f"   URL: {page.url}")
                print(f"   Title: {page.title()}")
                
                # Wait longer for tunnel authentication
                print("   ⏳ Waiting for GitHub tunnel authentication (15 seconds)...")
                time.sleep(15)
                
                # Check if URL changed (redirect)
                current_url = page.url
                if current_url != codespace_url:
                    print(f"   🔄 Redirected to: {current_url}")
                
                # Check page content
                html_content = page.content()
                
                # Analyze the page
                if "Connecting to the forwarded port" in html_content:
                    print("   ⚠️  Still showing GitHub tunnel authentication page")
                    print("   This indicates the tunnel is not completing")
                    
                    # Check for specific elements
                    if page.locator("#text").count() > 0:
                        status_text = page.locator("#text").inner_text()
                        print(f"   Status text: {status_text}")
                    
                elif "Argo CD" in html_content or "argocd" in html_content.lower():
                    print("   ✅ ArgoCD UI content detected")
                    
                    if page.locator("input[name='username']").count() > 0:
                        print("   ✅ Login form detected")
                    
                else:
                    print("   ❌ Unexpected content")
                    print(f"   First 500 chars: {html_content[:500]}")
                
                # Check console messages
                if console_messages:
                    print(f"\n   📋 Console Messages ({len(console_messages)}):")
                    for msg in console_messages[:10]:
                        print(f"      {msg}")
                
                # Check errors
                if errors:
                    print(f"\n   ❌ JavaScript Errors ({len(errors)}):")
                    for error in errors[:5]:
                        print(f"      {error}")
                
                # Take screenshot
                screenshot_path = "/workspaces/stacks/argocd-codespace-screenshot.png"
                page.screenshot(path=screenshot_path)
                print(f"\n   📸 Screenshot saved: {screenshot_path}")
                
            except Exception as e:
                print(f"   ❌ Error accessing Codespaces URL: {e}")
        
        # Close browser
        browser.close()
        
        print("\n" + "="*65)
        print("🏁 Debugging Complete")
        print("="*65)
        print("\n💡 Recommendations:")
        print("   1. Check screenshots: argocd-local-screenshot.png")
        if codespace_url:
            print("                       argocd-codespace-screenshot.png")
        print("   2. Review console messages and errors above")
        print("   3. Login credentials: admin / developer")
        print()

if __name__ == "__main__":
    try:
        debug_argocd_ui()
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
