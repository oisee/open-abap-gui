import {Config, MemoryFile, Registry, SyntaxLogic} from "@abaplint/core";

// Preserve the parsed source span for statements that the native ABAP frontend
// lowers itself. Rename selection-screen references identified by abaplint's
// syntax resolver; SQL columns and locally shadowed variables keep their names.
export const NATIVE_STATEMENTS = new Set([
  "Select", "SelectLoop", "EndSelect", "Commit", "Rollback",
  "OpenDataset", "ReadDataset", "CloseDataset", "GetDataset", "Transfer",
]);

function offset(source, position) {
  const lines = source.split("\n");
  let result = 0;
  for (let i = 1; i < position.row; i++) result += lines[i - 1].length + 1;
  return result + position.col - 1;
}

function positionKey(filename, position) {
  return `${filename}:${position.row}:${position.col}`;
}

export function resolvedSelectionPositions(parsed, selectionState) {
  const declarations = new Set();
  for (const unit of parsed.units) {
    for (const statement of unit.statements) {
      if (!["Parameter", "SelectOption"].includes(statement.kind)) continue;
      for (const token of statement.node.getTokens()) {
        if (selectionState?.[token.getStr().toUpperCase()]) {
          declarations.add(positionKey(unit.filename, token.getStart()));
        }
      }
    }
  }
  const registry = new Registry(parsed.config ?? Config.getDefault());
  for (const unit of parsed.units) registry.addFile(new MemoryFile(unit.filename, unit.source));
  registry.parse();
  const references = new Set();
  const scopes = [];
  for (const object of registry.getObjects()) {
    const syntax = new SyntaxLogic(registry, object).run();
    scopes.push(syntax.spaghetti);
    for (const scope of syntax.spaghetti.allNodes()) {
      for (const reference of scope.getData().references) {
        if (!reference.resolved || !["Read From", "Write To"].includes(reference.referenceType)) continue;
        if (!declarations.has(positionKey(reference.resolved.getFilename(), reference.resolved.getStart()))) continue;
        references.add(positionKey(reference.position.getFilename(), reference.position.getStart()));
      }
    }
  }
  return {references, scopes, declarations};
}

function selectionTokens(node, selections, filename, resolution) {
  const result = [];
  const visit = (part, ancestors = []) => {
    const children = part.getChildren?.() ?? [];
    const kind = part.get?.()?.constructor?.name ?? part.constructor.name;
    if (children.length) {
      for (const child of children) visit(child, [...ancestors, kind]);
      return;
    }
    const token = part.getFirstToken?.();
    const name = token?.getStr?.().toUpperCase();
    if (!selections.has(name) || !token?.getStart) return;
    if (ancestors.some((entry) => ["SQLFieldName", "SQLFromSource", "DatabaseTable"].includes(entry))) return;
    if (ancestors.includes("Select") && !ancestors.some((entry) =>
      ["SQLSource", "SQLTarget", "TargetField", "FieldChain"].includes(entry))) return;
    const key = positionKey(filename, token.getStart());
    if (!resolution.references.has(key)) {
      // A few abaplint statement visitors (GET DATASET, for example) omit a
      // data reference. Resolve their parsed operand in its lexical scope.
      const variable = resolution.scopes.map((scope) => scope.lookupPosition(token.getStart(), filename)?.findVariable(name)).find(Boolean);
      if (!variable || !resolution.declarations.has(positionKey(variable.getFilename(), variable.getStart()))) return;
    }
    result.push({position: token.getStart(), name, length: token.getStr().length});
  };
  visit(node);
  return result;
}

export function nativeStatementText(statement, source, selectionState, resolution) {
  const start = statement.span.startOffset;
  const end = statement.span.endOffset;
  let text = source.slice(start, end);
  const selections = new Map(Object.entries(selectionState ?? {}).map(([name, state]) => [name.toUpperCase(), state.member]));
  const edits = selectionTokens(statement.node, selections, statement.filename, resolution);
  for (const edit of edits.sort((a, b) => offset(source, b.position) - offset(source, a.position))) {
    const at = offset(source, edit.position) - start;
    text = text.slice(0, at) + selections.get(edit.name) + text.slice(at + edit.length);
  }
  return text;
}
