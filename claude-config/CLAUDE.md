# Global Claude Instructions

See AGENTS.md for agent-specific instructions.

## Interactive Testing Workflow

**CRITICAL**: Always test UI features interactively in the browser before marking them complete.

### Testing Browser Features

When implementing browser-based features (HTML/CSS/JavaScript):

1. **Automated Tests Are Not Enough**
   - Playwright headless tests verify functionality but not visual appearance
   - UI bugs, rendering issues, and interaction problems require visual inspection

2. **Use Browser Automation MCP Tools**
   - Available tools: `mcp__claude-in-chrome__*`
   - Get tab context: `tabs_context_mcp(createIfEmpty=true)`
   - Navigate: `navigate(tabId, url)`
   - Screenshot: `computer(action='screenshot', tabId)`
   - Interact: `computer(action='left_click', tabId, coordinate)`
   - Execute JS: `javascript_tool(action='javascript_exec', tabId, text)`

3. **Interactive Testing Checklist**
   ```
   [ ] Load the page and take a screenshot
   [ ] Verify new UI elements are visible
   [ ] Test each interactive control (buttons, dropdowns, toggles)
   [ ] Verify visual appearance matches design
   [ ] Test with real data (not just test fixtures)
   [ ] Check browser console for errors
   [ ] Verify expected behavior at each step
   [ ] Document any visual issues found
   ```

4. **Example Testing Flow**
   ```javascript
   // 1. Get tabs and navigate
   tabs_context_mcp(createIfEmpty=true)
   navigate(tabId, 'http://localhost:8765/demo.html')

   // 2. Take initial screenshot
   screenshot(tabId)

   // 3. Interact with UI
   left_click(tabId, [100, 200])  // Click button
   wait(tabId, 2)

   // 4. Verify state changed
   javascript_tool(tabId, 'document.querySelector("#status").textContent')
   screenshot(tabId)

   // 5. Check console for errors
   read_console_messages(tabId, onlyErrors=true)
   ```

5. **When to Test Interactively**
   - After implementing new UI features
   - After making visual changes (CSS, layout)
   - After adding interactive controls
   - Before marking features as complete
   - When user reports visual issues

6. **Document Testing**
   - Note what was tested in commit messages
   - Save screenshots of verified states
   - Report any issues found during testing
