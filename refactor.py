import re

with open('/Users/tan/idea/screenshot/Sources/Capture/OverlayViewModel.swift', 'r') as f:
    code = f.read()

# Replace declaration
code = code.replace('@Published var selectedElementID: UUID? = nil', '@Published var selectedElementIDs: Set<UUID> = []')

# Replace didSet logic for properties
def replace_didset(prop):
    old_code = f"""        didSet {{
            if let id = selectedElementID, let idx = elements.firstIndex(where: {{ $0.id == id }}) {{
                saveState()
                elements[idx].{prop} = {prop}
            }}
        }}"""
    new_code = f"""        didSet {{
            let selectedIdxs = elements.indices.filter {{ selectedElementIDs.contains(elements[$0].id) }}
            if !selectedIdxs.isEmpty {{
                saveState()
                for idx in selectedIdxs {{ elements[idx].{prop} = {prop} }}
            }}
        }}"""
    return code.replace(old_code, new_code)

code = replace_didset('color')
code = replace_didset('isFilled')
code = replace_didset('fillOpacity')
code = replace_didset('fontSize')

# Replace single selection assignments to multiple
code = code.replace('selectedElementID = nil', 'selectedElementIDs.removeAll()')
code = code.replace('selectedElementID = hitElement.id', 'if !isShiftPressed { selectedElementIDs.removeAll() }; selectedElementIDs.insert(hitElement.id)')
code = code.replace('selectedElementID = hit.id', 'if !isShiftPressed { selectedElementIDs.removeAll() }; selectedElementIDs.insert(hit.id)')
code = code.replace('selectedElementID = id', 'selectedElementIDs = [id]')
code = code.replace('selectedElementID = element.id', 'selectedElementIDs = [element.id]')

# Replace "if let id = selectedElementID" with "for id in selectedElementIDs" or similar
# specifically:
code = code.replace('if let id = self.selectedElementID, let el = self.elements.first(where: { $0.id == id }), el.type != .select {',
                    'if let id = self.selectedElementIDs.first, let el = self.elements.first(where: { $0.id == id }), el.type != .select {')

code = code.replace('if let id = selectedElementID, let element = elements.first(where: { $0.id == id }), element.hasBindingPoints {',
                    'if let id = selectedElementIDs.first, let element = elements.first(where: { $0.id == id }), element.hasBindingPoints {')

code = code.replace('if selectedTool != .select || selectedElementID != nil {',
                    'if selectedTool != .select || !selectedElementIDs.isEmpty {')

code = code.replace('if selectedElementID == id {',
                    'if selectedElementIDs.contains(id) {')

code = code.replace('if let id = selectedElementID {',
                    'if let id = selectedElementIDs.first {')

code = code.replace('if let id = selectedElementID, let el = elements.first(where: { $0.id == id }) {',
                    'if let id = selectedElementIDs.first, let el = elements.first(where: { $0.id == id }) {')

code = code.replace('if let id = selectedElementID { targetIds.insert(id) }',
                    'for id in selectedElementIDs { targetIds.insert(id) }')

code = code.replace('if selectedTool == .select, selectedElementID == id {',
                    'if selectedTool == .select, selectedElementIDs.contains(id) {')

code = code.replace('if !handledBindingPoint, selectedTool == .select, let selectedId = selectedElementID, let el = elements.first(where: { $0.id == selectedId }) {',
                    'if !handledBindingPoint, selectedTool == .select, let selectedId = selectedElementIDs.first, let el = elements.first(where: { $0.id == selectedId }) {')

code = code.replace('dragMode = .movingElement(hitElement.id, original: hitElement)',
                    'let originals = elements.filter { selectedElementIDs.contains($0.id) }\ndragMode = .movingElements(originals)')

code = code.replace('case movingElement(UUID, original: AnnotationElement)',
                    'case movingElements([AnnotationElement])')

with open('/Users/tan/idea/screenshot/Sources/Capture/OverlayViewModel.swift', 'w') as f:
    f.write(code)

