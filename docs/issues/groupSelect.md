**Is your feature request related to a problem? Please describe.**
Currently, users can only select and move one shape at a time. When working with complex annotations or multiple shapes, moving them individually is tedious and time-consuming.

**Describe the solution you'd like**
I would like to add the ability to select multiple shapes at once and move them as a group. This includes:
1. Using `Shift` or `Cmd` (on macOS) / `Ctrl` (on Windows) + Left Click to select/deselect multiple individual shapes.
2. The ability to drag and move all currently selected shapes simultaneously.

**Checklist**
- [ ] Implement multi-selection logic using `Shift` + Click and `Cmd`/`Ctrl` + Click.
- [ ] Add visual feedback for multi-selected shapes (e.g., bounding boxes or highlight borders around all selected items).
- [ ] Implement group dragging functionality to move all selected shapes together.
- [ ] Ensure proper state updates for all moved shapes.
- [ ] (Optional) Add a "Clear Selection" shortcut or behavior when clicking on an empty area of the canvas.